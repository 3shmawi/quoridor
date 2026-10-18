import 'dart:async';

import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/online_chat.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/online/online_game_service.dart';
import 'package:quoridor/flame/services/turn_clock.dart';

/// Stands in for Firestore: games are whatever the test seeds, and the
/// first rematch link offered on a game is the one that stands.
class FakeOnlineGameService implements OnlineGameService {
  final sessions = <String, OnlineSession>{};
  final byCode = <String, OnlineSession>{};
  final links = <String, RematchLink>{};
  final abandoned = <String>[];
  final created = <OnlineSession>[];

  /// The turn limit each created game was asked for.
  final createdTurnLimits = <TurnLimit>[];
  OnlineSession? nextCreated;
  final _streams = <String, StreamController<OnlineGame>>{};

  void push(OnlineGame game) => _streams[game.gameId]?.add(game);

  @override
  Future<OnlineResult<OnlineSession>> resume(String gameId) async =>
      OnlineResult.success(sessions[gameId]);

  @override
  Future<OnlineResult<OnlineSession>> createPrivateGame({
    int playerCount = 2,
    TurnLimit turnLimit = TurnLimit.off,
  }) async {
    createdTurnLimits.add(turnLimit);
    created.add(nextCreated!);
    return OnlineResult.success(nextCreated);
  }

  /// When set, joining fails as it does when sign-in did: unavailable, with
  /// this as the reason.
  String? signInError;

  @override
  Future<OnlineResult<OnlineSession>> joinByCode(String rawCode) async {
    final error = signInError;
    if (error != null) {
      return OnlineResult.failed(OnlineFailure.unavailable, error);
    }
    final session = byCode[rawCode];
    return session == null
        ? const OnlineResult.failed(OnlineFailure.gameNotFound)
        : OnlineResult.success(session);
  }

  @override
  Future<OnlineResult<RematchLink>> offerRematch(
    String gameId,
    RematchLink link,
  ) async => OnlineResult.success(links.putIfAbsent(gameId, () => link));

  @override
  Future<void> abandon(String gameId) async => abandoned.add(gameId);

  /// Games ended other than on the board, as (game, winner, reason).
  final endings = <(String, int?, OnlineOutcomeReason)>[];

  /// Draws offered, as (game, seat, move count), and games whose offer was
  /// declined.
  final drawOffers = <(String, int, int)>[];
  final drawsDeclined = <String>[];

  @override
  Future<OnlineResult<void>> offerDraw(
    String gameId, {
    required int seat,
    required int atMove,
  }) async {
    drawOffers.add((gameId, seat, atMove));
    return const OnlineResult.success(null);
  }

  @override
  Future<OnlineResult<void>> declineDraw(String gameId) async {
    drawsDeclined.add(gameId);
    return const OnlineResult.success(null);
  }

  bool endingFails = false;

  @override
  Future<OnlineResult<void>> endGame(
    String gameId, {
    required int? winner,
    required OnlineOutcomeReason reason,
  }) async {
    if (endingFails) {
      return const OnlineResult.failed(OnlineFailure.backendError);
    }
    endings.add((gameId, winner, reason));
    return const OnlineResult.success(null);
  }

  @override
  Stream<OnlineGame> watchGame(String gameId) =>
      (_streams[gameId] ??= StreamController<OnlineGame>.broadcast()).stream;

  /// Moves submitted, in order. Each waits on [submitResults] until the test
  /// completes it, so a test can act while a move is still on its way.
  final submitted = <GameMove>[];
  final submitResults = <Completer<OnlineResult<OnlineGame>>>[];

  @override
  Future<OnlineResult<OnlineGame>> submitMove(
    OnlineSession session,
    GameMove move,
  ) {
    submitted.add(move);
    final result = Completer<OnlineResult<OnlineGame>>();
    submitResults.add(result);
    return result.future;
  }

  /// Messages sent, in order, and whether sending them works.
  final chatSent = <ChatMessage>[];
  bool chatFails = false;
  final _chatStreams = <String, StreamController<List<ChatMessage>>>{};

  /// Delivers [messages] as the game's latest chat, as Firestore would.
  void pushChat(String gameId, List<ChatMessage> messages) =>
      _chatStreams[gameId]?.add(messages);

  @override
  Future<bool> sendChat(String gameId, ChatMessage message) async {
    if (chatFails) return false;
    chatSent.add(message);
    return true;
  }

  @override
  Stream<List<ChatMessage>> watchChat(String gameId) =>
      (_chatStreams[gameId] ??= StreamController<List<ChatMessage>>.broadcast())
          .stream;

  @override
  Future<void> heartbeat(String gameId, int seat) async {}

  @override
  Future<void> markAway(String gameId, int seat) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
