import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/online_chat.dart';
import '../../models/online_session.dart';
import '../firebase_service.dart';
import '../game_service.dart';
import '../turn_clock.dart';
import '../identity_service.dart';
import 'online_game_codec.dart';
import 'room_code.dart';

/// Why an online action did not go through.
enum OnlineFailure {
  /// Firebase is not available, or the device has no identity yet.
  unavailable,

  /// No game carries the code that was entered.
  gameNotFound,

  /// Every seat in the game is already taken.
  gameFull,

  /// The player tried to join a game they are already in.
  alreadyJoined,

  /// It is not this player's turn, or the game is not active.
  notYourTurn,

  /// Another move landed first. The caller should resync and retry.
  staleMove,

  /// The move broke the rules of Quoridor.
  illegalMove,

  /// The backend rejected the write or could not be reached.
  backendError,
}

/// The outcome of an online action.
@immutable
class OnlineResult<T> {
  final T? value;
  final OnlineFailure? failure;
  final String? detail;

  const OnlineResult.success(this.value) : failure = null, detail = null;

  const OnlineResult.failed(this.failure, [this.detail]) : value = null;

  bool get isSuccess => failure == null;

  /// A short explanation suitable for showing to the player.
  String get message {
    switch (failure) {
      case null:
        return 'Done';
      case OnlineFailure.unavailable:
        return detail == null
            ? 'Online play is unavailable right now'
            : 'Online play is unavailable right now ($detail)';
      case OnlineFailure.gameNotFound:
        return 'No game found with that code';
      case OnlineFailure.gameFull:
        return 'That game is already full';
      case OnlineFailure.alreadyJoined:
        return 'You are already in that game';
      case OnlineFailure.notYourTurn:
        return 'It is not your turn';
      case OnlineFailure.staleMove:
        return 'Your opponent moved first — reloading the board';
      case OnlineFailure.illegalMove:
        return detail ?? 'That move is not legal';
      case OnlineFailure.backendError:
        return 'Could not reach the game server';
    }
  }
}

/// Creates, joins, watches and plays online games.
///
/// Rule enforcement stays where it already lives: every move is checked with
/// [GameService] before it is submitted, and again by the receiving client
/// when it arrives. Clients therefore never have to trust each other's board,
/// only their own copy of the rules.
///
/// Moves — not boards — are what a client submits. The move list is the source
/// of truth and the `board` field is a cache of replaying it, which is what
/// makes reconnect possible and what lets a server-side validator take over
/// later without changing the stored shape of a game.
class OnlineGameService {
  OnlineGameService._();

  static final OnlineGameService instance = OnlineGameService._();

  static const String gamesCollection = 'games';
  static const String movesCollection = 'moves';
  static const String chatCollection = 'chat';

  /// How much of a game's chat is kept on screen.
  static const int chatHistory = 50;

  /// How many codes to try before giving up on finding an unused one.
  static const int _codeAttempts = 5;

  CollectionReference<Map<String, dynamic>>? get _games =>
      FirebaseService.isReady
      ? FirebaseFirestore.instance.collection(gamesCollection)
      : null;

  /// Creates a game for [playerCount] people with a room code and seats the
  /// creator as player 1. [turnLimit] is the time every player gets for a
  /// turn.
  Future<OnlineResult<OnlineSession>> createPrivateGame({
    int playerCount = 2,
    TurnLimit turnLimit = TurnLimit.off,
  }) async {
    assert(playerCount >= 2 && playerCount <= 4);
    // Sign in first: it waits for Firebase to finish starting, and reading
    // the collection before that finds nothing.
    final identity = await IdentityService.instance.ensureSignedIn();
    final games = _games;
    if (games == null || identity == null) {
      return OnlineResult.failed(
        OnlineFailure.unavailable,
        IdentityService.instance.lastError,
      );
    }

    final creator = OnlinePlayer(
      uid: identity.uid,
      displayName: identity.displayName,
      connected: true,
    );

    try {
      final code = await _reserveRoomCode(games);
      if (code == null) {
        return const OnlineResult.failed(
          OnlineFailure.backendError,
          'could not allocate a room code',
        );
      }

      // The other seats are filled in on join, so the board starts with
      // every seat human and nobody's name but the creator's.
      final board = GameStateFactory.createNewGame(
        player1Name: identity.displayName,
        player2Name: 'Waiting…',
        player2IsAI: false,
        playerCount: playerCount,
      );

      final doc = games.doc();
      await doc.set(
        OnlineGameCodec.encodeNewGame(
          roomCode: code,
          creator: creator,
          board: board,
          timestamp: FieldValue.serverTimestamp(),
          turnLimit: turnLimit,
        ),
      );

      final snapshot = await doc.get();
      final game = OnlineGameCodec.decodeGame(doc.id, snapshot.data()!);
      return OnlineResult.success(OnlineSession.forUid(game, identity.uid));
    } catch (error) {
      debugPrint('OnlineGameService: create failed: $error');
      return OnlineResult.failed(OnlineFailure.backendError, '$error');
    }
  }

