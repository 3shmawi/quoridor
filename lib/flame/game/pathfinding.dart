import 'dart:math' as math;

import '../core/constants.dart';
import '../models/game_state.dart';

enum GamePhase { early, mid, late }

class PathNode {
  final Position position;
  final int gCost; // Distance from start
  final double hCost; // Distance to target
  final PathNode? parent;
  final int
  alternativePathCount; // Track how many alternative paths we've explored

  PathNode(
    this.position,
    this.gCost,
    this.hCost, [
    this.parent,
    this.alternativePathCount = 0,
  ]);

  double get fCost => gCost + hCost;

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
    final alternativePaths = <List<Position>>[];
    final random = math.Random();

    final startNode = PathNode(
      start,
      0,
      _calculateHeuristic(start, targetRow, gameState),
    );
    openSet.add(startNode);
    gScores[start] = 0;

    while (openSet.isNotEmpty) {
      final currentNode = openSet.removeFirst();

      // Check if we reached the target row
      if (currentNode.position.row == targetRow) {
        final path = _reconstructPath(currentNode);

        // Sometimes explore alternative paths even when we found a good one
        if (random.nextDouble() < 0.3 && alternativePaths.length < 3) {
          // 30% chance to explore more
          // Add current path to alternatives
          alternativePaths.add(path);

          // Continue searching for more paths
          closedSet.remove(currentNode.position);
          continue;
        }

        // Choose between found paths
        if (alternativePaths.isNotEmpty) {
          alternativePaths.add(path);
          // Sometimes choose a longer but more strategic path
          if (random.nextDouble() < 0.4) {
            // 40% chance to choose alternative
            final selectedPath = _selectBestAlternativePath(
              alternativePaths,
              gameState,
            );

            return selectedPath;
          }
        }

        return path;
      }

      closedSet.add(currentNode.position);

      // Explore neighbors
      final neighbors = gameState.getValidMoves(currentNode.position);

      // Sometimes shuffle neighbors to explore different paths
      if (random.nextDouble() < 0.2) {
        // 20% chance to shuffle
        neighbors.shuffle(random);
      }

      for (final neighborPos in neighbors) {
        if (closedSet.contains(neighborPos)) continue;

        final tentativeGScore = currentNode.gCost + 1;
        final existingGScore = gScores[neighborPos];

        if (existingGScore == null || tentativeGScore < existingGScore) {
          gScores[neighborPos] = tentativeGScore;
          final hCost = _calculateHeuristic(neighborPos, targetRow, gameState);

          // Add some randomness to the heuristic to explore different paths
          final randomizedHCost =
              hCost * (0.9 + random.nextDouble() * 0.2); // ±10% variation

          final neighborNode = PathNode(
            neighborPos,
            tentativeGScore,
            randomizedHCost,
            currentNode,
            currentNode.alternativePathCount + 1,
          );

          openSet.add(neighborNode);
        }
      }
    }

    // If we have alternative paths but didn't find a direct path, return the best alternative
    if (alternativePaths.isNotEmpty) {
      final bestPath = _selectBestAlternativePath(alternativePaths, gameState);

      return bestPath;
    }

