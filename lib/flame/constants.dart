import 'package:flutter/foundation.dart';

final cellSizeNotifier = ValueNotifier<double>(40);

// Game constants and configurations for Quoridor game

class GameConstants {
  // Board dimensions
  static const int boardSize = 9;
  static const int maxWallsPerPlayer = 10;

  // Multi-player configurations
  static const int maxPlayers = 4;
  static const int wallsFor2Players = 10;
  static const int wallsFor3Players = 7;
  static const int wallsFor4Players = 5;

  // Cell dimensions for rendering
  // static const double cellSize = 40.0;
  static const double cellSpacing = 4.0;
  static const double boardPadding = 10.0;
  static const double goalLineThickness = 4.0;
  static const double wallThickness = 6.0;
  // static const double wallLength = cellSize * 2 + wallThickness;

  // Board colors
  static const int lightCellColor = 0xFFF1F4F8;
  static const int darkCellColor = 0xFFE5E7EB;
  static const int player1Color = 0xFF6F61EF;
  static const int player2Color = 0xFF006400;
  static const int player3Color = 0xFFE74C3C;
  static const int player4Color = 0xFFF39C12;
  static const int wallColor = 0xFF15161E;
  static const int validMoveColor = 0xFFEE8B60;

  // Player starting positions (correct Quoridor setup)
  static const Position player1Start = Position(8, 4); // Bottom center
  static const Position player2Start = Position(0, 4); // Top center
  static const Position player3Start = Position(4, 8); // Right center
  static const Position player4Start = Position(4, 0); // Left center

  // Goal rows (entire rows are goals)
  static const int player1Goal = 0; // Top row
  static const int player2Goal = 8; // Bottom row
  static const int player3Goal = 4; // Center row (for 4-player mode)
  static const int player4Goal = 4; // Center row (for 4-player mode)

  // Goal columns (entire columns are goals for 4-player mode)
  static const int player1GoalCol = 4; // Center column (for 4-player mode)
  static const int player2GoalCol = 4; // Center column (for 4-player mode)
  static const int player3GoalCol = 0; // Left column
  static const int player4GoalCol = 8; // Right column

  // Helper method to get wall count based on player count
  static int getWallsForPlayerCount(int playerCount) {
    switch (playerCount) {
      case 2:
        return wallsFor2Players;
      case 3:
        return wallsFor3Players;
      case 4:
        return wallsFor4Players;
      default:
        return wallsFor2Players;
    }
  }

  // Helper method to get player color
  static int getPlayerColor(int playerId) {
    switch (playerId) {
      case 1:
        return player1Color;
      case 2:
        return player2Color;
      case 3:
        return player3Color;
      case 4:
        return player4Color;
      default:
        return player1Color;
    }
  }
}

class Position {
  final int row;
  final int col;

  const Position(this.row, this.col);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Position && other.row == row && other.col == col;
  }

  @override
  int get hashCode => row.hashCode ^ col.hashCode;

  @override
  String toString() => 'Position($row, $col)';

  Map<String, dynamic> toJson() => {'row': row, 'col': col};

  static Position fromJson(Map<String, dynamic> json) =>
      Position(json['row'] as int, json['col'] as int);

  Position copyWith({int? row, int? col}) {
    return Position(row ?? this.row, col ?? this.col);
  }
}

enum WallOrientation { horizontal, vertical }

enum WallRotationPhase {
  verticalLeft,
  horizontalTop,
  verticalRight,
  horizontalBottom,
}

class Wall {
  final Position position; // Top-left position of the wall
  final WallOrientation orientation;

  const Wall(this.position, this.orientation);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Wall &&
        other.position == position &&
        other.orientation == orientation;
  }

  @override
  int get hashCode => position.hashCode ^ orientation.hashCode;

  Map<String, dynamic> toJson() => {
    'position': position.toJson(),
    'orientation': orientation.index,
  };

  static Wall fromJson(Map<String, dynamic> json) => Wall(
    Position.fromJson(json['position']),
    WallOrientation.values[json['orientation'] as int],
  );

  Wall copyWith({Position? position, WallOrientation? orientation}) {
    return Wall(position ?? this.position, orientation ?? this.orientation);
  }
}

enum GameStatus {
  playing,
  player1Won,
  player2Won,
  player3Won,
  player4Won,
  draw,
}

enum MoveType { pawnMove, wallPlace }

class GameMove {
  final MoveType type;
  final Position? newPosition; // For pawn moves
  final Wall? wall; // For wall placement
  final int playerId;

  const GameMove.pawnMove(this.newPosition, this.playerId)
    : type = MoveType.pawnMove,
      wall = null;

  const GameMove.wallPlace(this.wall, this.playerId)
    : type = MoveType.wallPlace,
      newPosition = null;

  Map<String, dynamic> toJson() => {
    'type': type.index,
    'newPosition': newPosition?.toJson(),
    'wall': wall?.toJson(),
    'playerId': playerId,
  };

  static GameMove fromJson(Map<String, dynamic> json) {
    final moveType = MoveType.values[json['type'] as int];
    final playerId = json['playerId'] as int;

    if (moveType == MoveType.pawnMove) {
      return GameMove.pawnMove(
        Position.fromJson(json['newPosition']),
        playerId,
      );
    } else {
      return GameMove.wallPlace(Wall.fromJson(json['wall']), playerId);
    }
  }
}
