import 'dart:math';

import '../../constants.dart';
import '../../models/game_state.dart';
import '../../models/player.dart';
import '../game_service.dart';

/// Strength of the computer opponent.
enum EngineStrength {
  /// Sees one move ahead and plays loosely. Beatable on purpose.
  easy,

  /// Sees the reply. Blocks when blocking is worth it.
  medium,

  /// Searches deep enough to set up walls a move in advance.
  hard,
}

/// A search-based Quoridor opponent.
///
/// The previous AI chose the move that reduced the difference between its row
/// and its goal row. That ignores walls entirely, so a wall across its route
/// left it with no move that reduced the difference, and it shuffled between
/// two squares forever. Distance here is the real shortest path with the walls
/// on the board, so going *around* a wall is correctly seen as progress, and
/// the engine searches replies rather than grabbing the locally best square.
class QuoridorEngine {
  QuoridorEngine._();

  /// Score returned for a won position. Large enough to dominate any
  /// distance difference, small enough to stay clear of overflow.
  static const int _winScore = 100000;

  /// A distance advantage is what the game is actually about, so it outweighs
  /// holding walls in reserve.
  static const int _distanceWeight = 10;
  static const int _wallWeight = 1;

  /// Upper bound on nodes per move, so a turn never hangs the UI.
  static const int _nodeBudget = 30000;

  static int _depthFor(EngineStrength strength) {
    switch (strength) {
      case EngineStrength.easy:
        return 1;
      case EngineStrength.medium:
        return 2;
      case EngineStrength.hard:
        return 3;
    }
  }

  /// Picks a move for the player to move, or null if there is none.
  static GameMove? bestMove(
    GameState state,
    EngineStrength strength, {
    Random? random,
  }) {
    if (state.isGameOver) return null;

    final me = state.currentPlayerId;
    final moves = _generateMoves(state);
    if (moves.isEmpty) return null;

    final rng = random ?? Random();

    // Easy plays a decent move rather than the best one, so it is beatable
    // without being silly: it still uses real distances, it just does not
    // always pick the top choice.
    if (strength == EngineStrength.easy && rng.nextDouble() < 0.35) {
      final pawnMoves = moves
          .where((m) => m.type == MoveType.pawnMove)
          .toList();
      if (pawnMoves.isNotEmpty) {
        return pawnMoves[rng.nextInt(pawnMoves.length)];
      }
    }

    final budget = _NodeBudget(_nodeBudget);
    final depth = _depthFor(strength);

    // Where this pawn came from, used only to break ties away from stepping
    // straight back — the shuffle the old AI was famous for.
    final previous = _previousPosition(state, me);

    GameMove? best;
    var bestScore = -_winScore * 2;

    for (final move in moves) {
      final child = applyMove(state, move);
      final score = -_negamax(
        child,
        depth - 1,
        -_winScore * 2,
        -bestScore,
        3 - me,
        budget,
      );

      final adjusted = _tieBreak(score, move, previous);

      if (best == null || adjusted > bestScore) {
        bestScore = adjusted;
        best = move;
      }
    }

    return best ?? moves.first;
  }

  /// Nudges a move that walks straight back where it came from below an
  /// otherwise equal alternative.
  static int _tieBreak(int score, GameMove move, Position? previous) {
    if (previous == null) return score;
    if (move.type != MoveType.pawnMove) return score;
    return move.newPosition == previous ? score - 1 : score;
  }

  static Position? _previousPosition(GameState state, int playerId) {
    for (var i = state.moveHistory.length - 1; i >= 0; i--) {
      final move = state.moveHistory[i];
      if (move.playerId == playerId && move.type == MoveType.pawnMove) {
        // The move that put the pawn where it is; the square before that is
        // the one it would be stepping back to.
        for (var j = i - 1; j >= 0; j--) {
          final earlier = state.moveHistory[j];
          if (earlier.playerId == playerId &&
              earlier.type == MoveType.pawnMove) {
            return earlier.newPosition;
          }
        }
        return null;
      }
    }
    return null;
  }

  static int _negamax(
    GameState state,
    int depth,
    int alpha,
    int beta,
    int perspective,
    _NodeBudget budget,
  ) {
    budget.spend();

    if (state.isGameOver || depth <= 0 || budget.exhausted) {
      return _evaluate(state, perspective);
    }

    final moves = _generateMoves(state);
    if (moves.isEmpty) return _evaluate(state, perspective);

    var value = -_winScore * 2;

    for (final move in moves) {
      final child = applyMove(state, move);
      final score = -_negamax(
        child,
        depth - 1,
        -beta,
        -alpha,
        3 - perspective,
        budget,
      );

      if (score > value) value = score;
      if (value > alpha) alpha = value;
      if (alpha >= beta) break; // The opponent would avoid this line.
    }

    return value;
  }

  /// Scores [state] from [perspective]'s point of view.
  ///
  /// Everything here is in units of "steps I am ahead": how much shorter my
  /// route is than theirs, plus a small credit for walls still in hand, since
  /// a wall unspent is a threat unspent.
  static int _evaluate(GameState state, int perspective) {
    final me = perspective == 1 ? state.player1 : state.player2;
    final them = perspective == 1 ? state.player2 : state.player1;

    if (me.hasReachedGoal) return _winScore;
    if (them.hasReachedGoal) return -_winScore;

    final myDistance = distanceToGoal(state, me);
    final theirDistance = distanceToGoal(state, them);

    // A sealed-off player cannot happen under the rules, but a defensive
    // value keeps the search total rather than throwing mid-line.
    if (myDistance == null) return -_winScore;
    if (theirDistance == null) return _winScore;

    return (theirDistance - myDistance) * _distanceWeight +
        (me.wallsRemaining - them.wallsRemaining) * _wallWeight;
  }

