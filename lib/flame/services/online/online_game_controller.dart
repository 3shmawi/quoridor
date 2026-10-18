import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/online_chat.dart';
import '../../models/online_session.dart';
import '../game_service.dart';
import '../turn_clock.dart';
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
  OnlineGameController({OnlineGameService? service, DateTime Function()? now})
    : _service = service ?? OnlineGameService.instance,
      _now = now ?? DateTime.now;

  final OnlineGameService _service;
  final DateTime Function() _now;

  /// The shortest gap between two messages from this device, so a reaction
  /// stays a reaction rather than a flood of them.
  static const Duration chatCooldown = Duration(milliseconds: 1200);

  /// How often this device reports that it is still here.
  static const Duration heartbeatInterval = Duration(seconds: 10);

  /// How stale an opponent's heartbeat may get before they are shown as away.
  /// Three missed beats, so one slow round trip does not raise a false alarm.
  static const Duration presenceTimeout = Duration(seconds: 35);

  /// How long the other player of a two-player game must have been gone
  /// before the win can be claimed from them. The Security Rules hold out
  /// for a minute by the server's clock; a few seconds more here allows for
  /// this device's clock being ahead of it.
  static const Duration claimAfter = Duration(seconds: 65);

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
  StreamSubscription<List<ChatMessage>>? _chatSubscription;
  Timer? _heartbeat;
  Timer? _presenceTicker;

  /// Fires when a move lands that this device did not make, so the game can
  /// apply it and play its sound.
  void Function(GameState board)? onRemoteUpdate;

  /// Fires when the game ends, with true if this device won, false if it
  /// lost, and null for a draw.
  void Function(bool? didWin)? onGameOver;

  /// Fires when the other player offers this device a draw.
  void Function()? onDrawOffered;

  /// Fires when the other player turns down this device's draw offer.
  void Function()? onDrawDeclined;

  OnlineSession? get session => _session;
  OnlineGame? get game => _session?.game;
  OnlineConnectionState get connection => _connection;

  /// The last thing worth telling the player, if anything, in English.
  String? get message => _message;

  /// What went wrong, when [message] is a failure. Screens show this in the
  /// player's language rather than [message] as it is.
  OnlineFailure? get failure => _failure;
  OnlineFailure? _failure;

  /// The technical reason behind [failure], when the backend gave one -- a
  /// sign-in error code such as `operation-not-allowed`.
  String? get failureDetail => _failureDetail;
  String? _failureDetail;

  void _fail(OnlineResult<Object?> result) {
    _failure = result.failure;
    _failureDetail = result.detail;
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
    final now = _now();
    for (final player in session.opponents) {
      final lastSeen = player.lastSeen;
      if (lastSeen == null || now.difference(lastSeen) > presenceTimeout) {
        return player;
      }
    }
    return null;
  }

  /// How long until the win can be claimed from the other player of a
  /// two-player game, who has gone quiet; zero once it can be, and null while
  /// there is nothing to claim.
  Duration? get claimWinIn {
    final session = _session;
    if (session == null ||
        !session.isParticipant ||
        session.game.playerCount != 2 ||
        session.game.status != OnlineGameStatus.active) {
      return null;
    }
    final lastSeen = session.opponent?.lastSeen;
    if (lastSeen == null) return null;
    final gone = _now().difference(lastSeen);
    if (gone <= presenceTimeout) return null;
    final left = claimAfter - gone;
    return left.isNegative ? Duration.zero : left;
  }

  bool get canClaimWin => claimWinIn == Duration.zero;

  /// Takes the win from the other player, who has gone. False when it was
  /// refused, for one because they have come back.
  Future<bool> claimWin() async {
    final session = _session;
    final seat = session?.localPlayerId;
    if (session == null || seat == null || !canClaimWin) return false;
    final result = await _service.endGame(
      session.game.gameId,
      winner: seat,
      reason: OnlineOutcomeReason.timeout,
    );
    if (!result.isSuccess) {
      _fail(result);
      if (!_disposed) notifyListeners();
      return false;
    }
    return true;
  }

  // --- Resigning and draws -------------------------------------------------

  /// Whether this device may resign or offer a draw: a two-player game under
  /// way that it plays in.
  bool get canResign => leavingResigns;

  /// The draw the other player is waiting on this device to answer.
  DrawOffer? get drawOfferToAnswer {
    final offer = _session?.game.openDrawOffer;
    if (offer == null || offer.by == localPlayerId) return null;
    return offer;
  }

  /// Whether this device has a draw offer out that is still standing.
  bool get drawOffered {
    final offer = _session?.game.openDrawOffer;
    return offer != null && offer.by == localPlayerId;
  }

  /// Whether a draw can be offered now: once per move, and not while
  /// answering one.
  bool get canOfferDraw {
    final game = _session?.game;
    if (game == null || !canResign) return false;
    final last = game.drawOffer;
    return last == null || last.atMove != game.moveCount;
  }

  /// Gives this game to the other player.
  Future<bool> resign() async {
    final session = _session;
    final seat = session?.localPlayerId;
    if (session == null || seat == null || !canResign) return false;
    return _report(
      await _service.endGame(
        session.game.gameId,
        winner: 3 - seat,
        reason: OnlineOutcomeReason.resign,
      ),
    );
  }

  Future<bool> offerDraw() async {
    final session = _session;
    final seat = session?.localPlayerId;
    if (session == null || seat == null || !canOfferDraw) return false;
    return _report(
      await _service.offerDraw(
        session.game.gameId,
        seat: seat,
        atMove: session.game.moveCount,
      ),
    );
  }

  /// Agrees the draw the other player offered, ending the game.
  Future<bool> acceptDraw() async {
    final session = _session;
    if (session == null || drawOfferToAnswer == null) return false;
    return _report(
      await _service.endGame(
        session.game.gameId,
        winner: null,
        reason: OnlineOutcomeReason.draw,
      ),
    );
  }

  Future<bool> declineDraw() async {
    final session = _session;
    if (session == null || drawOfferToAnswer == null) return false;
    return _report(await _service.declineDraw(session.game.gameId));
  }

  /// True for [result] succeeding; otherwise records why, for the screen.
  bool _report(OnlineResult<void> result) {
    if (result.isSuccess) return true;
    _fail(result);
    if (!_disposed) notifyListeners();
    return false;
  }

  /// Whether leaving now hands the game to the other player: a two-player
  /// game that is under way.
  bool get leavingResigns {
    final game = _session?.game;
    return game != null &&
        _session!.isParticipant &&
        game.playerCount == 2 &&
        game.status == OnlineGameStatus.active;
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

      // The rematch keeps the time the table was playing with.
      final created = await _service.createPrivateGame(
        playerCount: session.game.playerCount,
        turnLimit: session.game.turnLimit,
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

  // --- Chat ----------------------------------------------------------------

  final List<ChatMessage> _chat = [];
  final StreamController<ChatMessage> _chatArrivals =
      StreamController<ChatMessage>.broadcast();
  final Random _random = Random();
  int _unreadChat = 0;
  DateTime? _lastChatSent;

  /// False until the first list of messages has come in. That one is the
  /// conversation so far, not anything new, so it neither pops up nor
  /// counts as unread.
  bool _chatPrimed = false;

  /// This game's messages, oldest first.
  List<ChatMessage> get chat => List.unmodifiable(_chat);

  /// Messages from the others since the chat was last looked at.
  int get unreadChat => _unreadChat;

  /// Every message as it should pop up on screen: the others' when they
  /// arrive, and this device's own the moment it is sent.
  Stream<ChatMessage> get chatArrivals => _chatArrivals.stream;

  /// Whether a message can go out right now.
  bool get canChat {
    final session = _session;
    if (_disposed || session == null || !session.isParticipant) return false;
    final last = _lastChatSent;
    return last == null || _now().difference(last) >= chatCooldown;
  }

  /// Sends [item] to the table. It shows here at once and goes out in the
  /// background; false when it was not sent at all.
  Future<bool> sendChat(QuickChat item) => _send(item: item);

  /// Sends words the player typed, tidied to one line of at most
  /// [ChatMessage.maxText] characters; false when there was nothing to send
  /// or it was not sent.
  Future<bool> sendText(String raw) {
    final text = ChatMessage.tidy(raw);
    if (text.isEmpty) return Future.value(false);
    return _send(text: text);
  }

  Future<bool> _send({QuickChat? item, String? text}) async {
    final session = _session;
    final seat = session?.localPlayerId;
    if (session == null || seat == null || !canChat) return false;

    final sentAt = _now();
    _lastChatSent = sentAt;
    final message = ChatMessage(
      id:
          '$seat-${sentAt.microsecondsSinceEpoch}-'
          '${_random.nextInt(0x7fffffff).toRadixString(36)}',
      seat: seat,
      item: item,
      text: text,
      sentAt: sentAt,
    );
    _mergeChat([message]);
    _chatArrivals.add(message);
    notifyListeners();

    final sent = await _service.sendChat(session.game.gameId, message);
    if (!sent && !_disposed) {
      // Taking it back off the list says it did not go, without a toast
      // in the middle of the board for something this small.
      _chat.removeWhere((m) => m.id == message.id);
      notifyListeners();
    }
    return sent;
  }

  /// Whether the others' messages are kept quiet: still listed, but with no
  /// bubble, no sound and no unread count.
  bool get chatMuted => _chatMuted;
  bool _chatMuted = false;

  set chatMuted(bool value) {
    if (_chatMuted == value) return;
    _chatMuted = value;
    if (value) _unreadChat = 0;
    notifyListeners();
  }

  /// The chat has been read.
  void markChatRead() {
    if (_unreadChat == 0) return;
    _unreadChat = 0;
    notifyListeners();
  }

  void _onChatChanged(List<ChatMessage> messages) {
    if (_disposed) return;
    final known = {for (final m in _chat) m.id};
    final fresh = [
      for (final m in messages)
        if (!known.contains(m.id)) m,
    ];
    _mergeChat(messages);

    if (_chatPrimed && !_chatMuted) {
      final seat = _session?.localPlayerId;
      for (final message in fresh) {
        if (message.seat == seat) continue;
        _unreadChat++;
        _chatArrivals.add(message);
      }
    }
    _chatPrimed = true;
    notifyListeners();
  }

  /// Adds [messages] to the list, taking the server's copy of any already
  /// there, and keeps it in order and to its length.
  void _mergeChat(List<ChatMessage> messages) {
    final byId = {for (final m in _chat) m.id: m};
    for (final m in messages) {
      // A message the server has not dated yet keeps the time it was first
      // seen here, so it stays where it was in the list.
      byId[m.id] = m.sentAt != null ? m : m.dated(byId[m.id]?.sentAt ?? _now());
    }
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    final merged = byId.values.toList()
      ..sort((a, b) => (a.sentAt ?? epoch).compareTo(b.sentAt ?? epoch));
    final overflow = merged.length - OnlineGameService.chatHistory;
    _chat
      ..clear()
      ..addAll(overflow > 0 ? merged.skip(overflow) : merged);
  }

  void _resetChat() {
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _chat.clear();
    _unreadChat = 0;
    _chatPrimed = false;
  }

  /// The player whose turn it is, as the server names them.
  OnlinePlayer? get playerToMove {
    final game = _session?.game;
    return game?.players[game.currentPlayerId];
  }

  /// The time each player has for a turn in this game, as its host set it.
  TurnLimit get turnLimit => _session?.game.turnLimit ?? TurnLimit.off;

  /// Creates a game for [playerCount] people, with [turnLimit] for every
  /// turn, and starts watching it.
  Future<bool> createGame({
    int playerCount = 2,
    TurnLimit turnLimit = TurnLimit.off,
  }) async {
    _setConnection(OnlineConnectionState.connecting);
    final result = await _service.createPrivateGame(
      playerCount: playerCount,
      turnLimit: turnLimit,
    );
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
    _failureDetail = null;
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

    // A rematch is a new game with a conversation of its own.
    _resetChat();
    _chatSubscription = _service
        .watchChat(gameId)
        .listen(
          _onChatChanged,
          // Chat going quiet must not end the game; the game's own stream
          // reports a lost connection.
          onError: (Object error) =>
              debugPrint('OnlineGameController: chat error: $error'),
        );

    // Report in immediately, then keep reporting.
    unawaited(_service.heartbeat(gameId, seat));
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_service.heartbeat(gameId, seat));
    });

    // The opponent going quiet is not an event, it is the absence of one, so
    // it has to be noticed on a timer rather than from the stream.
    _presenceTicker?.cancel();
    // Every second, so the time left to claim a win counts down smoothly.
    _presenceTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshConnection();
      if (claimWinIn != null && !_disposed) notifyListeners();
    });
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

    // A draw offered, or an answer to one: neither moves a piece, so nothing
    // below would tell the screen about it.
    if (game.drawOffer != previous?.game.drawOffer) {
      final offer = game.drawOffer;
      final seat = _session?.localPlayerId;
      if (offer != null && seat != null) {
        if (offer.by != seat && game.openDrawOffer != null) {
          onDrawOffered?.call();
        } else if (offer.by == seat &&
            offer.declined &&
            !(previous?.game.drawOffer?.declined ?? false)) {
          onDrawDeclined?.call();
        }
      }
      notifyListeners();
    }

    if (game.isOver && (previous == null || !previous.game.isOver)) {
      final didWin = _session?.didWin;
      _setConnection(OnlineConnectionState.ended);
      final drawn = game.outcomeReason == OnlineOutcomeReason.draw;
      if (didWin != null || drawn) onGameOver?.call(didWin);
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
  Future<bool> submitMove(GameMove move, {bool timedOut = false}) async {
    final session = _session;
    if (session == null || _submitting) return false;

    final confirmed = session.game;
    if (!GameService.isValidMove(confirmed.board, move, timedOut: timedOut)) {
      return false;
    }
    _submitting = true;

    try {
      _applyOptimistically(move, timedOut: timedOut);

      final result = await _service.submitMove(
        session,
        move,
        timedOut: timedOut,
      );

      if (!result.isSuccess) {
        _rollback(_serverGame ?? confirmed);
        _fail(result);
        return false;
      }

      _message = null;
      _failure = null;
      _failureDetail = null;
      return true;
    } finally {
      _submitting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Hands the turn on when this device's time for it has run out. Online,
  /// a turn that runs out passes to the next player rather than having a
  /// move played for this one.
  Future<bool> passTurn() async {
    final seat = localPlayerId;
    if (seat == null || !isLocalTurn) return false;
    return submitMove(GameMove.pass(seat), timedOut: true);
  }

  /// Shows [move] on this device before the server has confirmed it.
  void _applyOptimistically(GameMove move, {bool timedOut = false}) {
    final session = _session;
    if (session == null) return;

    // The real rules, not the engine's shortcut: that drops the move history
    // to keep its search cheap, which emptied the move list while a move was
    // in flight and made every earlier move sound again once it landed.
    final board = GameService.executeMove(
      session.game.board,
      move,
      timedOut: timedOut,
    );
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
        turnLimit: game.turnLimit,
        drawOffer: game.drawOffer,
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
      final resigns = abandon && leavingResigns;
      if (seat != null) await _service.markAway(gameId, seat);
      if (resigns && seat != null) {
        // Leaving a two-player game gives it to the one who stays.
        await _service.endGame(
          gameId,
          winner: 3 - seat,
          reason: OnlineOutcomeReason.resign,
        );
      } else if (abandon && !session.game.isOver) {
        await _service.abandon(gameId);
      }
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
    _failureDetail = null;
    notifyListeners();
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _presenceTicker?.cancel();
    _presenceTicker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    _chatArrivals.close();
    super.dispose();
  }
}
