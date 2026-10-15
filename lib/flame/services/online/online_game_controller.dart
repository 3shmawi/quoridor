import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/online_session.dart';
import '../game_service.dart';
import '../identity_service.dart';
import 'online_game_service.dart';

/// How this device is faring in an online game.
enum OnlineConnectionState {
  /// Creating or joining a game.
  connecting,

  /// In a game, waiting for the remaining seats to fill.
  waitingForOpponent,

  /// Every player present and the game is live.
  live,

  /// At least one other player has stopped reporting in.
  opponentAway,

  /// This device has lost contact with the backend.
  offline,

  /// The session ended, cleanly or otherwise.
  ended,
}

/// Owns one online game for as long as the player is in it.
///
/// This is deliberately the only thing that talks to [OnlineGameService] from
/// the UI: it holds the session, keeps presence fresh, re-validates moves that
/// arrive from the opponent, and exposes a single listenable state for the
/// screens to render.
class OnlineGameController extends ChangeNotifier {
  OnlineGameController({OnlineGameService? service})
    : _service = service ?? OnlineGameService.instance;

  final OnlineGameService _service;

  /// How often this device reports that it is still here.
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// How stale an opponent's heartbeat may get before they are shown as away.
  /// Three missed beats, so one slow round trip does not raise a false alarm.
  static const Duration presenceTimeout = Duration(seconds: 35);

  OnlineSession? _session;
  OnlineConnectionState _connection = OnlineConnectionState.connecting;
  String? _message;
  bool _submitting = false;
  bool _rematching = false;
  bool _disposed = false;

  /// True while a move is shown locally but not yet confirmed by the server.
  bool _pendingLocalMove = false;

  /// The game as the server last sent it, whatever is on screen.
  ///
  /// A refused move falls back to this. Falling back to the board from when
  /// the move was made instead threw away anything that had arrived since,
  /// such as the very move that made this one stale.
  OnlineGame? _serverGame;

  StreamSubscription<OnlineGame>? _subscription;
  Timer? _heartbeat;
  Timer? _presenceTicker;

  /// Fires when a move lands that this device did not make, so the game can
  /// apply it and play its sound.
  void Function(GameState board)? onRemoteUpdate;

  /// Fires when the game ends, with true if this device won.
  void Function(bool didWin)? onGameOver;

  OnlineSession? get session => _session;
  OnlineGame? get game => _session?.game;
  OnlineConnectionState get connection => _connection;

  /// The last thing worth telling the player, if anything, in English.
  String? get message => _message;

  /// What went wrong, when [message] is a failure. Screens show this in the
  /// player's language rather than [message] as it is.
  OnlineFailure? get failure => _failure;
  OnlineFailure? _failure;

  void _fail(OnlineResult<Object?> result) {
    _failure = result.failure;
    _message = result.message;
  }

  bool get isSubmitting => _submitting;
  bool get isActive => _session != null;
  bool get isLocalTurn => (_session?.isLocalTurn ?? false) && !_submitting;
  int? get localPlayerId => _session?.localPlayerId;
  String? get roomCode => _session?.game.roomCode;

  /// The first other player who has stopped reporting in, if any.
  OnlinePlayer? get awayPlayer {
    final session = _session;
    if (session == null) return null;
    final now = DateTime.now();
    for (final player in session.opponents) {
      final lastSeen = player.lastSeen;
      if (lastSeen == null || now.difference(lastSeen) > presenceTimeout) {
        return player;
      }
    }
    return null;
  }

  /// A rematch somebody else offered on the finished game, waiting to be
  /// joined.
  RematchLink? get rematchOffer {
    final session = _session;
    if (session == null || !session.game.isOver) return null;
    final link = session.game.rematch;
    if (link == null || link.by == session.localPlayerId) return null;
    return link;
  }

  /// Whether this device can ask for, or join, a rematch right now.
  bool get canRematch {
    final session = _session;
    return session != null &&
        session.isParticipant &&
        session.game.isOver &&
        !_rematching;
  }

  bool get isRematching => _rematching;

