import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '/flame/components/player_components.dart';
import '/flame/services/sounds.dart';
import '/theme.dart';
import '../core/constants.dart';
import '../models/game_state.dart';
import 'wall_component.dart';

final cellSizeNotifier = ValueNotifier<double>(40);

class BoardComponent extends PositionComponent {
  GameState _gameState;
  bool enableSound = true;
  bool showValidMoves = true;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;

  late final WallComponent wallComponent;
  late final PlayerComponent _playerComponent;

  static const double _boardPadding = GameConstants.boardPadding;
  static const double _cellSpacing = GameConstants.cellSpacing;

  BoardComponent(this._gameState) {
    _playerComponent = PlayerComponent(_gameState);
    wallComponent = WallComponent(_gameState);
    add(wallComponent);
    add(_playerComponent);
  }

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;

    ///players
    _playerComponent.gameState = newGameState;
    _playerComponent.validMoves.clear();
    _playerComponent.selectedPawn = null;
    _playerComponent.showValidMoves = showValidMoves;

    ///walls
    _gameState.previewWall = null;
    wallComponent.lastTappedWall = null;
    wallComponent.gameState = newGameState;
  }

  @override
  void render(Canvas canvas) {
    _drawGrid(canvas);
  }

  void _drawGrid(Canvas canvas) {
    final lightPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF2C3E50) // Dark mode light cell
          : const Color(GameConstants.lightCellColor)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF1A2530) // Dark mode dark cell
          : const Color(GameConstants.darkCellColor)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isDarkModeNotifier.value
          ? const Color(0xFF34495E) // Dark mode border
          : const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        final rect = Rect.fromLTWH(
          _boardPadding + col * (cellSizeNotifier.value + _cellSpacing),
          _boardPadding + row * (cellSizeNotifier.value + _cellSpacing),
          cellSizeNotifier.value,
          cellSizeNotifier.value,
        );

        // Checkerboard pattern
        final isLight = (row + col) % 2 == 0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          isLight ? lightPaint : darkPaint,
        );

        // Cell border
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          borderPaint,
        );
      }
    }
  }

  void handleTap(Vector2 position) {
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
          onMoveAttempted?.call(cellPosition);
          GameSounds.triggerFeedback(
            soundKey: _gameState.currentPlayer.id == 1 ? 'move_p1' : 'move_p2',
          );
          _playerComponent.selectedPawn = null;
          _playerComponent.validMoves.clear();
          return;
        } else {
          debugPrint('- Invalid move, clearing selection');
          _playerComponent.selectedPawn = null;
          _playerComponent.validMoves.clear();
          return;
        }
      }
    }

    // If no player is selected, check for player selection first
    if (cellPosition != null) {
      final currentPlayerPosition = _gameState.currentPlayer.position;
      final otherPlayerPosition = _gameState.players
          .firstWhere((player) => player.id != _gameState.currentPlayer.id)
          .position;

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
      if (_gameState.players.any((player) => player.position == cellPosition)) {
        debugPrint('- Tapped on player at position');
        _handlePositionTap(cellPosition);
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
      _handleWallTap(wall);
    } else if (cellPosition != null) {
      // If we're tapping on a cell (not a player), handle as a move
      debugPrint('Cell tap detected (not a player):');
      debugPrint(
        '- Cell position: row=${cellPosition.row}, col=${cellPosition.col}',
      );
      debugPrint(
        '- Is valid move: ${_gameState.getValidMoves(_gameState.currentPlayer.position).contains(cellPosition)}',
      );
      debugPrint('- Current player: ${_gameState.currentPlayer.id}');
      debugPrint(
        '- Walls remaining: ${_gameState.currentPlayer.wallsRemaining}',
      );

      _handlePositionTap(cellPosition);
    }
  }

  void _handlePositionTap(Position position) {
    final currentPlayerPosition = _gameState.currentPlayer.position;

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
    _gameState.previewWall = null;
    wallComponent.lastTappedWall = null;
    _gameState.previewWall = null;

    if (position == currentPlayerPosition) {
      if (_playerComponent.selectedPawn == position) {
        debugPrint('- Deselecting current player');
        _playerComponent.selectedPawn = null;
        _playerComponent.validMoves.clear();
      } else {
        debugPrint('- Selecting current player');
        _playerComponent.selectedPawn = position;
        _playerComponent.validMoves = _gameState.getValidMoves(position);
        debugPrint('- Valid moves: ${_playerComponent.validMoves.length}');
      }
    }
  }

  void _handleWallTap(Wall wall) {
    final playerId = _gameState.currentPlayer.id;

    debugPrint('Wall tap handling:');
    debugPrint('- Current player: $playerId');
    debugPrint('- Walls remaining: ${_gameState.currentPlayer.wallsRemaining}');
    debugPrint(
      '- Wall position: row=${wall.position.row}, col=${wall.position.col}',
    );
    debugPrint('- Wall orientation: ${wall.orientation}');

    if (_gameState.previewWall == null || _gameState.previewWall != wall) {
      _gameState.previewWall = wall;
      wallComponent.lastTappedWall = wall;
      _gameState.previewWall = wall;
      wallComponent.isValid = _gameState.currentPlayer.hasWallsRemaining;
      debugPrint('- Preview wall set');
    } else if (_gameState.previewWall == wall &&
        wallComponent.lastTappedWall == wall) {
      if (_gameState.currentPlayer.hasWallsRemaining) {
        debugPrint('- Attempting to place wall');

        onWallPlaceAttempted?.call(wall);
      } else {
        debugPrint('- Cannot place wall: No walls remaining');
      }
    } else {
      debugPrint('- Clearing wall preview');
      _gameState.previewWall = null;
      wallComponent.lastTappedWall = null;
      _gameState.previewWall = null;
    }
  }

  void handleHover(Vector2 position) {
    final offset = Offset(position.x, position.y);
    final wall = wallComponent.getWallFromOffset(offset);
    if (wall != null) {
      _gameState.previewWall = wall;
      wallComponent.isValid = _gameState.currentPlayer.hasWallsRemaining;
    } else {
      _gameState.previewWall = null;
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
