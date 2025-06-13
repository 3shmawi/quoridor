import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '/flame/components/board_component.dart';
import '../constants.dart';
import '../models/game_state.dart';

class PlayerComponent extends PositionComponent {
  GameState gameState;
  bool showValidMoves = true;
  Position? selectedPawn;
  List<Position> validMoves = [];

  final double _boardPadding = GameConstants.boardPadding;
  final double _cellSpacing = GameConstants.cellSpacing;

  PlayerComponent(this.gameState);

  @override
  void render(Canvas canvas) {
    _drawValidMoves(canvas);
    _drawPlayers(canvas);
    _drawSelection(canvas);
  }

  void _drawPlayers(Canvas canvas) {
    // Draw player 1
    _drawPlayer(
      canvas: canvas,
      position: gameState.player1.position,
      color: const Color(GameConstants.player1Color),
      playerId: 1,
    );

    // Draw player 2
    _drawPlayer(
      canvas: canvas,
      position: gameState.player2.position,
      color: const Color(GameConstants.player2Color),
      playerId: 2,
    );
  }

  void _drawPlayer({
    required Canvas canvas,
    required Position position,
    required Color color,
    required int playerId,
  }) {
    final center = _getCellCenter(position);
    final isSelected = selectedPawn == position;
    final radius = cellSizeNotifier.value * 0.35;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final pawnPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Draw shadow
    canvas.drawCircle(
      Offset(center.dx + 2, center.dy + 2),
      radius,
      shadowPaint,
    );

    // Draw pawn base
    canvas.drawCircle(center, radius, pawnPaint);

    // Draw white border
    canvas.drawCircle(center, radius, borderPaint);

    // Draw highlight if selected
    if (isSelected) {
      final selectionPaint = Paint()
        ..color = const Color(GameConstants.validMoveColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      canvas.drawCircle(center, radius + 6, selectionPaint);
    }

    // Draw inner highlight
    canvas.drawCircle(
      Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
      radius * 0.2,
      highlightPaint,
    );

    // Draw player number
    final textPainter = TextPainter(
      text: TextSpan(
        text: playerId.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawSelection(Canvas canvas) {
    if (selectedPawn != null) {
      final paint = Paint()
        ..color = const Color(
          GameConstants.validMoveColor,
        ).withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(
        _boardPadding +
            selectedPawn!.col * (cellSizeNotifier.value + _cellSpacing),
        _boardPadding +
            selectedPawn!.row * (cellSizeNotifier.value + _cellSpacing),
        cellSizeNotifier.value,
        cellSizeNotifier.value,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  void _drawValidMoves(Canvas canvas) {
    if (!showValidMoves || validMoves.isEmpty) return;

    final paint = Paint()
      ..color = const Color(GameConstants.validMoveColor).withValues(alpha: 0.6)
      ..color = const Color(GameConstants.validMoveColor).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(GameConstants.validMoveColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final position in validMoves) {
      final center = _getCellCenter(position);

      canvas.drawCircle(center, cellSizeNotifier.value * 0.3, paint);
      canvas.drawCircle(center, cellSizeNotifier.value * 0.3, borderPaint);
    }
  }

  Offset _getCellCenter(Position position) {
    return Offset(
      _boardPadding +
          position.col * (cellSizeNotifier.value + _cellSpacing) +
          cellSizeNotifier.value / 2,
      _boardPadding +
          position.row * (cellSizeNotifier.value + _cellSpacing) +
          cellSizeNotifier.value / 2,
    );
  }
}
