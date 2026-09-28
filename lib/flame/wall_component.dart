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

  /// Marks every slot a wall could occupy.
  ///
  /// These are always on while the player still has walls: they are what makes
  /// wall placement discoverable without a mode to switch into, and they are
  /// kept faint so the board still reads as a board.
  bool showSlots = true;

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
      ..color = const Color(0xFF64748B).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final radius = metrics.spacing * 0.3;

    for (int row = 1; row < GameConstants.boardSize; row++) {
      for (int col = 1; col < GameConstants.boardSize; col++) {
        canvas.drawCircle(metrics.intersectionCenter(row, col), radius, paint);
      }
    }
  }

  /// Who placed each wall, worked out from the move history.
  ///
  /// The wall itself does not record an owner -- it is just a position and an
  /// orientation, which is all the rules need -- so the history is the source
  /// for this. A wall with no matching move (an older saved game, say) falls
  /// back to the neutral colour.
  Map<Wall, int> get _wallOwners {
    final owners = <Wall, int>{};
    for (final move in gameState.moveHistory) {
      final wall = move.wall;
      if (move.type == MoveType.wallPlace && wall != null) {
        owners[wall] = move.playerId;
      }
    }
    return owners;
  }

  Color _wallColor(int? ownerId) {
    if (ownerId == null) {
      return Color(
        isDarkModeNotifier.value
            ? GameConstants.wallColorDark
            : GameConstants.wallColor,
      );
    }
    return Color(GameConstants.colorForSeat(ownerId));
  }

  void _drawWalls(Canvas canvas) {
    final owners = _wallOwners;

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
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()
          ..color = _wallColor(owners[wall])
          ..style = PaintingStyle.fill,
      );
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
      RRect.fromRectAndRadius(
        rect.inflate(metrics.wallThickness * 0.5),
        radius,
      ),
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
