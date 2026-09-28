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
  static const int _nodeBudget = 200000;

  /// Wall-clock cap per move, per strength.
  ///
  /// Node counts are a poor proxy for time once the board fills up and each
  /// node costs a path search, so the search also stops on the clock. This is
  /// what separates medium from hard: both look four moves ahead, but on a
  /// crowded board — the only place the difference shows — medium runs out of
  /// time and settles for what it has seen, while hard finishes the line.
  ///
  /// Searching deeper than four was tried and plays *worse*: the budget cuts
  /// a depth-six search off mid-tree, leaving the root comparing scores taken
  /// at different depths, which is how the engine talks itself into a step
  /// backwards.
  static Duration _timeBudgetFor(EngineStrength strength) {
    switch (strength) {
      case EngineStrength.easy:
        return const Duration(milliseconds: 150);
      case EngineStrength.medium:
        return const Duration(milliseconds: 400);
      case EngineStrength.hard:
        return const Duration(milliseconds: 900);
    }
  }

  /// How many of its own recent squares the engine will avoid returning to.
  ///
  /// One is not enough: a pawn can circle three or four squares without ever
  /// stepping straight back, which is what "it repeats itself" looks like.
  static const int _repetitionWindow = 6;

  static int _depthFor(EngineStrength strength) {
    switch (strength) {
      case EngineStrength.easy:
        return 2;
      case EngineStrength.medium:
        return 4;
      case EngineStrength.hard:
        return 4;
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

    final budget = _SearchBudget(_nodeBudget, _timeBudgetFor(strength));
    final target = _depthFor(strength);

    // Where this pawn has been lately, so the search can prefer not to
    // revisit it when nothing else separates the moves.
    final recent = _recentPositions(state, me);

    // Deepen one ply at a time, keeping only depths that finished.
    //
    // Searching straight to the target depth was what made the engine look
    // silly: when the budget ran out halfway through the root's move list,
    // the moves searched before the cutoff carried real scores and the rest
    // carried whatever the truncated search happened to return, so the engine
    // compared depths against each other and picked a step backwards. Falling
    // back to the last *complete* depth means a cut-off search is merely
    // shallower, never incoherent — and the ordering from that depth makes
    // the next one prune far harder, so the depth is usually reached anyway.
    var scored = <({GameMove move, int score})>[];
    var order = moves;

    for (var depth = 1; depth <= target; depth++) {
      final pass = <({GameMove move, int score})>[];
      var alpha = -_winScore * 2;

      for (final move in order) {
        final child = applyMove(state, move);
        final raw = -_negamax(
          child,
          depth - 1,
          -_winScore * 2,
          -alpha,
          3 - me,
          budget,
        );

        final score = _withRepetitionPenalty(raw, move, recent);
        if (score > alpha) alpha = score;
        pass.add((move: move, score: score));

        if (budget.exhausted) break;
      }

      // A pass that did not see every root move cannot be compared with one
      // that did, so it is discarded rather than mixed in.
      if (pass.length < order.length) break;

      pass.sort((a, b) => b.score.compareTo(a.score));
      scored = pass;
      order = [for (final entry in pass) entry.move];

      if (budget.exhausted) break;
    }

    if (scored.isEmpty) return moves.first;

    // Easy is meant to be beatable, so it takes one of the better moves
    // rather than the best one. But "one of the top three" is not the same as
    // "nearly as good": with only two or three sensible moves on the board,
    // the third is often a step backwards, and an opponent that wanders is
    // read as broken rather than as easy. So the pool is bounded by score —
    // moves that cost less than a single step of progress — and is empty when
    // there is only one reasonable move, which is exactly when it matters.
    if (strength == EngineStrength.easy && scored.length > 1) {
      final best = scored.first.score;
      final pool = scored
          .where((entry) => best - entry.score < _distanceWeight)
          .where((entry) => !_revisits(entry.move, recent))
          .take(3)
          .toList();
      if (pool.isNotEmpty) return pool[rng.nextInt(pool.length)].move;
    }

    return scored.first.move;
  }

  /// A single step along the shortest route to the player's goal.
  ///
  /// This is the move played when somebody's turn times out, and it is
  /// deliberately not [bestMove]: the strongest reply is often a wall, and
  /// spending one of the ten a player holds because they looked at their
  /// phone's notification shade is a real cost they did not choose. Stepping
  /// forward spends nothing and is never a blunder.
  static GameMove? stepTowardsGoal(GameState state) {
    final player = state.currentPlayer;

    GameMove? best;
    int? bestDistance;

    for (final position in state.getValidMoves(player.position)) {
      final move = GameMove.pawnMove(position, player.id);
      final after = applyMove(state, move);
      final moved = player.id == 1 ? after.player1 : after.player2;

      if (moved.hasReachedGoal) return move;

      final distance = distanceToGoal(after, moved);
      if (distance == null) continue;
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
        best = move;
      }
    }

    return best;
  }

  /// The squares this player has occupied recently, most recent first.
  static List<Position> _recentPositions(GameState state, int playerId) {
    final positions = <Position>[];
    for (var i = state.moveHistory.length - 1; i >= 0; i--) {
      final move = state.moveHistory[i];
      if (move.playerId != playerId || move.type != MoveType.pawnMove) continue;
      final at = move.newPosition;
      if (at != null) positions.add(at);
      if (positions.length >= _repetitionWindow) break;
    }
    return positions;
  }

  /// Whether [move] steps back onto a square this pawn has just left.
  static bool _revisits(GameMove move, List<Position> recent) =>
      move.type == MoveType.pawnMove && recent.contains(move.newPosition);

  /// What a revisit costs, in the same units as distance.
  ///
  /// A penalty smaller than one step cannot stop a shuttle, because that is
  /// exactly the shape of one: from A the search rates B a step better, and
  /// from B it rates A a step better, so a sub-step penalty loses to the
  /// illusion every time and the pawn shuttles until the game is abandoned.
  /// Just over two steps breaks that while still letting through a retreat
  /// that genuinely opens a shorter route.
  static const int _repetitionCost = _distanceWeight * 2 + 4;

  /// Discourages stepping back onto a square this pawn has just left.
  static int _withRepetitionPenalty(
    int score,
    GameMove move,
    List<Position> recent,
  ) {
    if (move.type != MoveType.pawnMove) return score;
    final index = recent.indexOf(move.newPosition!);
    if (index < 0) return score;

    // The more recently it was there, the worse going back looks.
    final recency = _repetitionWindow - index;
    return score - (_repetitionCost * recency) ~/ _repetitionWindow;
  }

  static int _negamax(
    GameState state,
    int depth,
    int alpha,
    int beta,
    int perspective,
    _SearchBudget budget,
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

/// Stops a search before it becomes a pause the player notices.
///
/// Both limits matter: nodes bound a wide shallow search, and the clock bounds
/// a deep one on a crowded board where every node costs a path search.
class _SearchBudget {
  _SearchBudget(this.nodeLimit, Duration timeLimit)
    : _deadline = DateTime.now().add(timeLimit);

  final int nodeLimit;
  final DateTime _deadline;

  int used = 0;
  bool _outOfTime = false;

  bool get exhausted => _outOfTime || used >= nodeLimit;

  void spend() {
    used++;
    // Checking the clock is not free, but checking it rarely lets the search
    // overshoot its budget by more than the budget itself.
    if (used % 128 == 0 && DateTime.now().isAfter(_deadline)) {
      _outOfTime = true;
    }
  }
}
