import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/app_strings.dart';
import 'package:quoridor/flame/services/online/online_game_codec.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/online/online_game_service.dart';

import 'fakes/fake_online_game_service.dart';

const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

OnlineGame onlineGame(
  String id, {
  OnlineGameStatus status = OnlineGameStatus.finished,
  Map<int, OnlinePlayer> players = const {1: alice, 2: bob},
  String roomCode = 'OLD111',
  RematchLink? rematch,
  int moveCount = 30,
}) => OnlineGame(
  gameId: id,
  roomCode: roomCode,
  status: status,
  players: players,
  currentPlayerId: 1,
  moveCount: moveCount,
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
  winnerPlayerId: status == OnlineGameStatus.finished ? 1 : null,
  rematch: rematch,
);

void main() {
  late FakeOnlineGameService service;
  late OnlineGameController controller;
  final boards = <GameState>[];

  setUp(() {
    service = FakeOnlineGameService();
    controller = OnlineGameController(service: service);
    boards.clear();
    controller.onRemoteUpdate = boards.add;
  });

  tearDown(() => controller.dispose());

  Future<void> sitAtFinishedGame({required int seat, RematchLink? link}) async {
    service.sessions['old'] = OnlineSession(
      game: onlineGame('old', rematch: link),
      localPlayerId: seat,
    );
    expect(await controller.resumeGame('old'), isTrue);
    boards.clear();
  }

  test('asking first creates a new game, links it, and moves to it', () async {
    await sitAtFinishedGame(seat: 2);
    service.nextCreated = OnlineSession(
      game: onlineGame(
        'new',
        status: OnlineGameStatus.waiting,
        players: const {1: bob},
        roomCode: 'NEW222',
        moveCount: 0,
      ),
      localPlayerId: 1,
    );

    expect(controller.canRematch, isTrue);
    expect(await controller.requestRematch(), isTrue);

    expect(service.links['old']?.gameId, 'new');
    expect(service.links['old']?.by, 2);
    expect(controller.game?.gameId, 'new');
    expect(controller.localPlayerId, 1);
    expect(controller.connection, OnlineConnectionState.waitingForOpponent);
    // The board on screen follows, though no move announced it.
    expect(boards.single.gameId, 'new');
  });

  test('an offer from somebody else is joined, not duplicated', () async {
    const offer = RematchLink(gameId: 'theirs', roomCode: 'THEIRS', by: 1);
    await sitAtFinishedGame(seat: 2, link: offer);
    service.byCode['THEIRS'] = OnlineSession(
      game: onlineGame(
        'theirs',
        status: OnlineGameStatus.active,
        roomCode: 'THEIRS',
        players: {
          1: OnlinePlayer(
            uid: alice.uid,
            displayName: alice.displayName,
            lastSeen: DateTime.now(),
          ),
          2: OnlinePlayer(
            uid: bob.uid,
            displayName: bob.displayName,
            lastSeen: DateTime.now(),
          ),
        },
        moveCount: 0,
      ),
      localPlayerId: 2,
    );

    expect(controller.rematchOffer, offer);
    expect(await controller.requestRematch(), isTrue);

    expect(service.created, isEmpty);
    expect(controller.game?.gameId, 'theirs');
    expect(controller.connection, OnlineConnectionState.live);
  });

  test('asking at the same moment joins whoever got there first', () async {
    await sitAtFinishedGame(seat: 2);
    // Alice's link lands between Bob creating his game and linking it.
    service.links['old'] = const RematchLink(
      gameId: 'alices',
      roomCode: 'ALICES',
      by: 1,
    );
    service.nextCreated = OnlineSession(
      game: onlineGame(
        'bobs',
        status: OnlineGameStatus.waiting,
        players: const {1: bob},
        roomCode: 'BOBS22',
        moveCount: 0,
      ),
      localPlayerId: 1,
    );
    service.byCode['ALICES'] = OnlineSession(
      game: onlineGame(
        'alices',
        status: OnlineGameStatus.active,
        roomCode: 'ALICES',
        moveCount: 0,
      ),
      localPlayerId: 2,
    );

    expect(await controller.requestRematch(), isTrue);

    expect(service.abandoned, ['bobs']);
    expect(controller.game?.gameId, 'alices');
  });

  test('an offer arriving on the finished game is shown', () async {
    await sitAtFinishedGame(seat: 2);
    var notified = 0;
    controller.addListener(() => notified++);

    service.push(
      onlineGame(
        'old',
        rematch: const RematchLink(gameId: 'n', roomCode: 'NNNNNN', by: 1),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(notified, greaterThan(0));
    expect(controller.rematchOffer?.roomCode, 'NNNNNN');
  });

  test('your own offer is not shown back to you as one to join', () async {
    await sitAtFinishedGame(
      seat: 2,
      link: const RematchLink(gameId: 'n', roomCode: 'NNNNNN', by: 2),
    );
    expect(controller.rematchOffer, isNull);
  });

  test('there is no rematch while the game is still being played', () async {
    service.sessions['live'] = OnlineSession(
      game: onlineGame('live', status: OnlineGameStatus.active),
      localPlayerId: 1,
    );
    await controller.resumeGame('live');
    expect(controller.canRematch, isFalse);
    expect(await controller.requestRematch(), isFalse);
  });

  test('a failure reaches the player in their own language', () async {
    const offer = RematchLink(gameId: 'gone', roomCode: 'GONE11', by: 1);
    await sitAtFinishedGame(seat: 2, link: offer);

    // The offered game has disappeared by the time this device joins.
    expect(await controller.requestRematch(), isFalse);
    expect(controller.failure, OnlineFailure.gameNotFound);

    const arabic = AppStrings(Locale('ar'));
    expect(arabic.onlineNotice(controller), arabic.gameNotFound);
    expect(arabic.onlineNotice(controller), isNot(controller.message));
  });

  test('a rematch link survives the trip through the stored document', () {
    const link = RematchLink(gameId: 'g2', roomCode: 'ABCDEF', by: 3);
    final stored = OnlineGameCodec.encodeRematch(link: link, timestamp: 0);
    expect(OnlineGameCodec.decodeRematch(stored['rematch']), link);
    expect(OnlineGameCodec.decodeRematch(null), isNull);
    expect(OnlineGameCodec.decodeRematch({'gameId': 'g2'}), isNull);
  });

  test('when online play is unavailable, the reason is still shown', () async {
    // The reason is what tells a broken Firebase setup apart from a dropped
    // connection; translating the message once lost it.
    service.signInError = 'operation-not-allowed';
    expect(await controller.joinGame('ABCDEF'), isFalse);
    expect(controller.failure, OnlineFailure.unavailable);

    for (final strings in const [
      AppStrings(Locale('en')),
      AppStrings(Locale('ar')),
    ]) {
      final notice = strings.onlineNotice(controller)!;
      expect(notice, startsWith(strings.onlineUnavailable));
      expect(notice, contains('operation-not-allowed'));
    }
  });
}
