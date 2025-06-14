import '../core/constants.dart';

class Player {
  final int id; // 1 or 2
  Position position;
  int wallsRemaining;
  final int goalRow;
  final String name;
  final int playerColor;
  bool isAI;

  Player({
    required this.id,
    required this.position,
    required this.wallsRemaining,
    required this.goalRow,
    required this.name,
    required this.playerColor,
    this.isAI = false,
  });

  bool get hasWallsRemaining => wallsRemaining > 0;

  bool get hasReachedGoal => switch (id) {
    1 => position.row == goalRow,
    2 => position.row == goalRow,
    3 => position.col == goalRow,
    4 => position.col == goalRow,
    _ => false,
  };

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
    playerColor: json['playerColor'] as int,
    isAI: json['isAI'] as bool,
  );

  Player copyWith({
    Position? position,
    int? wallsRemaining,
    String? name,
    bool? isAI,
    int? playerColor,
  }) => Player(
    id: id,
    position: position ?? this.position,
    wallsRemaining: wallsRemaining ?? this.wallsRemaining,
    goalRow: goalRow,
    name: name ?? this.name,
    playerColor: playerColor ?? this.playerColor,
    isAI: isAI ?? this.isAI,
  );
}

// Helper function to create default players
class PlayerFactory {
  static int playerCount = GameConstants.playersStartPositions.length;

  static Player createPlayer1({String name = 'Player 1'}) => Player(
    id: 1,
    position: GameConstants.playersStartPositions[0],
    goalRow: GameConstants.player1Goal,
    name: name,
    playerColor: GameConstants.player1Color,
    wallsRemaining: playerCount == 2
        ? 10
        : playerCount == 3
        ? 7
        : 5,
  );

  static Player createPlayer2({String name = 'Player 2', bool isAI = true}) =>
      Player(
        id: 2,
        position: GameConstants.playersStartPositions[1],
        goalRow: GameConstants.player2Goal,
        name: name,
        isAI: isAI,
        playerColor: GameConstants.player2Color,
        wallsRemaining: playerCount == 2
            ? 10
            : playerCount == 3
            ? 7
            : 5,
      );

  static Player createPlayer3({String name = 'Player 3'}) => Player(
    id: 3,
    position: GameConstants.playersStartPositions[2],
    goalRow: GameConstants.player2Goal,
    name: name,
    playerColor: GameConstants.player3Color,
    wallsRemaining: playerCount == 2
        ? 10
        : playerCount == 3
        ? 7
        : 5,
  );

  static Player createPlayer4({String name = 'Player 4'}) => Player(
    id: 4,
    position: GameConstants.playersStartPositions[3],
    goalRow: GameConstants.player1Goal,
    name: name,
    playerColor: GameConstants.player4Color,
    wallsRemaining: playerCount == 2
        ? 10
        : playerCount == 3
        ? 7
        : 5,
  );
}
