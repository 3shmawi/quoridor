import '../constants.dart';

class Player {
  final int id; // 1 to 4
  Position position;
  int wallsRemaining;

  /// The side of the board this player is racing to reach.
  final GoalEdge goal;

  final String name;
  final bool isAI;

  Player({
    required this.id,
    required this.position,
    this.wallsRemaining = GameConstants.maxWallsPerPlayer,
    required this.goal,
    required this.name,
    this.isAI = false,
  });

  bool get hasWallsRemaining => wallsRemaining > 0;

  bool get hasReachedGoal => goal.contains(position);

  /// Whether [position] would win the game for this player.
  bool isGoal(Position position) => goal.contains(position);

  /// The goal as a row, for the two seats that have one.
  ///
  /// Kept because a row reads more naturally than an edge wherever only the
  /// original two players can be involved; seats three and four cross the
  /// board sideways and have no goal row, so this is null for them.
  int? get goalRow {
    switch (goal) {
      case GoalEdge.top:
        return 0;
      case GoalEdge.bottom:
        return GameConstants.boardSize - 1;
      case GoalEdge.left:
      case GoalEdge.right:
        return null;
    }
  }

  void moveTo(Position newPosition) {
    position = newPosition;
  }

  void useWall() {
    if (wallsRemaining > 0) {
      wallsRemaining--;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'position': position.toJson(),
    'wallsRemaining': wallsRemaining,
    'goal': goal.name,
    // Still written so a new build's save can be opened by an old one.
    if (goalRow != null) 'goalRow': goalRow,
    'name': name,
    'isAI': isAI,
  };

  static Player fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as int,
    position: Position.fromJson(json['position']),
    wallsRemaining: json['wallsRemaining'] as int,
    goal: _goalFrom(json),
    name: json['name'] as String,
    isAI: json['isAI'] as bool,
  );

  /// Reads the goal, falling back to the row that games saved before seats
  /// three and four existed carry instead.
  static GoalEdge _goalFrom(Map<String, dynamic> json) {
    final name = json['goal'] as String?;
    if (name != null) {
      for (final edge in GoalEdge.values) {
        if (edge.name == name) return edge;
      }
    }

    final row = json['goalRow'] as int?;
    if (row != null) return row == 0 ? GoalEdge.top : GoalEdge.bottom;

    return GoalEdge.goalOfSeat(json['id'] as int);
  }

  Player copyWith({
    Position? position,
    int? wallsRemaining,
    String? name,
    bool? isAI,
  }) => Player(
    id: id,
    position: position ?? this.position,
    wallsRemaining: wallsRemaining ?? this.wallsRemaining,
    goal: goal,
    name: name ?? this.name,
    isAI: isAI ?? this.isAI,
  );
}

// Helper function to create default players
class PlayerFactory {
  static Player createPlayer1({String name = 'Player 1', bool isAI = false}) =>
      seat(1, name: name, isAI: isAI);

  static Player createPlayer2({String name = 'Player 2', bool isAI = true}) =>
      seat(2, name: name, isAI: isAI);

  /// Where each seat starts, which way it faces, and how many walls it holds.
  static Player seat(
    int id, {
    String? name,
    bool isAI = false,
    int playerCount = 2,
  }) => Player(
    id: id,
    position: startOfSeat(id),
    goal: GoalEdge.goalOfSeat(id),
    wallsRemaining: GameConstants.wallsFor(playerCount),
    name: name ?? 'Player $id',
    isAI: isAI,
  );

  static Position startOfSeat(int seat) {
    switch (seat) {
      case 1:
        return GameConstants.player1Start;
      case 2:
        return GameConstants.player2Start;
      case 3:
        return GameConstants.player3Start;
      default:
        return GameConstants.player4Start;
    }
  }
}
