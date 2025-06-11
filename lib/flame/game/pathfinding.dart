import '../constants.dart';
import '../models/game_state.dart';

class PathNode {
  final Position position;
  final int gCost; // Distance from start
  final int hCost; // Distance to target
  final PathNode? parent;

  PathNode(this.position, this.gCost, this.hCost, [this.parent]);

  int get fCost => gCost + hCost;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PathNode && other.position == position;
  }

  @override
  int get hashCode => position.hashCode;
}

class Pathfinding {
  // A* algorithm to find shortest path from start to any position in target row
  static List<Position>? findShortestPath(
    GameState gameState,
    Position start,
    int targetRow,
  ) {
    final openSet = PriorityQueue<PathNode>(
      (a, b) => a.fCost.compareTo(b.fCost),
    );
    final closedSet = <Position>{};
    final gScores = <Position, int>{};

    final startNode = PathNode(start, 0, _calculateHeuristic(start, targetRow));
    openSet.add(startNode);
    gScores[start] = 0;

    while (openSet.isNotEmpty) {
      final currentNode = openSet.removeFirst();

      // Check if we reached the target row
      if (currentNode.position.row == targetRow) {
        return _reconstructPath(currentNode);
      }

      closedSet.add(currentNode.position);

      // Explore neighbors
      final neighbors = gameState.getValidMoves(currentNode.position);

      for (final neighborPos in neighbors) {
        if (closedSet.contains(neighborPos)) continue;

        final tentativeGScore = currentNode.gCost + 1;
        final existingGScore = gScores[neighborPos];

        if (existingGScore == null || tentativeGScore < existingGScore) {
          gScores[neighborPos] = tentativeGScore;
          final hCost = _calculateHeuristic(neighborPos, targetRow);
          final neighborNode = PathNode(
            neighborPos,
            tentativeGScore,
            hCost,
            currentNode,
          );

          openSet.add(neighborNode);
        }
      }
    }

    return null; // No path found
  }

  // Check if a wall placement would block all paths for any player
  static bool wouldWallBlockAllPaths(GameState gameState, Wall wall) {
    // Create temporary game state with the wall
    final tempGameState = _createTempGameStateWithWall(gameState, wall);

    // Check if both players still have valid paths
    final player1Path = findShortestPath(
      tempGameState,
      tempGameState.player1.position,
      tempGameState.player1.goalRow,
    );

    final player2Path = findShortestPath(
      tempGameState,
      tempGameState.player2.position,
      tempGameState.player2.goalRow,
    );

    return player1Path == null || player2Path == null;
  }

  // Calculate shortest path lengths for both players
  static Map<int, int> calculatePathLengths(GameState gameState) {
    final player1Path = findShortestPath(
      gameState,
      gameState.player1.position,
      gameState.player1.goalRow,
    );

    final player2Path = findShortestPath(
      gameState,
      gameState.player2.position,
      gameState.player2.goalRow,
    );

    return {1: player1Path?.length ?? 999, 2: player2Path?.length ?? 999};
  }

