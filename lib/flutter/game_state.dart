import '../constants.dart';
import 'player.dart';

class GameState {
  final String gameId;
  final Player player1;
  final Player player2;
  final List<Wall> walls;
  int currentPlayerId;
  GameStatus status;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<GameMove> moveHistory;

  GameState({
    required this.gameId,
    required this.player1,
    required this.player2,
    List<Wall>? walls,
    this.currentPlayerId = 1,
    this.status = GameStatus.playing,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GameMove>? moveHistory,
  }) : walls = walls ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        moveHistory = moveHistory ?? [];

  Player get currentPlayer => currentPlayerId == 1 ? player1 : player2;
  Player get otherPlayer => currentPlayerId == 1 ? player2 : player1;

  GameStatus get gameStatus => status;
  bool get isGameOver => status != GameStatus.playing;

  String? get winner {
    switch (status) {
      case GameStatus.player1Won:
        return player1.name;
      case GameStatus.player2Won:
        return player2.name;
      default:
        return null;
    }
  }

  void switchTurn() {
    currentPlayerId = currentPlayerId == 1 ? 2 : 1;
    updatedAt = DateTime.now();
  }

  void addWall(Wall wall) {
    walls.add(wall);
    currentPlayer.useWall();
    updatedAt = DateTime.now();
  }

  void movePawn(Position newPosition) {
    currentPlayer.moveTo(newPosition);
    updatedAt = DateTime.now();
  }

  void checkWinCondition() {
    if (player1.hasReachedGoal) {
      status = GameStatus.player1Won;
    } else if (player2.hasReachedGoal) {
      status = GameStatus.player2Won;
    }
    updatedAt = DateTime.now();
  }

  void addMoveToHistory(GameMove move) {
    moveHistory.add(move);
    updatedAt = DateTime.now();
  }

  bool isPositionOccupied(Position position) {
    return player1.position == position || player2.position == position;
  }

  bool isWallBlocking(Position from, Position to) {
    // Check if there's a wall blocking movement between two adjacent positions
    for (final wall in walls) {
      if (_wallBlocksMovement(wall, from, to)) {
        return true;
      }
    }
    return false;
  }

  bool _wallBlocksMovement(Wall wall, Position from, Position to) {
    final wallRow = wall.position.row;
    final wallCol = wall.position.col;

    if (wall.orientation == WallOrientation.horizontal) {
      // Horizontal wall blocks vertical movement
      if (from.col == to.col) {
        final minRow = from.row < to.row ? from.row : to.row;
        final maxRow = from.row < to.row ? to.row : from.row;

        return wallRow == maxRow &&
            wallCol <= from.col &&
            wallCol + 1 >= from.col;
      }
    } else {
      // Vertical wall blocks horizontal movement
      if (from.row == to.row) {
        final minCol = from.col < to.col ? from.col : to.col;
        final maxCol = from.col < to.col ? to.col : from.col;

        return wallCol == maxCol &&
            wallRow <= from.row &&
            wallRow + 1 >= from.row;
      }
    }

    return false;
  }

  List<Position> getValidMoves(Position position) {
    final validMoves = <Position>[];
    final directions = [
      Position(-1, 0), // Up
      Position(1, 0),  // Down
      Position(0, -1), // Left
      Position(0, 1),  // Right
    ];

    for (final direction in directions) {
      final newPos = Position(
        position.row + direction.row,
        position.col + direction.col,
      );

      // Check bounds
      if (newPos.row < 0 || newPos.row >= GameConstants.boardSize ||
          newPos.col < 0 || newPos.col >= GameConstants.boardSize) {
        continue;
      }

      // Check wall blocking
      if (isWallBlocking(position, newPos)) {
        continue;
      }

      // Check if position is occupied
      if (isPositionOccupied(newPos)) {
        // Check for jump moves
        final jumpPos = Position(
          newPos.row + direction.row,
          newPos.col + direction.col,
        );

        // Jump over opponent if possible
        if (jumpPos.row >= 0 && jumpPos.row < GameConstants.boardSize &&
            jumpPos.col >= 0 && jumpPos.col < GameConstants.boardSize &&
            !isWallBlocking(newPos, jumpPos) &&
            !isPositionOccupied(jumpPos)) {
          validMoves.add(jumpPos);
        } else {
          // Diagonal jump if blocked behind
          final diagonalMoves = [
            Position(newPos.row - 1, newPos.col), // Up from opponent
            Position(newPos.row + 1, newPos.col), // Down from opponent
            Position(newPos.row, newPos.col - 1), // Left from opponent
            Position(newPos.row, newPos.col + 1), // Right from opponent
          ];

          for (final diagPos in diagonalMoves) {
            if (diagPos.row >= 0 && diagPos.row < GameConstants.boardSize &&
                diagPos.col >= 0 && diagPos.col < GameConstants.boardSize &&
                !isWallBlocking(newPos, diagPos) &&
                !isPositionOccupied(diagPos)) {
              validMoves.add(diagPos);
            }
          }
        }
      } else {
        validMoves.add(newPos);
      }
    }

    return validMoves;
  }

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'player1': player1.toJson(),
    'player2': player2.toJson(),
    'walls': walls.map((w) => w.toJson()).toList(),
    'currentPlayerId': currentPlayerId,
    'status': status.index,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'moveHistory': moveHistory.map((m) => m.toJson()).toList(),
  };

  static GameState fromJson(Map<String, dynamic> json) => GameState(
    gameId: json['gameId'] as String,
    player1: Player.fromJson(json['player1']),
    player2: Player.fromJson(json['player2']),
    walls: (json['walls'] as List).map((w) => Wall.fromJson(w)).toList(),
    currentPlayerId: json['currentPlayerId'] as int,
    status: GameStatus.values[json['status'] as int],
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    moveHistory: (json['moveHistory'] as List)
        .map((m) => GameMove.fromJson(m))
        .toList(),
  );

  GameState copyWith({
    String? gameId,
    Player? player1,
    Player? player2,
    List<Wall>? walls,
    int? currentPlayerId,
    GameStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GameMove>? moveHistory,
  }) {
    return GameState(
      gameId: gameId ?? this.gameId,
      player1: player1 ?? this.player1,
      player2: player2 ?? this.player2,
      walls: walls ?? List<Wall>.from(this.walls),
      currentPlayerId: currentPlayerId ?? this.currentPlayerId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      moveHistory: moveHistory ?? List<GameMove>.from(this.moveHistory),
    );
  }
}

// Factory for creating new games
class GameStateFactory {
  static GameState createNewGame({
    String? gameId,
    String player1Name = 'Player 1',
    String player2Name = 'AI',
    bool player2IsAI = true,
  }) {
    gameId ??= 'game_${DateTime.now().millisecondsSinceEpoch}';

    return GameState(
      gameId: gameId,
      player1: PlayerFactory.createPlayer1(name: player1Name),
      player2: PlayerFactory.createPlayer2(name: player2Name, isAI: player2IsAI),
    );
  }
}