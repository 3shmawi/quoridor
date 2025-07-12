import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../controller/game_controller.dart';
import '../controller/game_states.dart';
import '../models/game_state.dart';

class PlayerComponent extends PositionComponent {
  GameController? _gameController;
  bool showValidMoves = true;
  Position? selectedPawn;
  List<Position> validMoves = [];

  final double _boardPadding = GameConstants.boardPadding;
  final double _cellSpacing = GameConstants.cellSpacing;

  PlayerComponent({GameController? gameController}) {
    _gameController = gameController;
  }

  void setGameController(GameController controller) {
    _gameController = controller;
  }

  void updateFromState(GamePlayingState state) {
    showValidMoves = state.showValidMoves;
    validMoves = state.validMoves;
  }

  void clearSelection() {
    selectedPawn = null;
    validMoves.clear();
  }

  @override
  void render(Canvas canvas) {
    if (_gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    _drawValidMoves(canvas, gameState);
    _drawPlayers(canvas, gameState);
    _drawSelection(canvas, gameState);
  }

  void _drawPlayers(Canvas canvas, GameState gameState) {
    for (final player in gameState.players) {
      _drawPlayer(
        canvas: canvas,
        position: player.position,
        playerId: player.id,
        gameState: gameState,
      );
    }
  }

  void _drawPlayer({
    required Canvas canvas,
    required Position position,
    required int playerId,
    required GameState gameState,
  }) {
    final center = _getCellCenter(position);
    final isSelected = selectedPawn == position;
    final radius = cellSizeNotifier.value * 0.35;

    final milliseconds = DateTime.now().millisecondsSinceEpoch;
    final isCurrentPlayer = gameState.currentPlayerId == playerId;
    final t = isCurrentPlayer ? (sin(milliseconds / 300.0) + 1) / 2 : 1;
    final opacity = isCurrentPlayer ? 1.0 : 0.15;

    final playerColor = Color(GameConstants.getPlayerColor(playerId));

    if (isCurrentPlayer) {
      final glowPaint = Paint()
        ..color = playerColor.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, radius * 1.6, glowPaint);
    }

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2 * opacity * (.5 + t))
      ..style = PaintingStyle.fill;

    final pawnPaint = Paint()
      ..color = playerColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * (.5 + t))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3 * opacity * (.5 + t))
      ..style = PaintingStyle.fill;

    // Animate scale for current player
    final scale = isCurrentPlayer
        ? 1.0 + 0.05 * sin(milliseconds / 200.0)
        : 1.0;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    canvas.drawCircle(
      Offset(center.dx + 2, center.dy + 2),
      radius,
      shadowPaint,
    );
    canvas.drawCircle(center, radius, pawnPaint);
    canvas.drawCircle(center, radius, borderPaint);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
      radius * 0.2,
      highlightPaint,
    );

    if (isSelected) {
      final selectionPaint = Paint()
        ..color = const Color(GameConstants.validMoveColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawCircle(center, radius + 6, selectionPaint);
    }

    canvas.restore();

    final textPainter = TextPainter(
      text: TextSpan(
        text: playerId.toString(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
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

  void _drawSelection(Canvas canvas, GameState gameState) {
    if (selectedPawn != null) {
      final paint = Paint()
        ..color = const Color(GameConstants.validMoveColor).withOpacity(0.3)
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

  void _drawValidMoves(Canvas canvas, GameState gameState) {
    if (!showValidMoves || validMoves.isEmpty || selectedPawn == null) return;

    final paint = Paint()
      ..color = const Color(GameConstants.validMoveColor).withOpacity(0.3)
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