  // Find the best wall placement to maximize opponent\'s path
  static Wall? findBestWallPlacement(GameState gameState, int playerId) {
    final opponentId = playerId == 1 ? 2 : 1;
    final opponentPos = opponentId == 1
        ? gameState.player1.position
        : gameState.player2.position;
    final opponentGoal = opponentId == 1
        ? gameState.player1.goalRow
        : gameState.player2.goalRow;

    Wall? bestWall;
    int maxPathIncrease = 0;

    // Get current opponent path length
    final currentPath = findShortestPath(gameState, opponentPos, opponentGoal);
    final currentLength = currentPath?.length ?? 0;

    if (currentLength == 0) return null;

    // Try all possible wall placements
    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        // Try horizontal wall
        final horizontalWall = Wall(
          Position(row, col),
          WallOrientation.horizontal,
        );

        if (_isValidWallPlacement(gameState, horizontalWall)) {
          final tempGameState = _createTempGameStateWithWall(
            gameState,
            horizontalWall,
          );
          final newPath = findShortestPath(
            tempGameState,
            opponentPos,
            opponentGoal,
          );
          final newLength = newPath?.length ?? 999;

          final pathIncrease = newLength - currentLength;
          if (pathIncrease > maxPathIncrease) {
            maxPathIncrease = pathIncrease;
            bestWall = horizontalWall;
          }
        }

        // Try vertical wall
        final verticalWall = Wall(Position(row, col), WallOrientation.vertical);

        if (_isValidWallPlacement(gameState, verticalWall)) {
          final tempGameState = _createTempGameStateWithWall(
            gameState,
            verticalWall,
          );
          final newPath = findShortestPath(
            tempGameState,
            opponentPos,
            opponentGoal,
          );
          final newLength = newPath?.length ?? 999;

          final pathIncrease = newLength - currentLength;
          if (pathIncrease > maxPathIncrease) {
            maxPathIncrease = pathIncrease;
            bestWall = verticalWall;
          }
        }
      }
    }

    return bestWall;
  }

  static int _calculateHeuristic(Position position, int targetRow) {
    return (position.row - targetRow).abs();
  }

  static List<Position> _reconstructPath(PathNode node) {
    final path = <Position>[];
    PathNode? current = node;

    while (current != null) {
      path.insert(0, current.position);
      current = current.parent;
    }

    return path;
  }

  static GameState _createTempGameStateWithWall(GameState original, Wall wall) {
    return GameState(
      gameId: original.gameId,
      player1: original.player1,
      player2: original.player2,
      walls: [...original.walls, wall],
      currentPlayerId: original.currentPlayerId,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
    );
  }

  static bool _isValidWallPlacement(GameState gameState, Wall wall) {
    // Check bounds
    if (wall.position.row < 0 || wall.position.col < 0) return false;

    if (wall.orientation == WallOrientation.horizontal) {
      if (wall.position.row >= GameConstants.boardSize ||
          wall.position.col >= GameConstants.boardSize - 1) {
        return false;
      }
    } else {
      if (wall.position.row >= GameConstants.boardSize - 1 ||
          wall.position.col >= GameConstants.boardSize) {
        return false;
      }
    }

    // Check if wall overlaps with existing walls
    for (final existingWall in gameState.walls) {
      if (_wallsOverlap(wall, existingWall)) {
        return false;
      }
    }

    // Check if wall would block all paths
    return !wouldWallBlockAllPaths(gameState, wall);
  }

  static bool _wallsOverlap(Wall wall1, Wall wall2) {
    if (wall1.orientation != wall2.orientation) return false;

    if (wall1.orientation == WallOrientation.horizontal) {
      return wall1.position.row == wall2.position.row &&
          (wall1.position.col == wall2.position.col ||
              wall1.position.col == wall2.position.col + 1 ||
              wall1.position.col == wall2.position.col - 1);
    } else {
      return wall1.position.col == wall2.position.col &&
          (wall1.position.row == wall2.position.row ||
              wall1.position.row == wall2.position.row + 1 ||
              wall1.position.row == wall2.position.row - 1);
    }
  }
}

// Simple priority queue implementation
class PriorityQueue<T> {
  final List<T> _heap = [];
  final int Function(T, T) _compare;

  PriorityQueue(this._compare);

  bool get isEmpty => _heap.isEmpty;
  bool get isNotEmpty => _heap.isNotEmpty;

  void add(T item) {
    _heap.add(item);
    _siftUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) throw StateError('Queue is empty');

    final result = _heap.first;
    final last = _heap.removeLast();

    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _siftDown(0);
    }

    return result;
  }

  void _siftUp(int index) {
    while (index > 0) {
      final parentIndex = (index - 1) ~/ 2;
      if (_compare(_heap[index], _heap[parentIndex]) >= 0) break;

      _swap(index, parentIndex);
      index = parentIndex;
    }
  }

  void _siftDown(int index) {
    while (true) {
      var minIndex = index;
      final leftChild = 2 * index + 1;
      final rightChild = 2 * index + 2;

      if (leftChild < _heap.length &&
          _compare(_heap[leftChild], _heap[minIndex]) < 0) {
        minIndex = leftChild;
      }

      if (rightChild < _heap.length &&
          _compare(_heap[rightChild], _heap[minIndex]) < 0) {
        minIndex = rightChild;
      }

      if (minIndex == index) break;

      _swap(index, minIndex);
      index = minIndex;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}