    return null; // No path found
  }

  static List<Position> _selectBestAlternativePath(
    List<List<Position>> paths,
    GameState gameState,
  ) {
    if (paths.isEmpty) return [];

    // Score each path based on multiple factors
    final pathScores = paths.map((path) {
      double score = 0;

      // Prefer paths that maintain distance from opponent
      final opponentPos = gameState.currentPlayerId == 1
          ? gameState.players[1].position
          : gameState.players[0].position;

      for (final pos in path) {
        final distance = math.sqrt(
          math.pow(pos.row - opponentPos.row, 2) +
              math.pow(pos.col - opponentPos.col, 2),
        );
        score += distance;
      }

      // Prefer paths that stay closer to center
      final center = GameConstants.boardSize / 2;
      for (final pos in path) {
        final distanceFromCenter = math.sqrt(
          math.pow(pos.row - center, 2) + math.pow(pos.col - center, 2),
        );
        score -= distanceFromCenter * 0.5;
      }

      // Slight penalty for longer paths
      score -= path.length * 0.2;

      return score;
    }).toList();

    // Find the path with the highest score
    final bestScoreIndex = pathScores.indexOf(pathScores.reduce(math.max));
    return paths[bestScoreIndex];
  }

  // Check if a wall placement would block all paths for any player
  static bool wouldWallBlockAllPaths(GameState gameState, Wall wall) {
    // Create temporary game state with the wall
    final tempGameState = _createTempGameStateWithWall(gameState, wall);

    // Check if both players still have valid paths
    final player1Path = findShortestPath(
      tempGameState,
      tempGameState.players[0].position,
      tempGameState.players[0].goalRow,
    );

    final player2Path = findShortestPath(
      tempGameState,
      tempGameState.players[1].position,
      tempGameState.players[1].goalRow,
    );

    return player1Path == null || player2Path == null;
  }

  // Calculate shortest path lengths for both players
  static Map<int, int> calculatePathLengths(GameState gameState) {
    final player1Path = findShortestPath(
      gameState,
      gameState.players[0].position,
      gameState.players[0].goalRow,
    );

    final player2Path = findShortestPath(
      gameState,
      gameState.players[1].position,
      gameState.players[1].goalRow,
    );

    return {1: player1Path?.length ?? 999, 2: player2Path?.length ?? 999};
  }

  // Enhanced heuristic calculation
  static double _calculateHeuristic(
    Position position,
    int targetRow,
    GameState gameState,
  ) {
    // Base Manhattan distance
    final baseDistance = (position.row - targetRow).abs().toDouble();

    // Consider walls in the path
    final wallPenalty = _calculateWallPenalty(position, targetRow, gameState);

    // Consider opponent's position (avoid getting too close)
    final opponentPenalty = _calculateOpponentPenalty(position, gameState);

    // Consider board edges (prefer paths closer to center)
    final edgePenalty = _calculateEdgePenalty(position);

    return baseDistance + wallPenalty + opponentPenalty + edgePenalty;
  }

  static double _calculateWallPenalty(
    Position position,
    int targetRow,
    GameState gameState,
  ) {
    double penalty = 0;
    final direction = position.row < targetRow ? 1 : -1;

    // Check for walls in the path to target row
    for (int row = position.row; row != targetRow; row += direction) {
      for (final wall in gameState.walls) {
        if (wall.orientation == WallOrientation.horizontal) {
          if (wall.position.row == row &&
              wall.position.col <= position.col &&
              wall.position.col + 1 >= position.col) {
            penalty += 2;
          }
        }
      }
    }

    return penalty;
  }

  static double _calculateOpponentPenalty(
    Position position,
    GameState gameState,
  ) {
    final opponentPos = gameState.currentPlayerId == 1
        ? gameState.players[1].position
        : gameState.players[0].position;

    final distance = math.sqrt(
      math.pow(position.row - opponentPos.row, 2) +
          math.pow(position.col - opponentPos.col, 2),
    );

    // Add penalty if too close to opponent
    return distance < 2 ? 3 : 0;
  }

  static double _calculateEdgePenalty(Position position) {
    final center = GameConstants.boardSize / 2;
    final distanceFromCenter = math.sqrt(
      math.pow(position.row - center, 2) + math.pow(position.col - center, 2),
    );

    return distanceFromCenter * 0.2;
  }

  // Find the best wall placement to maximize opponent\'s path
  static Wall? findBestWallPlacement(
    GameState gameState,
    int playerId, {
    List<Wall>? recentAIWalls,
  }) {
    final opponentId = playerId == 1 ? 2 : 1;
    final opponentPos = opponentId == 1
        ? gameState.players[0].position
        : gameState.players[1].position;
    final opponentGoal = opponentId == 1
        ? gameState.players[0].goalRow
        : gameState.players[1].goalRow;

    // Get current opponent path length
    final currentPath = findShortestPath(gameState, opponentPos, opponentGoal);
    final currentLength = currentPath?.length ?? 0;

    if (currentLength == 0) return null;

    // Store multiple good wall placements instead of just the best one
    final goodWalls = <Wall>[];
    final wallScores = <Wall, double>{};
    double bestScore = double.negativeInfinity;
    final random = math.Random();
    final recentWalls = recentAIWalls ?? [];

    // Try all possible wall placements
    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        // Try horizontal wall
        final horizontalWall = Wall(
          Position(row, col),
          WallOrientation.horizontal,
        );

        if (_isValidWallPlacement(gameState, horizontalWall)) {
          final score = _evaluateWallPlacement(
            gameState,
            horizontalWall,
            opponentPos,
            opponentGoal,
            currentLength,
            recentWalls,
          );
          // Add some randomness to prevent predictable patterns
          final randomizedScore =
              score * (0.9 + random.nextDouble() * 0.2); // ±10% variation
          wallScores[horizontalWall] = randomizedScore;
          if (randomizedScore > bestScore) {
            bestScore = randomizedScore;
          }
        }

        // Try vertical wall
        final verticalWall = Wall(Position(row, col), WallOrientation.vertical);

        if (_isValidWallPlacement(gameState, verticalWall)) {
          final score = _evaluateWallPlacement(
            gameState,
            verticalWall,
            opponentPos,
            opponentGoal,
            currentLength,
            recentWalls,
          );
          // Add some randomness to prevent predictable patterns
          final randomizedScore =
              score * (0.9 + random.nextDouble() * 0.2); // ±10% variation
          wallScores[verticalWall] = randomizedScore;
          if (randomizedScore > bestScore) {
            bestScore = randomizedScore;
          }
        }
      }
    }

    // Collect walls that are close to the best score
    final threshold =
        bestScore * 0.85; // Consider walls within 85% of best score
    wallScores.forEach((wall, score) {
      if (score >= threshold) {
        goodWalls.add(wall);
      }
    });

    // If we have multiple good options, choose one based on strategy
    Wall? selectedWall;
    if (goodWalls.isNotEmpty) {
      // Sometimes choose a wall that creates a bottleneck
      if (random.nextDouble() < 0.3) {
        // 30% chance
        final bottleneckWalls = goodWalls
            .where((wall) => _createsBottleneck(wall, gameState))
            .toList();
        if (bottleneckWalls.isNotEmpty) {
          selectedWall =
              bottleneckWalls[random.nextInt(bottleneckWalls.length)];
        }
      }
      // Sometimes choose a wall that controls center
      if (selectedWall == null && random.nextDouble() < 0.3) {
        // 30% chance
        final centerWalls = goodWalls
            .where((wall) => _controlsCenter(wall, gameState))
            .toList();
        if (centerWalls.isNotEmpty) {
          selectedWall = centerWalls[random.nextInt(centerWalls.length)];
        }
      }
      // If no special strategy was chosen, pick randomly from good walls
      selectedWall ??= goodWalls[random.nextInt(goodWalls.length)];
    }

    return selectedWall;
  }

  static double _evaluateWallPlacement(
    GameState gameState,
    Wall wall,
    Position opponentPos,
    int opponentGoal,
    int currentPathLength,
    List<Wall> recentAIWalls,
  ) {
    final tempGameState = _createTempGameStateWithWall(gameState, wall);
    final newPath = findShortestPath(tempGameState, opponentPos, opponentGoal);
    final newLength = newPath?.length ?? 999;
    // Base score is the path length increase
    double score = (newLength - currentPathLength).toDouble();
    // Penalize repeated wall placements
    if (recentAIWalls.any(
      (w) => w.position == wall.position && w.orientation == wall.orientation,
    )) {
      score -= 5.0;
    }
    // Bonus for walls that force opponent to move away from center
    final center = GameConstants.boardSize / 2;
    final distanceFromCenter = math.sqrt(
      math.pow(opponentPos.row - center, 2) +
          math.pow(opponentPos.col - center, 2),
    );
    score += distanceFromCenter * 0.1;

    // Penalty for walls that are too far from opponent
    final distanceToOpponent = math.sqrt(
      math.pow(wall.position.row - opponentPos.row, 2) +
          math.pow(wall.position.col - opponentPos.col, 2),
    );
    score -= distanceToOpponent * 0.2;

    // Bonus for walls that block multiple potential paths
    score += _calculatePathBlockingScore(wall, gameState);

    // Consider game phase
    final gamePhase = _calculateGamePhase(gameState);
    if (gamePhase == GamePhase.early) {
      // Early game: prefer walls that create long-term advantages
      score += _evaluateLongTermImpact(wall, gameState) * 0.3;
    } else if (gamePhase == GamePhase.late) {
      // Late game: focus more on immediate path blocking
      score += _evaluateImmediateBlocking(wall, gameState) * 0.4;
    }

    // Additional strategic considerations
    if (_createsBottleneck(wall, gameState)) {
      score += 2.0;
    }

    if (_controlsCenter(wall, gameState)) {
      score += 1.5;
    }

    if (_createsMultiplePaths(wall, gameState)) {
      score += 1.0;
    }

    return score;
  }

  static GamePhase _calculateGamePhase(GameState gameState) {
    final totalWalls = gameState.walls.length;
    final maxWalls =
        GameConstants.maxWallsPerPlayer * 2; // Total walls for both players

    if (totalWalls < maxWalls * 0.3) return GamePhase.early;
    if (totalWalls < maxWalls * 0.7) return GamePhase.mid;
    return GamePhase.late;
  }

  static double _evaluateLongTermImpact(Wall wall, GameState gameState) {
    double score = 0;

    // Check if wall creates a bottleneck
    if (_createsBottleneck(wall, gameState)) {
      score += 2.0;
    }

    // Check if wall helps control center
    if (_controlsCenter(wall, gameState)) {
      score += 1.5;
    }

    // Check if wall creates multiple paths for self
    if (_createsMultiplePaths(wall, gameState)) {
      score += 1.0;
    }

    return score;
  }

  static double _evaluateImmediateBlocking(Wall wall, GameState gameState) {
    double score = 0;

    // Check if wall directly blocks opponent's shortest path
    if (_blocksShortestPath(wall, gameState)) {
      score += 3.0;
    }

    // Check if wall forces opponent to take longer path
    if (_forcesLongerPath(wall, gameState)) {
      score += 2.0;
    }

    return score;
  }

  static bool _createsBottleneck(Wall wall, GameState gameState) {
    // Check if wall creates a narrow passage that can be exploited later
    final surroundingWalls = gameState.walls
        .where(
          (w) =>
              (w.position.row - wall.position.row).abs() <= 1 &&
              (w.position.col - wall.position.col).abs() <= 1,
        )
        .length;

    return surroundingWalls >= 2;
  }

  static bool _controlsCenter(Wall wall, GameState gameState) {
    final center = GameConstants.boardSize / 2;
    final distanceFromCenter = math.sqrt(
      math.pow(wall.position.row - center, 2) +
          math.pow(wall.position.col - center, 2),
    );

    return distanceFromCenter <= 2;
  }

  static bool _createsMultiplePaths(Wall wall, GameState gameState) {
    // Check if wall placement creates alternative paths for self
    final tempGameState = _createTempGameStateWithWall(gameState, wall);
    final selfPos = gameState.currentPlayerId == 1
        ? gameState.players[0].position
        : gameState.players[1].position;
    final selfGoal = gameState.currentPlayerId == 1
        ? gameState.players[0].goalRow
        : gameState.players[1].goalRow;

    final paths = _findMultiplePaths(tempGameState, selfPos, selfGoal);
    return paths.length > 1;
  }

  static List<List<Position>> _findMultiplePaths(
    GameState gameState,
    Position start,
    int targetRow,
  ) {
    final paths = <List<Position>>[];
    final visited = <Position>{};

    void dfs(Position current, List<Position> currentPath) {
      if (current.row == targetRow) {
        paths.add(List.from(currentPath));
        return;
      }

      visited.add(current);
      final neighbors = gameState.getValidMoves(current);

      for (final neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          currentPath.add(neighbor);
          dfs(neighbor, currentPath);
          currentPath.removeLast();
        }
      }

      visited.remove(current);
    }

    dfs(start, [start]);
    return paths;
  }

  static bool _blocksShortestPath(Wall wall, GameState gameState) {
    final opponentId = gameState.currentPlayerId == 1 ? 2 : 1;
    final opponentPos = opponentId == 1
        ? gameState.players[0].position
        : gameState.players[1].position;
    final opponentGoal = opponentId == 1
        ? gameState.players[0].goalRow
        : gameState.players[1].goalRow;

    final originalPath = findShortestPath(gameState, opponentPos, opponentGoal);
    final tempGameState = _createTempGameStateWithWall(gameState, wall);
    final newPath = findShortestPath(tempGameState, opponentPos, opponentGoal);

    return newPath != null &&
        originalPath != null &&
        newPath.length > originalPath.length;
  }

  static bool _forcesLongerPath(Wall wall, GameState gameState) {
    final opponentId = gameState.currentPlayerId == 1 ? 2 : 1;
    final opponentPos = opponentId == 1
        ? gameState.players[0].position
        : gameState.players[1].position;
    final opponentGoal = opponentId == 1
        ? gameState.players[0].goalRow
        : gameState.players[1].goalRow;

    final originalPath = findShortestPath(gameState, opponentPos, opponentGoal);
    final tempGameState = _createTempGameStateWithWall(gameState, wall);
    final newPath = findShortestPath(tempGameState, opponentPos, opponentGoal);

    return newPath != null &&
        originalPath != null &&
        newPath.length >= originalPath.length + 2;
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
      players: List.from(original.players),
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

  static double _calculatePathBlockingScore(Wall wall, GameState gameState) {
    double score = 0;

    // Check how many potential paths this wall blocks
    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        if (wall.orientation == WallOrientation.horizontal) {
          if (wall.position.row == row &&
              wall.position.col <= col &&
              wall.position.col + 1 >= col) {
            score += 0.5;
          }
        } else {
          if (wall.position.col == col &&
              wall.position.row <= row &&
              wall.position.row + 1 >= row) {
            score += 0.5;
          }
        }
      }
    }

    return score;
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
