// Game constants and configurations for Quoridor game
class GameConstants {
  // Board dimensions
  static const int boardSize = 9;
  static const int maxWallsPerPlayer = 10;

  // Cell dimensions for rendering
  static const double cellSize = 30.0;
  static const double cellSpacing = 4.0;
  static const double boardPadding = 10.0;
  static const double goalLineThickness = 4.0;
  static const double wallThickness = 6.0;
  static const double wallLength = cellSize * 2 + wallThickness;

  // Board colors
  static const int lightCellColor = 0xFFF1F4F8;
  static const int darkCellColor = 0xFFE5E7EB;
  static const int player1Color = 0xFF6F61EF;
  static const int player2Color = 0xFF39D2C0;

  /// Placed walls. The old near-black wall was almost invisible against the
  /// dark board, which was a large part of why walls read as confusing, so the
  /// colour now follows the theme and stays high contrast in both.
  static const int wallColor = 0xFF6B4423;
  static const int wallColorDark = 0xFFF2A93B;
  static const int validMoveColor = 0xFFEE8B60;

  // Player starting positions
  static const Position player1Start = Position(8, 4);
  static const Position player2Start = Position(0, 4);

  /// Players three and four come in from the sides, so their goal is the
  /// opposite column rather than a row.
  static const Position player3Start = Position(4, 0);
  static const Position player4Start = Position(4, 8);

  // Goal rows
  static const int player1Goal = 0;
  static const int player2Goal = 8;

  /// How many walls each player holds, by how many are playing.
  ///
  /// The board does not grow with the players, so a fixed ten each would let
  /// three or four people wall it into a maze nobody can cross. The totals
  /// here keep roughly the same number of walls on the board however many are
  /// playing, which is how the boxed game handles it.
  static int wallsFor(int playerCount) {
    switch (playerCount) {
      case 3:
        return 7;
      case 4:
        return 5;
      default:
        return maxWallsPerPlayer;
    }
  }

  /// The seat colours, indexed by seat number.
  static const int player3Color = 0xFFF2A93B;
  static const int player4Color = 0xFFEE5D8A;

  static int colorForSeat(int seat) {
    switch (seat) {
      case 1:
        return player1Color;
      case 2:
        return player2Color;
      case 3:
        return player3Color;
      default:
        return player4Color;
    }
  }
}

/// The side of the board a player is trying to reach.
///
/// This replaces a plain goal row. Players one and two race up and down, so a
/// row was enough for them, but three and four cross the board sideways and
/// have no goal row at all — which is why every part of the game that asked
/// "is this pawn on its goal row?" had to learn to ask this instead.
enum GoalEdge {
  top,
  bottom,
  left,
  right;

  /// Whether [position] is on this edge.
  bool contains(Position position) {
    const last = GameConstants.boardSize - 1;
    switch (this) {
      case GoalEdge.top:
        return position.row == 0;
      case GoalEdge.bottom:
        return position.row == last;
      case GoalEdge.left:
        return position.col == 0;
      case GoalEdge.right:
        return position.col == last;
    }
  }

  /// The edge a player starting on this one is aiming for.
  GoalEdge get opposite {
    switch (this) {
      case GoalEdge.top:
        return GoalEdge.bottom;
      case GoalEdge.bottom:
        return GoalEdge.top;
      case GoalEdge.left:
        return GoalEdge.right;
      case GoalEdge.right:
        return GoalEdge.left;
    }
  }

  /// Where each seat starts, and so which edge it defends.
  static GoalEdge homeOfSeat(int seat) {
    switch (seat) {
      case 1:
        return GoalEdge.bottom;
      case 2:
        return GoalEdge.top;
      case 3:
        return GoalEdge.left;
      default:
        return GoalEdge.right;
    }
  }

  /// Where each seat is trying to get to.
  static GoalEdge goalOfSeat(int seat) => homeOfSeat(seat).opposite;
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

/// How a game stands.
///
/// Seats three and four are appended rather than slotted in beside the first
/// two, because the index of each value is what gets written to saved games
/// and to the server — renumbering them would make every game in flight read
/// back as something else.
enum GameStatus {
  playing,
  player1Won,
  player2Won,
  draw,
  player3Won,
  player4Won;

  /// The status meaning [seat] has won.
  static GameStatus wonBy(int seat) {
    switch (seat) {
      case 1:
        return GameStatus.player1Won;
      case 2:
        return GameStatus.player2Won;
      case 3:
        return GameStatus.player3Won;
      case 4:
        return GameStatus.player4Won;
      default:
        return GameStatus.playing;
    }
  }
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