  /// Moves this table on to a new game once the current one has ended.
  ///
  /// The finished game cannot be reused: its move log is append-only, so a
  /// second game would collide with the first one's moves. Instead the first
  /// to ask creates a fresh game, seated first, and links it from the old
  /// one; everyone else sees the link and joins it by its code. When two ask
  /// at once, the first link stands and the second player's own new game is
  /// abandoned in favour of joining it.
  Future<bool> requestRematch() async {
    final session = _session;
    if (!canRematch || session == null) return false;

    _rematching = true;
    notifyListeners();
    try {
      final offered = session.game.rematch;
      if (offered != null) return await _joinRematch(offered);

      final created = await _service.createPrivateGame(
        playerCount: session.game.playerCount,
      );
      final mine = created.value;
      if (!created.isSuccess || mine == null) {
        _fail(created);
        return false;
      }

      final standing = await _service.offerRematch(
        session.game.gameId,
        RematchLink(
          gameId: mine.game.gameId,
          roomCode: mine.game.roomCode,
          by: session.localPlayerId!,
        ),
      );
      final link = standing.value;
      if (!standing.isSuccess || link == null) {
        await _service.abandon(mine.game.gameId);
        _fail(standing);
        return false;
      }
      if (link.gameId != mine.game.gameId) {
        await _service.abandon(mine.game.gameId);
        return await _joinRematch(link);
      }

      return _adopt(created);
    } finally {
      _rematching = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _joinRematch(RematchLink link) async =>
      _adopt(await _service.joinByCode(link.roomCode));

  /// The player whose turn it is, as the server names them.
  OnlinePlayer? get playerToMove {
    final game = _session?.game;
    return game?.players[game.currentPlayerId];
  }

  /// Creates a game for [playerCount] people and starts watching it.
  Future<bool> createGame({int playerCount = 2}) async {
    _setConnection(OnlineConnectionState.connecting);
    final result = await _service.createPrivateGame(playerCount: playerCount);
    return _adopt(result);
  }

  /// Joins the game carrying [code] and starts watching it.
  Future<bool> joinGame(String code) async {
    _setConnection(OnlineConnectionState.connecting);
    final result = await _service.joinByCode(code);
    return _adopt(result);
  }

  /// Rejoins a game this device is already a player in.
  Future<bool> resumeGame(String gameId) async {
    _setConnection(OnlineConnectionState.connecting);
    final result = await _service.resume(gameId);
    return _adopt(result);
  }

  bool _adopt(OnlineResult<OnlineSession> result) {
    if (_disposed) return false;

    if (!result.isSuccess || result.value == null) {
      _fail(result);
      _setConnection(OnlineConnectionState.offline);
      return false;
    }

    _session = result.value;
    _serverGame = result.value!.game;
    _message = null;
    _failure = null;
    _startWatching();
    _refreshConnection();
    // A rematch replaces the board on screen, which no move will announce.
    onRemoteUpdate?.call(result.value!.game.board);
    return true;
  }

  void _startWatching() {
    final gameId = _session?.game.gameId;
    final seat = _session?.localPlayerId;
    if (gameId == null || seat == null) return;

    _subscription?.cancel();
    _subscription = _service
        .watchGame(gameId)
        .listen(_onGameChanged, onError: _onStreamError);

    // Report in immediately, then keep reporting.
    unawaited(_service.heartbeat(gameId, seat));
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_service.heartbeat(gameId, seat));
    });

