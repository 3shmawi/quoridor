import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai/quoridor_engine.dart';
import 'package:quoridor/flame/services/game_service.dart';

void main() {
  _timeoutMoveTests();

  GameState game({
    required Position p1,
    required Position p2,
    List<Wall> walls = const [],
    int currentPlayerId = 1,
    int p1Walls = 10,
    int p2Walls = 10,
  }) {
    final state = GameStateFactory.createNewGame(
      gameId: 'engine-test',
      player2IsAI: true,
    );
    state.player1.moveTo(p1);
    state.player2.moveTo(p2);
    state.player1.wallsRemaining = p1Walls;
    state.player2.wallsRemaining = p2Walls;
    state.walls.addAll(walls);
    state.currentPlayerId = currentPlayerId;
    return state;
  }

  group('distance uses the real route, not row difference', () {
    test('counts plain steps on an empty board', () {
      final state = game(p1: const Position(8, 4), p2: const Position(0, 4));
      // Player 1 starts on row 8 and runs to row 0.
      expect(QuoridorEngine.distanceToGoal(state, state.player1), 8);
      expect(QuoridorEngine.distanceToGoal(state, state.player2), 8);
    });

    test('a wall across the route makes the distance longer', () {
      final open = game(p1: const Position(8, 4), p2: const Position(0, 4));
      final blocked = game(
        p1: const Position(8, 4),
        p2: const Position(0, 4),
        walls: const [
          Wall(Position(8, 3), WallOrientation.horizontal),
          Wall(Position(8, 5), WallOrientation.horizontal),
        ],
      );

      expect(
        QuoridorEngine.distanceToGoal(blocked, blocked.player1),
        greaterThan(QuoridorEngine.distanceToGoal(open, open.player1)!),
      );
    });
  });

  group('the shuffle the old AI got stuck in', () {
    /// Reproduces the reported position: player 2 is walled in along the row
    /// below it, so no sideways step reduces its row difference and the old
    /// row-distance AI bounced between two squares forever.
    GameState walledIn() => game(
      p1: const Position(8, 4),
      p2: const Position(1, 1),
      walls: const [
        Wall(Position(2, 0), WallOrientation.horizontal),
        Wall(Position(2, 2), WallOrientation.horizontal),
        Wall(Position(2, 4), WallOrientation.horizontal),
      ],
      currentPlayerId: 2,
    );

    test('the position really does block the direct route', () {
      final state = walledIn();
      expect(
        state.isWallBlocking(const Position(1, 1), const Position(2, 1)),
        isTrue,
      );
    });

    test('every strength makes real progress instead of shuffling', () {
      for (final strength in EngineStrength.values) {
        final state = walledIn();
        final before = QuoridorEngine.distanceToGoal(state, state.player2)!;

        final move = QuoridorEngine.bestMove(
          state,
          strength,
          random: Random(1),
        );
        expect(move, isNotNull, reason: '$strength found no move');

        if (move!.type == MoveType.wallPlace) continue; // Blocking is progress.

        final after = QuoridorEngine.applyMove(state, move);
        final distance = QuoridorEngine.distanceToGoal(after, after.player2)!;

        expect(
          distance,
          lessThan(before),
          reason: '$strength moved without getting closer to its goal',
        );
      }
    });

    test('it does not walk back and forth across several turns', () {
      var state = walledIn();
      final visited = <Position>[];

      // Play out the AI's own moves, leaving the human pawn where it is.
      for (var turn = 0; turn < 6; turn++) {
        final move = QuoridorEngine.bestMove(
          state,
          EngineStrength.hard,
          random: Random(turn),
        );
        if (move == null || move.type == MoveType.wallPlace) break;

        state = QuoridorEngine.applyMove(state, move);
        visited.add(state.player2.position);

        // Hand the turn straight back so only the AI is moving.
        state.currentPlayerId = 2;
      }

      expect(
        visited.length,
        visited.toSet().length,
        reason: 'the AI returned to a square it had already been on: $visited',
      );
    });
  });

  group('it plays the obvious moves', () {
    test('steps onto the goal row when it can win', () {
      final state = game(
        p1: const Position(8, 4),
        p2: const Position(7, 4),
        currentPlayerId: 2,
      );

      final move = QuoridorEngine.bestMove(state, EngineStrength.hard);
      expect(move!.type, MoveType.pawnMove);
      expect(move.newPosition?.row, GameConstants.player2Goal);
    });

    test('only ever returns moves the rules accept', () {
      var state = GameStateFactory.createNewGame(player2IsAI: true);

      for (var turn = 0; turn < 12 && !state.isGameOver; turn++) {
        final move = QuoridorEngine.bestMove(
          state,
          EngineStrength.medium,
          random: Random(turn),
        );
        expect(move, isNotNull);
        expect(
          GameService.isValidMove(state, move!),
          isTrue,
          reason: 'engine proposed an illegal move on turn $turn',
        );
        state = GameService.executeMove(state, move);
      }
    });
  });

  group('strength', () {
    test('a deeper search is at least as good at a decisive position', () {
      // Player 2 runs to row 8, so row 7 is one step from winning.
      final state = game(
        p1: const Position(8, 4),
        p2: const Position(7, 2),
        currentPlayerId: 2,
      );

      for (final strength in [EngineStrength.medium, EngineStrength.hard]) {
        final move = QuoridorEngine.bestMove(state, strength);
        expect(
          move!.newPosition?.row,
          GameConstants.player2Goal,
          reason: '$strength did not take the win',
        );
      }
    });

    test('a move is found quickly enough to feel instant', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      state.currentPlayerId = 2;

      final watch = Stopwatch()..start();
      QuoridorEngine.bestMove(state, EngineStrength.hard);
      watch.stop();

      expect(
        watch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'hard took ${watch.elapsedMilliseconds}ms',
      );
    });
  });
}

