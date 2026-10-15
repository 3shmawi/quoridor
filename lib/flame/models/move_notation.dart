import '../constants.dart';

/// Short written names for squares and moves, for the move list.
///
/// Columns are lettered a to i from player 1's left and rows numbered 1 to 9
/// from player 1's end, the way the board is usually written about. A wall
/// is named by the square at the top-left of the four it sits between, plus
/// `h` or `v` for which way it runs.
class MoveNotation {
  MoveNotation._();

  static const _columns = 'abcdefghi';

  /// The square at [position], such as `e1` for player 1's start.
  static String square(Position position) =>
      '${_columns[position.col]}${GameConstants.boardSize - position.row}';

  /// The wall [wall], such as `e3h`.
  static String wall(Wall wall) {
    final row = wall.position.row;
    final col = wall.position.col;
    // A horizontal wall at (r, c) lies between rows r - 1 and r across
    // columns c and c + 1; a vertical one between columns c - 1 and c down
    // rows r and r + 1. Either way the top-left of that block names it.
    final topLeft = wall.orientation == WallOrientation.horizontal
        ? Position(row - 1, col)
        : Position(row, col - 1);
    final direction = wall.orientation == WallOrientation.horizontal
        ? 'h'
        : 'v';
    return '${square(topLeft)}$direction';
  }

  /// [move] written out, or null for a pass, which has no square to name.
  static String? of(GameMove move) {
    switch (move.type) {
      case MoveType.pawnMove:
        return square(move.newPosition!);
      case MoveType.wallPlace:
        return wall(move.wall!);
      case MoveType.pass:
        return null;
    }
  }
}
