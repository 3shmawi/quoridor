import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/game_service.dart';

void main() {
  GameState freshGame() => GameStateFactory.createNewGame(player2IsAI: false);

  WallPlacementResult check(GameState state, Wall wall) =>
      GameService.validateWallPlacement(state, state.currentPlayer, wall);

  group('wall bounds', () {
    test('accepts a wall on an interior groove', () {
      final state = freshGame();
      expect(
        check(state, const Wall(Position(4, 3), WallOrientation.horizontal))
            .isValid,
        isTrue,
      );
      expect(
        check(state, const Wall(Position(3, 4), WallOrientation.vertical))
            .isValid,
        isTrue,
      );
    });

    test('rejects a horizontal wall on the top edge', () {
      // Row 0 would sit on the board boundary and block nothing.
      final result = check(
        freshGame(),
        const Wall(Position(0, 3), WallOrientation.horizontal),
      );
      expect(result.rejection, WallRejection.outOfBounds);
    });

    test('rejects a vertical wall on the left edge', () {
      final result = check(
        freshGame(),
        const Wall(Position(3, 0), WallOrientation.vertical),
      );
      expect(result.rejection, WallRejection.outOfBounds);
    });

    test('rejects a wall whose second half falls off the board', () {
      final result = check(
        freshGame(),
        Wall(
          const Position(4, GameConstants.boardSize - 1),
          WallOrientation.horizontal,
        ),
      );
      expect(result.rejection, WallRejection.outOfBounds);
    });
  });

  group('wall conflicts', () {
    test('rejects an exact duplicate', () {
      final state = freshGame()
        ..walls.add(const Wall(Position(4, 3), WallOrientation.horizontal));
      final result = check(
        state,
        const Wall(Position(4, 3), WallOrientation.horizontal),
      );
      expect(result.rejection, WallRejection.overlaps);
    });

    test('rejects a same-orientation wall that half-overlaps', () {
      final state = freshGame()
        ..walls.add(const Wall(Position(4, 3), WallOrientation.horizontal));
      expect(
        check(state, const Wall(Position(4, 4), WallOrientation.horizontal))
            .rejection,
        WallRejection.overlaps,
      );
      expect(
        check(state, const Wall(Position(4, 2), WallOrientation.horizontal))
            .rejection,
        WallRejection.overlaps,
      );
    });

    test('allows a same-orientation wall two columns away', () {
      final state = freshGame()
        ..walls.add(const Wall(Position(4, 3), WallOrientation.horizontal));
      expect(
        check(state, const Wall(Position(4, 5), WallOrientation.horizontal))
            .isValid,
        isTrue,
      );
    });

    test('rejects a vertical wall crossing a horizontal one', () {
      // Horizontal (4, 3) is centred on intersection (4, 4); the vertical wall
      // centred on the same intersection is (3, 4).
      final state = freshGame()
        ..walls.add(const Wall(Position(4, 3), WallOrientation.horizontal));
      final result = check(
        state,
        const Wall(Position(3, 4), WallOrientation.vertical),
      );
      expect(result.rejection, WallRejection.crosses);
    });

    test('allows a perpendicular wall on a different intersection', () {
      final state = freshGame()
        ..walls.add(const Wall(Position(4, 3), WallOrientation.horizontal));
      expect(
        check(state, const Wall(Position(3, 6), WallOrientation.vertical))
            .isValid,
        isTrue,
      );
    });
  });

  group('wall must leave a path', () {
    test('rejects a wall that would seal a player in', () {
      final state = freshGame();

      // Fence player 2 (which starts on (0, 4)) into a two-cell pocket along
      // the top edge: a vertical wall on each side of cells (0, 4) and (0, 5).
      state.walls.addAll(const [
        Wall(Position(0, 4), WallOrientation.vertical),
        Wall(Position(0, 6), WallOrientation.vertical),
      ]);

      // Closing the floor under that pocket leaves player 2 with no route to
      // row 8, so the placement must be refused.
      final result = check(
        state,
        const Wall(Position(1, 4), WallOrientation.horizontal),
      );
      expect(result.rejection, WallRejection.blocksPlayer);
    });

    test('allows a wall that only lengthens the path', () {
      final state = freshGame();
      expect(
        check(state, const Wall(Position(1, 4), WallOrientation.horizontal))
            .isValid,
        isTrue,
      );
    });
  });

  group('wall supply', () {
    test('rejects placement when the player has no walls left', () {
      final state = freshGame();
      state.player1.wallsRemaining = 0;
      final result = check(
        state,
        const Wall(Position(4, 3), WallOrientation.horizontal),
      );
      expect(result.rejection, WallRejection.noWallsLeft);
    });
  });

  group('rejection messages', () {
    test('every rejection explains itself', () {
      for (final rejection in WallRejection.values) {
        expect(WallPlacementResult(rejection).message, isNotEmpty);
      }
    });
  });
}