void _timeoutMoveTests() {
  group('the move played when a turn times out', () {
    test('is always a pawn move, never a wall', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      final move = QuoridorEngine.stepTowardsGoal(state);

      expect(move, isNotNull);
      expect(move!.type, MoveType.pawnMove);
    });

    test('spends none of the player\'s walls', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      final before = state.player1.wallsRemaining;

      final after = QuoridorEngine.applyMove(
        state,
        QuoridorEngine.stepTowardsGoal(state)!,
      );

      expect(after.player1.wallsRemaining, before);
    });

    test('shortens the route to the goal', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      final before = QuoridorEngine.distanceToGoal(state, state.player1)!;

      final after = QuoridorEngine.applyMove(
        state,
        QuoridorEngine.stepTowardsGoal(state)!,
      );

      expect(QuoridorEngine.distanceToGoal(after, after.player1), before - 1);
    });

    test('goes round a wall rather than stalling in front of it', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      // Across the square directly in front of player 1, who starts at (8,4).
      state.walls.add(const Wall(Position(8, 3), WallOrientation.horizontal));
      state.walls.add(const Wall(Position(8, 4), WallOrientation.horizontal));

      final before = QuoridorEngine.distanceToGoal(state, state.player1)!;
      final after = QuoridorEngine.applyMove(
        state,
        QuoridorEngine.stepTowardsGoal(state)!,
      );

      expect(
        QuoridorEngine.distanceToGoal(after, after.player1),
        lessThan(before),
      );
    });

    test('takes the goal when it is one step away', () {
      final state = GameStateFactory.createNewGame(player2IsAI: true);
      state.player1.moveTo(const Position(1, 4));

      final after = QuoridorEngine.applyMove(
        state,
        QuoridorEngine.stepTowardsGoal(state)!,
      );

      expect(after.player1.hasReachedGoal, isTrue);
    });
  });
}
