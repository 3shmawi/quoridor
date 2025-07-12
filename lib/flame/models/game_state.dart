import 'package:quoridor/flame/services/ai_service.dart';

import '../../flame/constants.dart';
import 'player.dart';

class GameState {
  final String gameId;
  final List<Player> players;
  final List<Wall> walls;
  int currentPlayerId;
  GameStatus status;
  AIDifficulty aiDifficulty;
  final DateTime createdAt;
  DateTime updatedAt;
  final List<GameMove> moveHistory;
  bool showValidMoves;
  WallOrientation wallOrientation;
  WallRotationPhase wallRotationPhase;
  Wall? previewWall;

  GameState({
    required this.gameId,
    required this.players,
    List<Wall>? walls,
    this.currentPlayerId = 1,
    this.status = GameStatus.playing,
    this.aiDifficulty = AIDifficulty.medium,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.showValidMoves = true,
    List<GameMove>? moveHistory,
    this.wallOrientation = WallOrientation.horizontal,
    this.wallRotationPhase = WallRotationPhase.horizontalBottom,
    this.previewWall,
  }) : walls = walls ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       moveHistory = moveHistory ?? [];

  // Get player count
  int get playerCount => players.length;

  Player get currentPlayer =>
      players.firstWhere((p) => p.id == currentPlayerId);

  List<Player> get otherPlayers =>
      players.where((p) => p.id != currentPlayerId).toList();

  bool get isGameOver => status != GameStatus.playing;

  AIDifficulty get difficulty => aiDifficulty;

  set difficulty(AIDifficulty newDifficulty) {
    aiDifficulty = newDifficulty;
    updatedAt = DateTime.now();
  }

  void toggleShowValidMoves() {
    showValidMoves = !showValidMoves;
    updatedAt = DateTime.now();
  }

  WallOrientation get getWallOrientation => wallOrientation;

  set setWallOrientation(WallOrientation orientation) {
    wallOrientation = orientation;
    updatedAt = DateTime.now();
  }

  WallRotationPhase get getWallRotationPhase => wallRotationPhase;
  set setWallRotationPhase(WallRotationPhase phase) {
    wallRotationPhase = phase;
    updatedAt = DateTime.now();
  }

  Wall? get wallPreview => previewWall;

  set setWallPreview(Wall? wall) {
    previewWall = wall;
    updatedAt = DateTime.now();
  }

  String? get winner {
    switch (status) {
      case GameStatus.player1Won:
        return players[0].name;
      case GameStatus.player2Won:
        return players[1].name;
      case GameStatus.player3Won:
        return players[2].name;
      case GameStatus.player4Won:
        return players[3].name;
      default:
        return null;
    }
  }

  void switchTurn() {
    final currentIndex = players.indexWhere((p) => p.id == currentPlayerId);
    final nextIndex = (currentIndex + 1) % players.length;
    currentPlayerId = players[nextIndex].id;
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
    for (final player in players) {
      if (player.hasReachedGoal) {
        switch (player.id) {
          case 1:
            status = GameStatus.player1Won;
            break;
          case 2:
            status = GameStatus.player2Won;
            break;
          case 3:
            status = GameStatus.player3Won;
            break;
          case 4:
            status = GameStatus.player4Won;
            break;
        }
        updatedAt = DateTime.now();
        return;
      }
    }
  }

  void addMoveToHistory(GameMove move) {
    moveHistory.add(move);
    updatedAt = DateTime.now();
  }

  bool isPositionOccupied(Position position) {
    return players.any((player) => player.position == position);
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
        final maxRow = from.row < to.row ? to.row : from.row;

        return wallRow == maxRow &&
            wallCol <= from.col &&
            wallCol + 1 >= from.col;
      }
    } else {
      // Vertical wall blocks horizontal movement
      if (from.row == to.row) {
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
      Position(1, 0), // Down
      Position(0, -1), // Left
      Position(0, 1), // Right
    ];

    for (final direction in directions) {
      final newPos = Position(
        position.row + direction.row,
        position.col + direction.col,
      );

      // Check bounds
      if (newPos.row < 0 ||
          newPos.row >= GameConstants.boardSize ||
          newPos.col < 0 ||
          newPos.col >= GameConstants.boardSize) {
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
        if (jumpPos.row >= 0 &&
            jumpPos.row < GameConstants.boardSize &&
            jumpPos.col >= 0 &&
            jumpPos.col < GameConstants.boardSize &&
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
            if (diagPos.row >= 0 &&
                diagPos.row < GameConstants.boardSize &&
                diagPos.col >= 0 &&
                diagPos.col < GameConstants.boardSize &&
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
    'players': players.map((p) => p.toJson()).toList(),
    'walls': walls.map((w) => w.toJson()).toList(),
    'currentPlayerId': currentPlayerId,
    'status': status.index,
    "showValidMoves": showValidMoves,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'moveHistory': moveHistory.map((m) => m.toJson()).toList(),
  };

  static GameState fromJson(Map<String, dynamic> json) => GameState(
    gameId: json['gameId'] as String,
    players: (json['players'] as List).map((p) => Player.fromJson(p)).toList(),
    walls: (json['walls'] as List).map((w) => Wall.fromJson(w)).toList(),
    currentPlayerId: json['currentPlayerId'] as int,
    status: GameStatus.values[json['status'] as int],
    showValidMoves: json['showValidMoves'] as bool? ?? true,
    createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    moveHistory: (json['moveHistory'] as List)
        .map((m) => GameMove.fromJson(m))
        .toList(),
  );

  GameState copyWith({
    String? gameId,
    List<Player>? players,
    List<Wall>? walls,
    int? currentPlayerId,
    GameStatus? status,
    AIDifficulty? aiDifficulty,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? showValidMoves,
    List<GameMove>? moveHistory,
    WallOrientation? wallOrientation,
    WallRotationPhase? wallRotationPhase,
    Wall? previewWall,
  }) {
    return GameState(
      gameId: gameId ?? this.gameId,
      players: players ?? this.players,
      walls: walls ?? this.walls,
      currentPlayerId: currentPlayerId ?? this.currentPlayerId,
      status: status ?? this.status,
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      showValidMoves: showValidMoves ?? this.showValidMoves,
      moveHistory: moveHistory ?? this.moveHistory,
      wallOrientation: wallOrientation ?? this.wallOrientation,
      wallRotationPhase: wallRotationPhase ?? this.wallRotationPhase,
      previewWall: previewWall ?? this.previewWall,
    );
  }
}

// Factory for creating new games
class GameStateFactory {
  static GameState createMultiPlayerGame({
    String? gameId,
    int playerCount = 2,
    List<String>? playerNames,
    List<bool>? aiPlayers,
  }) {
    gameId ??= 'game_${DateTime.now().millisecondsSinceEpoch}';

    final players = PlayerFactory.createPlayersForCount(
      playerCount,
      playerNames: playerNames,
      aiPlayers: aiPlayers,
    );

    return GameState(gameId: gameId, players: players);
  }
}
