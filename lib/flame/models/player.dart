import '../constants.dart';

class Player {
  final int id; // 1 or 2
  Position position;
  int wallsRemaining;
  final int goalRow;
  final String name;
  bool isAI;

  Player({
    required this.id,
    required this.position,
    this.wallsRemaining = GameConstants.maxWallsPerPlayer,
    required this.goalRow,
    required this.name,
    this.isAI = false,
  });

  bool get hasWallsRemaining => wallsRemaining > 0;

  bool get hasReachedGoal => position.row == goalRow;

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
    'goalRow': goalRow,
    'name': name,
    'isAI': isAI,
  };

  static Player fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as int,
    position: Position.fromJson(json['position']),
    wallsRemaining: json['wallsRemaining'] as int,
    goalRow: json['goalRow'] as int,
    name: json['name'] as String,
    isAI: json['isAI'] as bool,
  );

  Player copyWith({
    Position? position,
    int? wallsRemaining,
    String? name,
    bool? isAI,
  }) => Player(
    id: id,
    position: position ?? this.position,
    wallsRemaining: wallsRemaining ?? this.wallsRemaining,
    goalRow: goalRow,
    name: name ?? this.name,
    isAI: isAI ?? this.isAI,
  );
}

// Helper function to create default players
class PlayerFactory {
  static Player createPlayer1({String name = 'Player 1', bool isAI = false}) =>
      Player(
        id: 1,
        position: GameConstants.player1Start,
        goalRow: GameConstants.player1Goal,
        name: name,
        isAI: isAI,
      );

  static Player createPlayer2({String name = 'Player 2', bool isAI = true}) =>
      Player(
        id: 2,
        position: GameConstants.player2Start,
        goalRow: GameConstants.player2Goal,
        name: name,
        isAI: isAI,
      );
}