  /// Length of the shortest route from [player] to their goal row, in steps,
  /// or null when no route exists.
  ///
  /// A plain breadth-first sweep of the 81 squares. Opponent-jumping is left
  /// out on purpose: it changes a route by at most a step and would cost far
  /// more than it is worth inside a search.
  static int? distanceToGoal(GameState state, Player player) {
    const size = GameConstants.boardSize;
    final visited = List.generate(size, (_) => List<bool>.filled(size, false));
    final queue = <Position>[player.position];
    visited[player.position.row][player.position.col] = true;

    var steps = 0;
    while (queue.isNotEmpty) {
      final levelSize = queue.length;

      for (var i = 0; i < levelSize; i++) {
        final current = queue.removeAt(0);
        if (current.row == player.goalRow) return steps;

        for (final next in _neighbours(state, current)) {
          if (visited[next.row][next.col]) continue;
          visited[next.row][next.col] = true;
          queue.add(next);
        }
      }

      steps++;
    }

    return null;
  }

  static Iterable<Position> _neighbours(GameState state, Position from) sync* {
    const size = GameConstants.boardSize;
    const deltas = [
      Position(-1, 0),
      Position(1, 0),
      Position(0, -1),
      Position(0, 1),
    ];

    for (final delta in deltas) {
      final to = Position(from.row + delta.row, from.col + delta.col);
      if (to.row < 0 || to.row >= size || to.col < 0 || to.col >= size) {
        continue;
      }
      if (state.isWallBlocking(from, to)) continue;
      yield to;
    }
  }

  /// Every move worth considering from [state].
  ///
  /// Pawn moves are cheap and few. Walls are not: there are over a hundred
  /// legal ones and checking each costs a path search, which is why only walls
  /// that actually interfere with the opponent's current best route are
  /// considered. A wall that does not lengthen their route is not a move worth
  /// searching.
  static List<GameMove> _generateMoves(GameState state) {
    final player = state.currentPlayer;
    final moves = <GameMove>[];

    for (final position in state.getValidMoves(player.position)) {
      moves.add(GameMove.pawnMove(position, player.id));
    }

    if (player.hasWallsRemaining) {
      for (final wall in _wallCandidates(state)) {
        moves.add(GameMove.wallPlace(wall, player.id));
      }
    }

    return moves;
  }

  /// Walls that would interrupt a step on the opponent's shortest route.
  static List<Wall> _wallCandidates(GameState state) {
    final opponent = state.otherPlayer;
    final route = _shortestRoute(state, opponent);
    if (route == null) return const [];

    final seen = <Wall>{};
    final candidates = <Wall>[];

    for (var i = 0; i + 1 < route.length; i++) {
      for (final wall in _wallsBlocking(route[i], route[i + 1])) {
        if (!seen.add(wall)) continue;
        if (GameService.validateWallPlacement(
          state,
          state.currentPlayer,
          wall,
        ).isValid) {
          candidates.add(wall);
        }
      }
    }

    return candidates;
  }

  /// The two walls that can block the step from [from] to [to].
  static List<Wall> _wallsBlocking(Position from, Position to) {
    if (from.col == to.col) {
      // Vertical step: a horizontal wall in the gap they cross.
      final row = from.row > to.row ? from.row : to.row;
      return [
        Wall(Position(row, from.col), WallOrientation.horizontal),
        Wall(Position(row, from.col - 1), WallOrientation.horizontal),
      ];
    }

    // Horizontal step: a vertical wall in the gap they cross.
    final col = from.col > to.col ? from.col : to.col;
    return [
      Wall(Position(from.row, col), WallOrientation.vertical),
      Wall(Position(from.row - 1, col), WallOrientation.vertical),
    ];
  }

  /// The squares of a shortest route for [player], start included.
  static List<Position>? _shortestRoute(GameState state, Player player) {
    const size = GameConstants.boardSize;
    final cameFrom = <Position, Position?>{player.position: null};
    final queue = <Position>[player.position];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      if (current.row == player.goalRow) {
        final route = <Position>[];
        Position? step = current;
        while (step != null) {
          route.insert(0, step);
          step = cameFrom[step];
        }
        return route;
      }

      for (final next in _neighbours(state, current)) {
        if (cameFrom.containsKey(next)) continue;
        cameFrom[next] = current;
        queue.add(next);
      }
    }

    assert(size == GameConstants.boardSize);
    return null;
  }

  /// Applies [move] to a copy of [state], without re-validating it.
  ///
  /// Search generates only legal moves, so re-running validation — which costs
  /// two path searches per wall — would double the price of every node.
  static GameState applyMove(GameState state, GameMove move) {
    final next = GameState(
      gameId: state.gameId,
      player1: state.player1.copyWith(),
      player2: state.player2.copyWith(),
      walls: List<Wall>.of(state.walls),
      currentPlayerId: state.currentPlayerId,
      status: state.status,
      createdAt: state.createdAt,
      updatedAt: state.updatedAt,
      moveHistory: <GameMove>[],
    );

    if (move.type == MoveType.pawnMove) {
      next.movePawn(move.newPosition!);
    } else {
      next.addWall(move.wall!);
    }

    next.checkWinCondition();
    if (!next.isGameOver) next.switchTurn();
    return next;
  }
}

/// Counts nodes so a search stops before it becomes a pause the player notices.
class _NodeBudget {
  _NodeBudget(this.limit);

  final int limit;
  int used = 0;

  bool get exhausted => used >= limit;

  void spend() => used++;
}
