import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai/quoridor_engine.dart';
import 'package:quoridor/flame/services/game_service.dart';

/// A position a player reported the computer getting stuck in.
///
/// Player 2 sits at (6,6) with no walls left, boxed in on three sides, and the
/// only way out is up and round the right-hand edge — a route that starts by
/// moving *away* from the goal. The engine that shipped before this was fixed
/// wandered a twelve-square loop here and came back no closer, which is what
/// "the computer keeps repeating itself" looked like from the player's side.
GameState reportedPosition() {
  final state = GameStateFactory.createNewGame(player2IsAI: true);

  state.player1.moveTo(const Position(1, 1));
  state.player2.moveTo(const Position(6, 6));

  const player2Walls = [
    Wall(Position(1, 4), WallOrientation.horizontal),
    Wall(Position(1, 4), WallOrientation.vertical),
    Wall(Position(1, 6), WallOrientation.vertical),
    Wall(Position(3, 5), WallOrientation.horizontal),
    Wall(Position(3, 7), WallOrientation.horizontal),
    Wall(Position(3, 4), WallOrientation.vertical),
    Wall(Position(4, 4), WallOrientation.horizontal),
    Wall(Position(4, 6), WallOrientation.horizontal),
    Wall(Position(5, 4), WallOrientation.vertical),
    Wall(Position(6, 2), WallOrientation.horizontal),
  ];

  // The three walls sealing the bottom edge, and the one closing column 7.
  const player1Walls = [
    Wall(Position(6, 8), WallOrientation.vertical),
    Wall(Position(8, 2), WallOrientation.horizontal),
    Wall(Position(8, 4), WallOrientation.horizontal),
    Wall(Position(8, 6), WallOrientation.horizontal),
  ];

  state.walls.addAll(player2Walls);
  state.walls.addAll(player1Walls);
  for (var i = 0; i < player2Walls.length; i++) {
    state.player2.useWall();
  }
  for (var i = 0; i < player1Walls.length; i++) {
    state.player1.useWall();
  }

  state.currentPlayerId = 2;
  return state;
}

void main() {
  test('the position is set up as reported', () {
    final state = reportedPosition();

    expect(state.player2.wallsRemaining, 0);
    expect(QuoridorEngine.distanceToGoal(state, state.player2), 6);
  });

  for (final strength in EngineStrength.values) {
    test('$strength walks out instead of circling', () {
      var state = reportedPosition();
      final squares = <Position>[];

      // The opponent is one step from winning and simply waits, exactly as in
      // the report — so nothing but the computer's own play moves this on.
      for (var ply = 0; ply < 40 && !state.isGameOver; ply++) {
        if (state.currentPlayerId == 2) {
          final move = QuoridorEngine.bestMove(state, strength);
          expect(move, isNotNull);
          if (move!.type == MoveType.pawnMove) squares.add(move.newPosition!);
          state = GameService.executeMove(state, move);
        } else {
          state = GameService.executeMove(
            state,
            GameMove.pawnMove(
              state.player1.position == const Position(1, 1)
                  ? const Position(1, 0)
                  : const Position(1, 1),
              1,
            ),
          );
        }
      }

      expect(
        state.player2.hasReachedGoal,
        isTrue,
        reason:
            'stopped at ${state.player2.position} after ${squares.length} '
            'moves: ${squares.join(' -> ')}',
      );

      // Six is the shortest route out, so anything longer is a detour.
      expect(squares.length, 6);
      expect(
        squares.toSet().length,
        squares.length,
        reason: 'revisited a square',
      );
    });
  }
}
