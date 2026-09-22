import 'dart:math' as math;
import 'dart:ui';

import '../constants.dart';

/// Geometry for the board, derived from the space the board is actually given.
///
/// Every size here scales with the viewport instead of being a fixed pixel
/// constant, so a cell is as large as the device allows. This is what makes
/// the board comfortable to touch on a phone and still sharp on a tablet.
class BoardMetrics {
  /// Length of one cell edge.
  final double cellSize;

  /// Gap between two neighbouring cells. Walls are drawn inside this gap.
  final double spacing;

  /// Padding between the board edge and the outer cells.
  final double padding;

  /// Offset of the board's top-left corner inside the component, so that a
  /// square board stays centred in a non-square viewport.
  final Offset origin;

  const BoardMetrics._({
    required this.cellSize,
    required this.spacing,
    required this.padding,
    required this.origin,
  });

  // Ratios are expressed relative to a cell so the whole board scales as one.
  static const double _spacingRatio = 0.14;
  static const double _paddingRatio = 0.35;
  static const double _wallRatio = 0.22;

  /// Smallest cell we ever render. Below this the board stops shrinking and
  /// is allowed to overflow rather than becoming untappable.
  static const double minCellSize = 22.0;

  static const int _n = GameConstants.boardSize;

  /// Builds metrics that fit a square board into [viewport].
  factory BoardMetrics.fit(Size viewport) {
    final side = math.max(0.0, math.min(viewport.width, viewport.height));

    // side = n*cell + (n-1)*spacing + 2*padding, with spacing and padding
    // expressed as ratios of cell.
    const divisor = _n + (_n - 1) * _spacingRatio + 2 * _paddingRatio;
    final cellSize = math.max(minCellSize, side / divisor);

    final spacing = cellSize * _spacingRatio;
    final padding = cellSize * _paddingRatio;
    final boardSide = _n * cellSize + (_n - 1) * spacing + 2 * padding;

    return BoardMetrics._(
      cellSize: cellSize,
      spacing: spacing,
      padding: padding,
      origin: Offset(
        (viewport.width - boardSide) / 2,
        (viewport.height - boardSide) / 2,
      ),
    );
  }

  /// Distance from one cell's leading edge to the next one's.
  double get step => cellSize + spacing;

  /// Thickness of a placed wall.
  double get wallThickness => cellSize * _wallRatio;

  /// Full edge length of the rendered board, padding included.
  double get boardSide => _n * cellSize + (_n - 1) * spacing + 2 * padding;

  Rect get boardRect =>
      Rect.fromLTWH(origin.dx, origin.dy, boardSide, boardSide);

  /// Top-left of the cell grid, i.e. inside the padding.
  double get _left => origin.dx + padding;
  double get _top => origin.dy + padding;

  Rect cellRect(Position position) => Rect.fromLTWH(
    _left + position.col * step,
    _top + position.row * step,
    cellSize,
    cellSize,
  );

  Offset cellCenter(Position position) => cellRect(position).center;

  /// Centre of the grid intersection [row], [col], where the intersections are
  /// the gaps between cells. Intersection (r, c) sits between rows r-1/r and
  /// columns c-1/c, so valid interior values run from 1 to boardSize - 1.
  Offset intersectionCenter(int row, int col) =>
      Offset(_left + col * step - spacing / 2, _top + row * step - spacing / 2);

  /// The rectangle a wall occupies.
  ///
  /// A horizontal wall at (r, c) lies in the gap above row r and spans columns
  /// c and c+1. A vertical wall at (r, c) lies in the gap left of column c and
  /// spans rows r and r+1. This matches how [GameState] resolves blocking.
  Rect wallRect(Wall wall) {
    if (wall.orientation == WallOrientation.horizontal) {
      return Rect.fromLTWH(
        _left + wall.position.col * step,
        _top + wall.position.row * step - spacing / 2 - wallThickness / 2,
        2 * cellSize + spacing,
        wallThickness,
      );
    }
    return Rect.fromLTWH(
      _left + wall.position.col * step - spacing / 2 - wallThickness / 2,
      _top + wall.position.row * step,
      wallThickness,
      2 * cellSize + spacing,
    );
  }

  /// The cell under [point], or null when the point falls outside the grid.
  Position? positionAt(Offset point) {
    final x = point.dx - _left;
    final y = point.dy - _top;
    if (x < 0 || y < 0) return null;

    final col = (x / step).floor();
    final row = (y / step).floor();
    if (row < 0 || row >= _n || col < 0 || col >= _n) return null;
    return Position(row, col);
  }

  /// The interior intersection closest to [point], clamped into range.
  ///
  /// Every point on the board resolves to some intersection, so a wall tap
  /// never has to hit a thin target: the player taps roughly where they want
  /// the wall and it snaps to the nearest slot.
  ({int row, int col}) nearestIntersection(Offset point) {
    final x = point.dx - _left;
    final y = point.dy - _top;

    final col = ((x + spacing / 2) / step).round().clamp(1, _n - 1);
    final row = ((y + spacing / 2) / step).round().clamp(1, _n - 1);
    return (row: row, col: col);
  }

  /// The wall that would be placed at intersection [row]/[col] with the given
  /// [orientation], converted into the game's wall coordinates.
  static Wall wallAtIntersection(
    int row,
    int col,
    WallOrientation orientation,
  ) {
    if (orientation == WallOrientation.horizontal) {
      // Sits in the gap above `row`, spanning columns col-1 and col.
      return Wall(Position(row, col - 1), orientation);
    }
    // Sits in the gap left of `col`, spanning rows row-1 and row.
    return Wall(Position(row - 1, col), orientation);
  }

  /// Inverse of [wallAtIntersection].
  static ({int row, int col}) intersectionOfWall(Wall wall) {
    if (wall.orientation == WallOrientation.horizontal) {
      return (row: wall.position.row, col: wall.position.col + 1);
    }
    return (row: wall.position.row + 1, col: wall.position.col);
  }
}
