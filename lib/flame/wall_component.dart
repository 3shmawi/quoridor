import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';

class WallComponent extends PositionComponent {
  GameState gameState;
  Wall? previewWall;
  bool isValid = true;

  static const double _cellSize = GameConstants.cellSize;
  static const double _wallThickness = GameConstants.wallThickness;
  static const double _boardPadding = GameConstants.boardPadding;
  static const double cellSpacing = GameConstants.cellSpacing;

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
      ..color = const Color(GameConstants.wallColor)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = const Color(GameConstants.wallColor).withOpacity(0.3)
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
          ? const Color(0xFF00C853).withOpacity(0.4) // green glow
          : const Color(0xFFFF0000).withOpacity(0.4) // red glow
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
        ..color = Colors.black.withOpacity(0.2)
        ..style = PaintingStyle.fill,
    );

    // Preview wall fill
    final previewPaint = Paint()
      ..color = isValid
          ? const Color(GameConstants.wallColor).withOpacity(0.5)
          : const Color(0xFFFF0000).withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isValid
          ? const Color(GameConstants.wallColor)
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
        _boardPadding + wall.position.col * (_cellSize + cellSpacing),
        _boardPadding +
            wall.position.row * (_cellSize + cellSpacing) -
            _wallThickness / 2,
        _cellSize * 2 + cellSpacing,
        _wallThickness,
      );
    } else {
      return Rect.fromLTWH(
        _boardPadding +
            wall.position.col * (_cellSize + cellSpacing) -
            _wallThickness / 2,
        _boardPadding + wall.position.row * (_cellSize + cellSpacing),
        _wallThickness,
        _cellSize * 2 + cellSpacing,
      );
    }
  }
}
