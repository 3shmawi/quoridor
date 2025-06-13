import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/components/board_component.dart';
import 'package:quoridor/theme.dart';

import '/flame/constants.dart';
import '/flame/models/game_state.dart';

class WallComponent extends PositionComponent {
  GameState gameState;
  Wall? previewWall;

  Wall? lastTappedWall;
  bool isValid = true;

  static const double _wallThickness = GameConstants.wallThickness;
  static const double _boardPadding = GameConstants.boardPadding;
  static const double _cellSpacing = GameConstants.cellSpacing;

  WallComponent(this.gameState);

  @override
  void render(Canvas canvas) {
    _drawWalls(canvas);
    if (previewWall != null) {
      _drawPreviewWall(canvas);
    }
  }

  void _drawWalls(Canvas canvas) {
    final wallPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? Colors.white
          : const Color(GameConstants.wallColor)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? Colors.white.withValues(alpha: 0.3)
          : const Color(GameConstants.wallColor).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (final wall in gameState.walls) {
      final rect = _getWallRect(wall);

      // Draw shadow
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.translate(2, 2), const Radius.circular(2)),
        shadowPaint,
      );

      // Draw wall
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        wallPaint,
      );
    }
  }

  void _drawPreviewWall(Canvas canvas) {
    if (previewWall == null) return;

    final rect = _getWallRect(previewWall!);

    // Draw glow effect
    final glowPaint = Paint()
      ..color = isValid
          ? const Color(0xFF00C853).withValues(alpha: 0.4) // green glow
          : const Color(0xFFFF0000).withValues(alpha: 0.4) // red glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(4)),
      glowPaint,
    );

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.translate(2, 2), const Radius.circular(2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill,
    );

    // Preview wall fill
    final previewPaint = Paint()
      ..color = isValid
          ? (isDarkModeNotifier.value
                ? Colors.white.withValues(alpha: 0.5)
                : const Color(GameConstants.wallColor).withValues(alpha: 0.5))
          : const Color(0xFFFF0000).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isValid
          ? (isDarkModeNotifier.value
                ? Colors.white
                : const Color(GameConstants.wallColor))
          : const Color(0xFFFF0000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      previewPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      borderPaint,
    );
  }

  Rect _getWallRect(Wall wall) {
    if (wall.orientation == WallOrientation.horizontal) {
      return Rect.fromLTWH(
        _boardPadding +
            wall.position.col * (cellSizeNotifier.value + _cellSpacing),
        _boardPadding +
            wall.position.row * (cellSizeNotifier.value + _cellSpacing) -
            _wallThickness / 2,
        cellSizeNotifier.value * 2 + _cellSpacing,
        _wallThickness,
      );
    } else {
      return Rect.fromLTWH(
        _boardPadding +
            wall.position.col * (cellSizeNotifier.value + _cellSpacing) -
            _wallThickness / 2,
        _boardPadding +
            wall.position.row * (cellSizeNotifier.value + _cellSpacing),
        _wallThickness,
        cellSizeNotifier.value * 2 + _cellSpacing,
      );
    }
  }

  Wall? getWallFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final cellCol = (localX / (cellSizeNotifier.value + _cellSpacing)).floor();
    final cellRow = (localY / (cellSizeNotifier.value + _cellSpacing)).floor();

    final cellX = localX % (cellSizeNotifier.value + _cellSpacing);
    final cellY = localY % (cellSizeNotifier.value + _cellSpacing);

    // Increased threshold for easier wall placement
    const edgeThreshold = 0.4; // 40% of cell size for wall placement
    final threshold = cellSizeNotifier.value * edgeThreshold;

    debugPrint('Wall position calculation:');
    debugPrint('- Local coordinates: ($localX, $localY)');
    debugPrint('- Cell coordinates: ($cellX, $cellY)');
    debugPrint('- Cell position: row=$cellRow, col=$cellCol');
    debugPrint('- Edge threshold: $threshold');

    // Check horizontal walls
    if (cellY < threshold && cellRow > 0) {
      debugPrint(
        '- Detected horizontal wall above at row: $cellRow, col: $cellCol',
      );
      return Wall(Position(cellRow, cellCol), WallOrientation.horizontal);
    } else if (cellY > cellSizeNotifier.value - threshold &&
        cellRow < GameConstants.boardSize - 1) {
      debugPrint(
        '- Detected horizontal wall below at row: ${cellRow + 1}, col: $cellCol',
      );
      return Wall(Position(cellRow + 1, cellCol), WallOrientation.horizontal);
    }

    // Check vertical walls
    if (cellX < threshold && cellCol > 0) {
      debugPrint(
        '- Detected vertical wall left at row: $cellRow, col: $cellCol',
      );
      return Wall(Position(cellRow, cellCol), WallOrientation.vertical);
    } else if (cellX > cellSizeNotifier.value - threshold &&
        cellCol < GameConstants.boardSize - 1) {
      debugPrint(
        '- Detected vertical wall right at row: $cellRow, col: ${cellCol + 1}',
      );
      return Wall(Position(cellRow, cellCol + 1), WallOrientation.vertical);
    }

    return null;
  }
}
