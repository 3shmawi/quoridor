// Game constants and configurations for Quoridor game
class GameConstants {
  // Board dimensions
  static const int boardSize = 9;
  static const int maxWallsPerPlayer = 10;

  // Cell dimensions for rendering
  static const double cellSize = 50.0;
  static const double wallThickness = 4.0;
  static const double wallLength = cellSize * 2 + wallThickness;

  // Board colors
  static const int lightCellColor = 0xFFF1F4F8;
  static const int darkCellColor = 0xFFE5E7EB;
  static const int player1Color = 0xFF6F61EF;
  static const int player2Color = 0xFF39D2C0;
  static const int wallColor = 0xFF15161E;
  static const int validMoveColor = 0xFFEE8B60;

  // Player starting positions
  static const Position player1Start = Position(0, 4);
  static const Position player2Start = Position(8, 4);

  // Goal rows
  static const int player1Goal = 8;
  static const int player2Goal = 0;
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
}

enum WallOrientation { horizontal, vertical }

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
}

enum GameStatus { playing, player1Won, player2Won, draw }

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