    // The opponent going quiet is not an event, it is the absence of one, so
    // it has to be noticed on a timer rather than from the stream.
    _presenceTicker?.cancel();
    _presenceTicker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshConnection(),
    );
  }

  void _onGameChanged(OnlineGame game) {
    if (_disposed) return;

    final previous = _session;
    _serverGame = game;

    // While this device's move is on its way, the server can still send the
    // game from before it: every player's heartbeat rewrites the document
    // every few seconds. Taking that board took the move back off the screen
    // until the server caught up, so it vanished and came back, and its
    // sound played twice. Until the server is at least as far along as the
    // screen, only its presence is taken; the board stays as shown.
    if (_pendingLocalMove &&
        previous != null &&
        game.moveCount < previous.game.moveCount) {
      _session = previous.copyWith(
        game: _withBoard(game, previous.game.board, previous.game.moveCount),
      );
      _refreshConnection();
      return;
    }

    final identity = IdentityService.instance.current;
    _session = identity == null
        ? previous?.copyWith(game: game)
        : OnlineSession.forUid(game, identity.uid);

    // The server's copy is the truth, so it always replaces what is on
    // screen -- including when it is simply confirming the move this device
    // already showed optimistically.
    final moved = previous != null && game.moveCount != previous.game.moveCount;
    if (_pendingLocalMove && game.moveCount >= previous!.game.moveCount) {
      _pendingLocalMove = false;
    }
    if (moved || _pendingLocalMove) onRemoteUpdate?.call(game.board);

    // A rematch offered on a finished game changes nothing else, so nothing
    // below would tell the screen about it.
    if (game.rematch != previous?.game.rematch) notifyListeners();

    if (game.isOver && (previous == null || !previous.game.isOver)) {
      final didWin = _session?.didWin;
      _setConnection(OnlineConnectionState.ended);
      if (didWin != null) onGameOver?.call(didWin);
      notifyListeners();
      return;
    }

    _refreshConnection();
  }

  void _onStreamError(Object error) {
    debugPrint('OnlineGameController: stream error: $error');
    _message = 'Lost contact with the game';
    _failure = OnlineFailure.backendError;
    _setConnection(OnlineConnectionState.offline);
  }

  /// Submits [move] on behalf of the local player.
  ///
  /// The move is shown immediately and sent in the background. Waiting for the
  /// server to echo it back put a whole round trip between the tap and the
  /// board changing, which reads as the game being slow even on a good
  /// connection.
  ///
  /// Showing it first is safe because the move was already validated against
  /// the same rules the server applies, and the write is guarded by the move
  /// counter: if the server refuses, [_rollback] puts the confirmed board back
  /// and the listener delivers the truth either way.
  Future<bool> submitMove(GameMove move) async {
    final session = _session;
    if (session == null || _submitting) return false;

    final confirmed = session.game;
    if (!GameService.isValidMove(confirmed.board, move)) return false;
    _submitting = true;

    try {
      _applyOptimistically(move);

      final result = await _service.submitMove(session, move);

      if (!result.isSuccess) {
        _rollback(_serverGame ?? confirmed);
        _fail(result);
        return false;
      }

      _message = null;
      _failure = null;
      return true;
    } finally {
      _submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Shows [move] on this device before the server has confirmed it.
  void _applyOptimistically(GameMove move) {
    final session = _session;
    if (session == null) return;

    // The real rules, not the engine's shortcut: that drops the move history
    // to keep its search cheap, which emptied the move list while a move was
    // in flight and made every earlier move sound again once it landed.
    final board = GameService.executeMove(session.game.board, move);
    _pendingLocalMove = true;
    _session = session.copyWith(
      game: _withBoard(session.game, board, session.game.moveCount + 1),
    );
    onRemoteUpdate?.call(board);
    notifyListeners();
  }

  /// Puts back the server's game in place of a refused move.
  void _rollback(OnlineGame confirmed) {
    _pendingLocalMove = false;
    _session = _session?.copyWith(game: confirmed);
    onRemoteUpdate?.call(confirmed.board);
    notifyListeners();
  }

  static OnlineGame _withBoard(OnlineGame game, GameState board, int count) =>
      OnlineGame(
        rematch: game.rematch,
        gameId: game.gameId,
        roomCode: game.roomCode,
        status: game.status,
        players: game.players,
        playerCount: game.playerCount,
        currentPlayerId: board.currentPlayerId,
        moveCount: count,
        board: board,
        winnerPlayerId: game.winnerPlayerId,
        outcomeReason: game.outcomeReason,
        updatedAt: game.updatedAt,
      );

  /// Leaves the game, marking this device away.
  Future<void> leave({bool abandon = false}) async {
    final session = _session;
    if (session != null) {
      final gameId = session.game.gameId;
      final seat = session.localPlayerId;
      if (seat != null) await _service.markAway(gameId, seat);
      if (abandon && !session.game.isOver) await _service.abandon(gameId);
    }
    _teardown();
    _session = null;
    _setConnection(OnlineConnectionState.ended);
  }

  /// Recomputes the connection state from the current game and presence.
  void _refreshConnection() {
    final session = _session;
    if (session == null) return;

    final game = session.game;

    if (game.isOver) {
      _setConnection(OnlineConnectionState.ended);
      return;
    }
    if (!game.isFull) {
      _setConnection(OnlineConnectionState.waitingForOpponent);
      return;
    }

    _setConnection(
      awayPlayer != null
          ? OnlineConnectionState.opponentAway
          : OnlineConnectionState.live,
    );
  }

  void _setConnection(OnlineConnectionState value) {
    if (_connection == value) return;
    _connection = value;
    if (!_disposed) notifyListeners();
  }

  /// Clears the last message once the UI has shown it.
  void consumeMessage() {
    if (_message == null) return;
    _message = null;
    _failure = null;
    notifyListeners();
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _presenceTicker?.cancel();
    _presenceTicker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    super.dispose();
  }
}
