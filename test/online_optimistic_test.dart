import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/game_service.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/online/online_game_service.dart';

import 'fakes/fake_online_game_service.dart';

const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

/// The game as the server holds it after [moves] have been played.
OnlineGame served(
  List<GameMove> moves, {
  Map<int, OnlinePlayer> players = const {1: alice, 2: bob},
}) {
  var board = GameStateFactory.createNewGame(gameId: 'g', player2IsAI: false);
  for (final move in moves) {
    board = GameService.executeMove(board, move);
  }
  return OnlineGame(
    gameId: 'g',
    roomCode: 'ABCDEF',
    status: OnlineGameStatus.active,
    players: players,
    currentPlayerId: board.currentPlayerId,
    moveCount: moves.length,
    board: board,
  );
}

const myStep = GameMove.pawnMove(Position(7, 4), 1);
const myWall = GameMove.wallPlace(
  Wall(Position(4, 3), WallOrientation.horizontal),
  1,
);
const theirStep = GameMove.pawnMove(Position(1, 4), 2);

void main() {
  late FakeOnlineGameService service;
  late OnlineGameController controller;
  final shown = <GameState>[];

  setUp(() async {
    service = FakeOnlineGameService();
    controller = OnlineGameController(service: service);
    shown.clear();
    controller.onRemoteUpdate = shown.add;

    service.sessions['g'] = OnlineSession(game: served([]), localPlayerId: 1);
    await controller.resumeGame('g');
    shown.clear();
  });

  tearDown(() => controller.dispose());

  /// Lets the stream deliver what was pushed.
  Future<void> deliver() => Future<void>.delayed(Duration.zero);

  for (final move in [myStep, myWall]) {
    test(
      'a ${move.type.name} stays on screen while it is on its way',
      () async {
        final submitting = controller.submitMove(move);
        expect(shown.single.moveHistory, [move]);

        // A heartbeat lands before the move does: same document, old board.
        service.push(served([]));
        await deliver();

        // The server confirms.
        service.push(served([move]));
        await deliver();
        service.submitResults.single.complete(
          OnlineResult.success(served([move])),
        );
        expect(await submitting, isTrue);

        // The move never left the board in between.
        for (final board in shown) {
          expect(board.moveHistory, [move]);
        }
        expect(controller.game?.moveCount, 1);
      },
    );
  }

  test('presence from the server still comes through meanwhile', () async {
    final submitting = controller.submitMove(myStep);

    final seen = DateTime.now();
    service.push(
      served(
        [],
        players: {
          1: alice,
          2: OnlinePlayer(uid: bob.uid, displayName: 'Bob', lastSeen: seen),
        },
      ),
    );
    await deliver();

    expect(controller.game?.players[2]?.lastSeen, seen);
    expect(controller.game?.moveCount, 1);

    service.submitResults.single.complete(
      OnlineResult.success(served([myStep])),
    );
    await submitting;
  });

  test('a refused move gives way to the move that beat it', () async {
    // Whatever the server moved on to while Alice's move was in flight --
    // here a move of Bob's -- is what a refusal must fall back to, not the
    // board from before either move.
    final submitting = controller.submitMove(myStep);

    final bobFirst = OnlineGame(
      gameId: 'g',
      roomCode: 'ABCDEF',
      status: OnlineGameStatus.active,
      players: const {1: alice, 2: bob},
      currentPlayerId: 1,
      moveCount: 1,
      board: GameService.executeMove(
        GameStateFactory.createNewGame(gameId: 'g', player2IsAI: false)
          ..currentPlayerId = 2,
        theirStep,
      ),
    );
    service.push(bobFirst);
    await deliver();

    service.submitResults.single.complete(
      const OnlineResult.failed(OnlineFailure.staleMove),
    );
    expect(await submitting, isFalse);

    // The board shows Bob's move, not the board from before either move.
    expect(shown.last.moveHistory, [theirStep]);
    expect(controller.game?.moveCount, 1);
  });

  test(
    'a refused move with nothing newer goes back to what was there',
    () async {
      final submitting = controller.submitMove(myStep);
      service.submitResults.single.complete(
        const OnlineResult.failed(OnlineFailure.illegalMove),
      );
      expect(await submitting, isFalse);
      expect(shown.last.moveHistory, isEmpty);
      expect(controller.game?.moveCount, 0);
    },
  );
}
