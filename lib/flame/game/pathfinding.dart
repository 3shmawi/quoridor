import '../constants.dart';
import '../models/game_state.dart';

/// Route questions the rules ask about walls.
class Pathfinding {
  Pathfinding._();

  /// Whether [wall] would leave somebody with no route to their goal.
  ///
  /// Every seat is checked, not just the first two: in a four-player game a
  /// wall that shuts one player in is just as illegal, and only looking at
  /// two of them would let it through.
  static bool wouldWallBlockAllPaths(GameState gameState, Wall wall) {
    final tempGameState = _createTempGameStateWithWall(gameState, wall);

    return tempGameState.players.any(
      (player) => !canReachGoal(tempGameState, player.position, player.goal),
    );
  }

  /// Whether walls alone leave a way from [start] to [goal].
  ///
  /// Pawns are left out on purpose. The rule is that a wall may not cut a
  /// player off from their goal, and a pawn standing in a corridor moves on;
  /// routing around pawns, as [findShortestPath] does, refused legal walls
  /// whenever two pawns stood in a line in a narrow passage, which a table of
  /// three or four sets up readily.
  static bool canReachGoal(GameState gameState, Position start, GoalEdge goal) {
    const size = GameConstants.boardSize;
    const steps = [
      Position(-1, 0),
      Position(1, 0),
      Position(0, -1),
      Position(0, 1),
    ];

    final seen = <Position>{start};
    final queue = <Position>[start];

    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      if (goal.contains(current)) return true;

      for (final step in steps) {
        final next = Position(current.row + step.row, current.col + step.col);
        if (next.row < 0 || next.row >= size || next.col < 0) continue;
        if (next.col >= size) continue;
        if (gameState.isWallBlocking(current, next)) continue;
        if (seen.add(next)) queue.add(next);
      }
    }

    return false;
  }

  static GameState _createTempGameStateWithWall(GameState original, Wall wall) {
    return original.copyWith(walls: [...original.walls, wall]);
  }
}
