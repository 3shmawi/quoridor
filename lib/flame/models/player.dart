import '../constants.dart';

class Player {
  final int id; // 1, 2, 3, or 4
  Position position;
  int wallsRemaining;
  final int goalRow;
  final int goalCol;
  final String name;
  bool isAI;

  Player({
    required this.id,
    required this.position,
    this.wallsRemaining = GameConstants.maxWallsPerPlayer,
    required this.goalRow,
    required this.goalCol,
    required this.name,
    this.isAI = false,
  });

  bool get hasWallsRemaining => wallsRemaining > 0;

  bool get hasReachedGoal {
    // For 2-player mode: check if reached the opposite row
    if (id <= 2) {
      return position.row == goalRow;
    }
    // For 4-player mode: check if reached the opposite side
    else {
      // Player 3 (right) needs to reach left column (0)
      if (id == 3) {
        return position.col == 0;
      }
      // Player 4 (left) needs to reach right column (8)
      else if (id == 4) {
        return position.col == 8;
      }
    }
    return false;
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
    'goalRow': goalRow,
    'goalCol': goalCol,
    'name': name,
    'isAI': isAI,
  };

  static Player fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as int,
    position: Position.fromJson(json['position']),
    wallsRemaining: json['wallsRemaining'] as int,
    goalRow: json['goalRow'] as int,
    goalCol: json['goalCol'] as int,
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
    goalCol: goalCol,
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
        goalCol: 4,
        name: name,
        isAI: isAI,
      );

  static Player createPlayer2({String name = 'Player 2', bool isAI = true}) =>
      Player(
        id: 2,
        position: GameConstants.player2Start,
        goalRow: GameConstants.player2Goal,
        goalCol: 4,
        name: name,
        isAI: isAI,
      );

  static Player createPlayer3({String name = 'Player 3', bool isAI = true}) =>
      Player(
        id: 3,
        position: GameConstants.player3Start,
        goalRow: GameConstants.player3Goal,
        goalCol: GameConstants.player3GoalCol,
        name: name,
        isAI: isAI,
      );

  static Player createPlayer4({String name = 'Player 4', bool isAI = true}) =>
      Player(
        id: 4,
        position: GameConstants.player4Start,
        goalRow: GameConstants.player4Goal,
        goalCol: GameConstants.player4GoalCol,
        name: name,
        isAI: isAI,
      );

  // Helper method to create players based on player count
  static List<Player> createPlayersForCount(
    int playerCount, {
    List<String>? playerNames,
    List<bool>? aiPlayers,
  }) {
    final players = <Player>[];
    final names =
        playerNames ?? ['Player 1', 'Player 2', 'Player 3', 'Player 4'];
    final ai = [false, false, false, false];
    final wallCount = GameConstants.getWallsForPlayerCount(playerCount);

    for (int i = 0; i < playerCount; i++) {
      Player player;
      switch (i + 1) {
        case 1:
          player = createPlayer1(name: names[i], isAI: ai[i]);
          break;
        case 2:
          player = createPlayer2(name: names[i], isAI: ai[i]);
          break;
        case 3:
          player = createPlayer3(name: names[i], isAI: ai[i]);
          break;
        case 4:
          player = createPlayer4(name: names[i], isAI: ai[i]);
          break;
        default:
          continue;
      }
      player.wallsRemaining = wallCount;
      players.add(player);
    }
    return players;
  }
}
