import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/board/board_metrics.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/theme.dart';

/// Draws the walls that are on the board plus the wall the player is lining up.
class WallComponent extends PositionComponent {
  GameState gameState;

  /// The wall being positioned but not yet committed.
  Wall? previewWall;

  /// Whether [previewWall] is a legal placement, which drives its colour.
  bool isValid = true;

  /// Marks every slot a wall could occupy. Shown only in wall mode, where it
  /// tells the player that the gaps between cells are the targets.
  bool showSlots = false;

  /// Geometry shared with the board; kept in sync by [BoardComponent].
  BoardMetrics metrics = BoardMetrics.fit(Size.zero);

  WallComponent(this.gameState);

  @override
  void render(Canvas canvas) {
    if (showSlots) _drawSlots(canvas);
    _drawWalls(canvas);
    if (previewWall != null) _drawPreviewWall(canvas);
  }

  void _drawSlots(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final radius = metrics.spacing * 0.42;

    for (int row = 1; row < GameConstants.boardSize; row++) {
      for (int col = 1; col < GameConstants.boardSize; col++) {
        canvas.drawCircle(metrics.intersectionCenter(row, col), radius, paint);
      }
    }
  }

  void _drawWalls(Canvas canvas) {
    final wallPaint = Paint()
      ..color = Color(
        isDarkModeNotifier.value
            ? GameConstants.wallColorDark
            : GameConstants.wallColor,
      )
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final radius = Radius.circular(metrics.wallThickness * 0.4);

    for (final wall in gameState.walls) {
      final rect = metrics.wallRect(wall);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.translate(0, metrics.wallThickness * 0.2),
          radius,
        ),
        shadowPaint,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), wallPaint);
    }
  }

  void _drawPreviewWall(Canvas canvas) {
    final wall = previewWall;
    if (wall == null) return;

    final rect = metrics.wallRect(wall);
    final radius = Radius.circular(metrics.wallThickness * 0.4);

    // Green when the wall can be placed, red when it cannot, so the player
    // reads the outcome before committing rather than after being refused.
    final accent = isValid ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(metrics.wallThickness * 0.5), radius),
      Paint()
        ..color = accent.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          metrics.wallThickness * 0.6,
        ),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = accent.withValues(alpha: 0.65)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = metrics.wallThickness * 0.22
        ..strokeJoin = StrokeJoin.round,
    );
  }
}