  /// Finds an unused room code, or null if every attempt collided.
  Future<String?> _reserveRoomCode(
    CollectionReference<Map<String, dynamic>> games,
  ) async {
    for (var attempt = 0; attempt < _codeAttempts; attempt++) {
      final code = RoomCode.generate();
      final existing = await games
          .where('roomCode', isEqualTo: code)
          .where('status', isEqualTo: OnlineGameStatus.waiting.name)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) return code;
    }
    return null;
  }

  /// Takes the empty seat in the game carrying [rawCode].
  ///
  /// The lowest empty seat is claimed in a transaction, so two people racing
  /// on the same code cannot both take it.
  Future<OnlineResult<OnlineSession>> joinByCode(String rawCode) async {
    // Sign in first: it waits for Firebase to finish starting, and reading
    // the collection before that finds nothing.
    final identity = await IdentityService.instance.ensureSignedIn();
    final games = _games;
    if (games == null || identity == null) {
      return OnlineResult.failed(
        OnlineFailure.unavailable,
        IdentityService.instance.lastError,
      );
    }

    final code = RoomCode.tryParse(rawCode);
    if (code == null) {
      return const OnlineResult.failed(OnlineFailure.gameNotFound);
    }

    try {
      final matches = await games
          .where('roomCode', isEqualTo: code)
          .where('status', isEqualTo: OnlineGameStatus.waiting.name)
          .limit(1)
          .get();

      if (matches.docs.isEmpty) {
        return const OnlineResult.failed(OnlineFailure.gameNotFound);
      }

      final doc = matches.docs.first.reference;
      OnlineFailure? failure;

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(doc);
        final data = snapshot.data();
        if (data == null) {
          failure = OnlineFailure.gameNotFound;
          return;
        }

        final game = OnlineGameCodec.decodeGame(doc.id, data);

        if (game.playerIdOf(identity.uid) != null) {
          failure = OnlineFailure.alreadyJoined;
          return;
        }
        final seat = game.firstEmptySeat;
        if (seat == null) {
          failure = OnlineFailure.gameFull;
          return;
        }

        final joiner = OnlinePlayer(
          uid: identity.uid,
          displayName: identity.displayName,
          connected: true,
        );

        // Name the seat now that its player is known, so each client
        // renders the real name.
        final board = _withPlayerName(game.board, seat, joiner.displayName);
        final fillsGame = game.players.length + 1 >= game.playerCount;

        transaction.update(doc, {
          ...OnlineGameCodec.encodeJoin(
            seat: seat,
            joiner: joiner,
            fillsGame: fillsGame,
            timestamp: FieldValue.serverTimestamp(),
          ),
          'board': board.toJson(),
        });
      });

      if (failure != null) return OnlineResult.failed(failure);

      final snapshot = await doc.get();
      final game = OnlineGameCodec.decodeGame(doc.id, snapshot.data()!);
      return OnlineResult.success(OnlineSession.forUid(game, identity.uid));
    } catch (error) {
      debugPrint('OnlineGameService: join failed: $error');
      return OnlineResult.failed(OnlineFailure.backendError, '$error');
    }
  }

  /// Streams a game as it changes.
  ///
  /// Documents that cannot be decoded are skipped rather than closing the
  /// stream, so one bad write does not end the session.
  Stream<OnlineGame> watchGame(String gameId) {
    final games = _games;
    if (games == null) return const Stream<OnlineGame>.empty();

    return games
        .doc(gameId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) return null;
          try {
            return OnlineGameCodec.decodeGame(snapshot.id, data);
          } catch (error) {
            debugPrint('OnlineGameService: skipping bad snapshot: $error');
            return null;
          }
        })
        .where((game) => game != null)
        .cast<OnlineGame>();
  }

  /// Submits [move] for [session].
  ///
  /// The move is validated locally first, then written together with the new
  /// board in a transaction that asserts the turn and the move count are still
  /// what this client saw. That assertion is the whole concurrency story: two
  /// clients cannot both write move N.
  Future<OnlineResult<OnlineGame>> submitMove(
    OnlineSession session,
    GameMove move,
  ) async {
    final games = _games;
    final identity = IdentityService.instance.current;
    if (games == null || identity == null) {
      return OnlineResult.failed(
        OnlineFailure.unavailable,
        IdentityService.instance.lastError,
      );
    }

    if (!session.isLocalTurn) {
      return const OnlineResult.failed(OnlineFailure.notYourTurn);
    }

    final localPlayerId = session.localPlayerId!;
    if (move.playerId != localPlayerId) {
      return const OnlineResult.failed(
        OnlineFailure.illegalMove,
        'move submitted for the wrong player',
      );
    }

    final doc = games.doc(session.game.gameId);
    OnlineFailure? failure;
    String? detail;

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(doc);
        final data = snapshot.data();
        if (data == null) {
          failure = OnlineFailure.gameNotFound;
          return;
        }

        final current = OnlineGameCodec.decodeGame(doc.id, data);

        if (current.moveCount != session.game.moveCount) {
          failure = OnlineFailure.staleMove;
          return;
        }
        if (current.status != OnlineGameStatus.active ||
            current.currentPlayerId != localPlayerId) {
          failure = OnlineFailure.notYourTurn;
          return;
        }

        // The rules are the same ones local play uses; nothing about being
        // online relaxes them.
        if (!GameService.isValidMove(current.board, move)) {
          failure = OnlineFailure.illegalMove;
          detail = move.type == MoveType.wallPlace
              ? GameService.validateWallPlacement(
                  current.board,
                  current.board.currentPlayer,
                  move.wall!,
                ).message
              : 'That move is not legal';
          return;
        }

        final nextBoard = GameService.executeMove(current.board, move);
        final nextCount = current.moveCount + 1;

        transaction.set(
          doc
              .collection(movesCollection)
              .doc(OnlineGameCodec.moveDocId(current.moveCount)),
          OnlineGameCodec.encodeMove(
            move: move,
            submittedBy: identity.uid,
            submittedAt: FieldValue.serverTimestamp(),
          ),
        );

        transaction.update(
          doc,
          OnlineGameCodec.encodeMoveResult(
            board: nextBoard,
            moveCount: nextCount,
            timestamp: FieldValue.serverTimestamp(),
          ),
        );
      });

      if (failure != null) return OnlineResult.failed(failure, detail);

      final snapshot = await doc.get();
      return OnlineResult.success(
        OnlineGameCodec.decodeGame(doc.id, snapshot.data()!),
      );
    } catch (error) {
      debugPrint('OnlineGameService: submitMove failed: $error');
      return OnlineResult.failed(OnlineFailure.backendError, '$error');
    }
  }

  /// Sends [message] to everyone in [gameId].
  ///
  /// The id is the sender's own, so the copy it shows straight away and the
  /// one the server sends back are known to be the same message.
  Future<bool> sendChat(String gameId, ChatMessage message) async {
    final games = _games;
    final identity = IdentityService.instance.current;
    if (games == null || identity == null) return false;
    try {
      await games
          .doc(gameId)
          .collection(chatCollection)
          .doc(message.id)
          .set(
            OnlineGameCodec.encodeChat(
              message: message,
              uid: identity.uid,
              sentAt: FieldValue.serverTimestamp(),
            ),
          );
      return true;
    } catch (error) {
      debugPrint('OnlineGameService: sendChat failed: $error');
      return false;
    }
  }

  /// The latest [chatHistory] messages in [gameId], oldest first, every time
  /// one arrives.
  Stream<List<ChatMessage>> watchChat(String gameId) {
    final games = _games;
    if (games == null) return const Stream<List<ChatMessage>>.empty();

    return games
        .doc(gameId)
        .collection(chatCollection)
        .orderBy('sentAt', descending: true)
        .limit(chatHistory)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs.reversed)
              // A message still on its way has no server time yet; the
              // controller dates it itself.
              ?OnlineGameCodec.decodeChat(doc.id, doc.data()),
          ],
        );
  }

  /// Offers [link] as the rematch of the finished game [gameId].
  ///
  /// Only one rematch is ever linked from a game, so when two players ask at
  /// once the first link stands. The result is the link that stands -- this
  /// one, or the one that got there first, which the caller should join
  /// instead of its own.
  Future<OnlineResult<RematchLink>> offerRematch(
    String gameId,
    RematchLink link,
  ) async {
    final games = _games;
    if (games == null) {
      return const OnlineResult.failed(OnlineFailure.unavailable);
    }

    final doc = games.doc(gameId);
    try {
      RematchLink? standing;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(doc);
        final existing = OnlineGameCodec.decodeRematch(
          snapshot.data()?['rematch'],
        );
        if (existing != null) {
          standing = existing;
          return;
        }
        transaction.update(
          doc,
          OnlineGameCodec.encodeRematch(
            link: link,
            timestamp: FieldValue.serverTimestamp(),
          ),
        );
        standing = link;
      });
      return OnlineResult.success(standing);
    } catch (error) {
      debugPrint('OnlineGameService: offerRematch failed: $error');
      return OnlineResult.failed(OnlineFailure.backendError, '$error');
    }
  }

  /// Refreshes this player's presence on [gameId].
  ///
  /// Written as dotted paths so only this player's own seat is touched; the
  /// Security Rules refuse a presence write that reaches anything else.
  Future<void> heartbeat(String gameId, int seat) async {
    final games = _games;
    if (games == null) return;
    try {
      await games.doc(gameId).update({
        'players.$seat.connected': true,
        'players.$seat.lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      // A missed heartbeat is not worth surfacing: the next one covers it,
      // and the opponent simply sees this player as away until then.
      debugPrint('OnlineGameService: heartbeat failed: $error');
    }
  }

  /// Marks this player as away, for a clean exit rather than a timeout.
  Future<void> markAway(String gameId, int seat) async {
    final games = _games;
    if (games == null) return;
    try {
      await games.doc(gameId).update({
        'players.$seat.connected': false,
        'players.$seat.lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('OnlineGameService: markAway failed: $error');
    }
  }

  /// Reads a game once, for resuming a session.
  Future<OnlineResult<OnlineSession>> resume(String gameId) async {
    // Sign in first: it waits for Firebase to finish starting, and reading
    // the collection before that finds nothing.
    final identity = await IdentityService.instance.ensureSignedIn();
    final games = _games;
    if (games == null || identity == null) {
      return OnlineResult.failed(
        OnlineFailure.unavailable,
        IdentityService.instance.lastError,
      );
    }

    try {
      final snapshot = await games.doc(gameId).get();
      final data = snapshot.data();
      if (data == null) {
        return const OnlineResult.failed(OnlineFailure.gameNotFound);
      }

      final game = OnlineGameCodec.decodeGame(snapshot.id, data);
      final session = OnlineSession.forUid(game, identity.uid);
      if (!session.isParticipant) {
        return const OnlineResult.failed(OnlineFailure.gameNotFound);
      }
      return OnlineResult.success(session);
    } catch (error) {
      debugPrint('OnlineGameService: resume failed: $error');
      return OnlineResult.failed(OnlineFailure.backendError, '$error');
    }
  }

  /// Games this player is still in, newest first. Used to offer a rejoin.
  Future<List<OnlineGame>> myActiveGames({int limit = 5}) async {
    final games = _games;
    final identity = IdentityService.instance.current;
    if (games == null || identity == null) return const [];

    final results = <String, OnlineGame>{};

    // Firestore has no OR across fields, so each seat is a separate query.
    for (final seat in [1, 2, 3, 4]) {
      try {
        final snapshot = await games
            .where(
              FieldPath(['players', '$seat', 'uid']),
              isEqualTo: identity.uid,
            )
            .where(
              'status',
              whereIn: [
                OnlineGameStatus.waiting.name,
                OnlineGameStatus.active.name,
              ],
            )
            .limit(limit)
            .get();

        for (final doc in snapshot.docs) {
          try {
            results[doc.id] = OnlineGameCodec.decodeGame(doc.id, doc.data());
          } catch (_) {
            // Skip a game we cannot read rather than losing the whole list.
          }
        }
      } catch (error) {
        debugPrint('OnlineGameService: myActiveGames seat $seat: $error');
      }
    }

    final list = results.values.toList()
      ..sort((a, b) {
        final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    return list.take(limit).toList();
  }

  /// Replays the stored move list, which is the authoritative record.
  ///
  /// Used to verify the cached board and, later, to rebuild a game on
  /// reconnect.
  Future<List<GameMove>> loadMoves(String gameId) async {
    final games = _games;
    if (games == null) return const [];

    try {
      final snapshot = await games
          .doc(gameId)
          .collection(movesCollection)
          .orderBy(FieldPath.documentId)
          .get();

      return snapshot.docs
          .map((doc) => OnlineGameCodec.decodeMove(doc.data()))
          .toList();
    } catch (error) {
      debugPrint('OnlineGameService: loadMoves failed: $error');
      return const [];
    }
  }

  /// Marks a game as abandoned. Best effort: a player who simply vanishes is
  /// handled by presence in a later phase.
  Future<void> abandon(String gameId) async {
    final games = _games;
    if (games == null) return;
    try {
      await games.doc(gameId).update({
        'status': OnlineGameStatus.abandoned.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('OnlineGameService: abandon failed: $error');
    }
  }

  static GameState _withPlayerName(GameState board, int seat, String name) =>
      board.copyWith(
        players: [
          for (final player in board.players)
            player.id == seat
                ? player.copyWith(name: name, isAI: false)
                : player,
        ],
      );
}
