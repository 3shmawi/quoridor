import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '/flame/components/player_components.dart';
import '/theme.dart';
import '../constants.dart';
import '../controller/game_controller.dart';
import '../controller/game_states.dart';
import '../models/game_state.dart';
import 'wall_component.dart';

class BoardComponent extends PositionComponent {
  bool enableSound = true;
  bool showValidMoves = true;
  GameController? _gameController;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;

  late final WallComponent wallComponent;
  late final PlayerComponent _playerComponent;

  static const double _boardPadding = GameConstants.boardPadding;
  static const double _cellSpacing = GameConstants.cellSpacing;

  BoardComponent({GameController? gameController}) {
    _gameController = gameController;
    _playerComponent = PlayerComponent(gameController: gameController);
    wallComponent = WallComponent(gameController: gameController);
    add(wallComponent);
    add(_playerComponent);
  }

  void setGameController(GameController controller) {
    _gameController = controller;
    _playerComponent.setGameController(controller);
    wallComponent.setGameController(controller);
  }

  void updateFromState(GamePlayingState state) {
    showValidMoves = state.showValidMoves;
    _playerComponent.updateFromState(state);
    wallComponent.updateFromState(state);
  }

  @override
  void render(Canvas canvas) {
    if (_gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    _drawGrid(canvas, gameState);
  }

  void _drawGrid(Canvas canvas, GameState gameState) {
    final lightPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF2C3E50)
          : const Color(GameConstants.lightCellColor)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF1A2530)
          : const Color(GameConstants.darkCellColor)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF34495E)
          : const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final milliseconds = DateTime.now().millisecondsSinceEpoch;
    final t = (sin(milliseconds / 300.0) + 1) / 2;

    final isPlayer1 = gameState.currentPlayer.id == 1;
    final playerColor = Color(
      isPlayer1 ? GameConstants.player1Color : GameConstants.player2Color,
    );

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        final rect = Rect.fromLTWH(
          _boardPadding + col * (cellSizeNotifier.value + _cellSpacing),
          _boardPadding + row * (cellSizeNotifier.value + _cellSpacing),
          cellSizeNotifier.value,
          cellSizeNotifier.value,
        );

        final isLight = (row + col) % 2 == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          isLight ? lightPaint : darkPaint,
        );

        final isGoalRow =
            (row == 0 && isPlayer1) ||
            (row == GameConstants.boardSize - 1 && !isPlayer1);

        if (isGoalRow) {
          // 🔥 1. Glow effect
          final glowPaint = Paint()
            ..color = playerColor.withValues(alpha: 0.6 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect.inflate(1.5),
              const Radius.circular(6),
            ),
            glowPaint,
          );

          // 🎯 3. Goal label (emoji or text)
          final goalText = TextPainter(
            text: TextSpan(
              text: '🏁', // Or use: 'GOAL'
              style: TextStyle(
                fontSize: 16,
                color: playerColor.withValues(alpha: 0.65),
                fontWeight: FontWeight.bold,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          goalText.layout();
          final goalOffset = Offset(
            rect.left + (rect.width - goalText.width) / 2,
            rect.top + (rect.height - goalText.height) / 2,
          );
          goalText.paint(canvas, goalOffset);
        }

        // 🧱 Cell border
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          borderPaint,
        );
      }
    }
  }

  void handleTap(Vector2 position) {
    if (_gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    final offset = Offset(position.x, position.y);
    final cellPosition = _getPositionFromOffset(offset);
    final wall = wallComponent.getWallFromOffset(offset);

    debugPrint(
      'Tap detected at screen position: (${position.x}, ${position.y})',
    );
    debugPrint('Converted to board offset: (${offset.dx}, ${offset.dy})');

    // If a player is selected, prioritize movement
    if (_playerComponent.selectedPawn != null) {
      if (cellPosition != null) {
        debugPrint('Player selected, checking move:');
        debugPrint(
          '- Selected pawn position: row=${_playerComponent.selectedPawn!.row}, col=${_playerComponent.selectedPawn!.col}',
        );
        debugPrint(
          '- Target position: row=${cellPosition.row}, col=${cellPosition.col}',
        );
        debugPrint(
          '- Is valid move: ${_playerComponent.validMoves.contains(cellPosition)}',
        );

        if (_playerComponent.validMoves.contains(cellPosition)) {
          debugPrint('- Moving to valid position');
          _handleMoveAttempt(cellPosition);
          _playerComponent.clearSelection();
          return;
        } else {
          debugPrint('- Invalid move, clearing selection');
          _playerComponent.clearSelection();
          return;
        }
      }
    }

    // If no player is selected, check for player selection first
    if (cellPosition != null) {
      final currentPlayerPosition = gameState.currentPlayer.position;
      final otherPlayerPosition = gameState.otherPlayer.position;

      debugPrint('Cell tap detected:');
      debugPrint(
        '- Cell position: row=${cellPosition.row}, col=${cellPosition.col}',
      );
      debugPrint(
        '- Current player position: row=${currentPlayerPosition.row}, col=${currentPlayerPosition.col}',
      );
      debugPrint(
        '- Other player position: row=${otherPlayerPosition.row}, col=${otherPlayerPosition.col}',
      );

      // Check if we're tapping on either player
      if (cellPosition == currentPlayerPosition ||
          cellPosition == otherPlayerPosition) {
        debugPrint('- Tapped on player at position');
        _handlePositionTap(cellPosition, gameState);
        return;
      }
    }

    // If we're not selecting a player or moving, check for wall placement
    if (wall != null) {
      debugPrint('Wall tap detected:');
      debugPrint(
        '- Wall position: row=${wall.position.row}, col=${wall.position.col}',
      );
      debugPrint('- Wall orientation: ${wall.orientation}');
      _handleWallTap(wall, gameState);
    } else if (cellPosition != null) {
      // If we're tapping on a cell (not a player), handle as a move
      debugPrint('Cell tap detected (not a player):');
      debugPrint(
        '- Cell position: row=${cellPosition.row}, col=${cellPosition.col}',
      );
      debugPrint(
        '- Is valid move: ${gameState.getValidMoves(gameState.currentPlayer.position).contains(cellPosition)}',
      );
      debugPrint('- Current player: ${gameState.currentPlayer.id}');
      debugPrint(
        '- Walls remaining: ${gameState.currentPlayer.wallsRemaining}',
      );

      _handlePositionTap(cellPosition, gameState);
    }
  }

  void _handlePositionTap(Position position, GameState gameState) {
    final currentPlayerPosition = gameState.currentPlayer.position;

    debugPrint('Position tap handling:');
    debugPrint(
      '- Current player position: row=${currentPlayerPosition.row}, col=${currentPlayerPosition.col}',
    );
    debugPrint('- Selected position: row=${position.row}, col=${position.col}');
    debugPrint(
      '- Is current player position: ${position == currentPlayerPosition}',
    );
    debugPrint(
      '- Is already selected: ${_playerComponent.selectedPawn == position}',
    );

    // Clear wall preview when tapping on a position
    wallComponent.clearPreview();

    if (position == currentPlayerPosition) {
      if (_playerComponent.selectedPawn == position) {
        debugPrint('- Deselecting current player');
        _playerComponent.clearSelection();
      } else {
        debugPrint('- Selecting current player');
        _playerComponent.selectedPawn = position;
        _playerComponent.validMoves = gameState.getValidMoves(position);
        debugPrint('- Valid moves: ${_playerComponent.validMoves.length}');
      }
    }
  }

  void _handleWallTap(Wall wall, GameState gameState) {
    final playerId = gameState.currentPlayer.id;

    debugPrint('Wall tap handling:');
    debugPrint('- Current player: $playerId');
    debugPrint('- Walls remaining: ${gameState.currentPlayer.wallsRemaining}');
    debugPrint(
      '- Wall position: row=${wall.position.row}, col=${wall.position.col}',
    );
    debugPrint('- Wall orientation: ${wall.orientation}');

    if (wallComponent.lastTappedWall == null ||
        wallComponent.lastTappedWall != wall) {
      wallComponent.lastTappedWall = wall;
      wallComponent.isValid = gameState.currentPlayer.hasWallsRemaining;
      // Update preview wall through controller
      if (_gameController != null) {
        _gameController!.add(SetPreviewWall(wall));
      }
      debugPrint('- Preview wall set');
    } else if (wallComponent.lastTappedWall == wall) {
      if (gameState.currentPlayer.hasWallsRemaining) {
        debugPrint('- Attempting to place wall');
        _handleWallPlaceAttempt(wall);
      } else {
        debugPrint('- Cannot place wall: No walls remaining');
      }
    } else {
      debugPrint('- Clearing wall preview');
      wallComponent.clearPreview();
      // Clear preview wall through controller
      if (_gameController != null) {
        _gameController!.add(SetPreviewWall(null));
      }
    }
  }

  void handleHover(Vector2 position) {
    if (_gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    final offset = Offset(position.x, position.y);
    final wall = wallComponent.getWallFromOffset(offset);
    if (wall != null) {
      wallComponent.lastTappedWall = wall;
      wallComponent.isValid = gameState.currentPlayer.hasWallsRemaining;
      // Update preview wall through controller
      _gameController!.add(SetPreviewWall(wall));
    } else {
      wallComponent.clearPreview();
      // Clear preview wall through controller
      _gameController!.add(SetPreviewWall(null));
    }
  }

  // Handle move attempts through controller if available
  void _handleMoveAttempt(Position newPosition) {
    if (_gameController != null) {
      _gameController!.add(MakePawnMove(newPosition));
    } else {
      // Fallback to direct callback
      onMoveAttempted?.call(newPosition);
    }
  }

  // Handle wall placement attempts through controller if available
  void _handleWallPlaceAttempt(Wall wall) {
    if (_gameController != null) {
      _gameController!.add(PlaceWall(wall));
    } else {
      // Fallback to direct callback
      onWallPlaceAttempted?.call(wall);
    }
  }

  Position? _getPositionFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final cellCol = (localX / (cellSizeNotifier.value + _cellSpacing)).floor();
    final cellRow = (localY / (cellSizeNotifier.value + _cellSpacing)).floor();

    debugPrint('Cell position calculation:');
    debugPrint('- Local coordinates: ($localX, $localY)');
    debugPrint('- Cell size: ${cellSizeNotifier.value}');
    debugPrint('- Cell spacing: $_cellSpacing');
    debugPrint('- Calculated cell: row=$cellRow, col=$cellCol');

    if (cellRow >= 0 &&
        cellRow < GameConstants.boardSize &&
        cellCol >= 0 &&
        cellCol < GameConstants.boardSize) {
      return Position(cellRow, cellCol);
    }
    return null;
  }
}
