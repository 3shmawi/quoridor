import 'package:audioplayers/audioplayers.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../flame/constants.dart';
import '../flame/models/game_state.dart';

class BoardComponent extends PositionComponent {
  GameState _gameState;
  bool showValidMoves = true;
  bool enableSound = true;
  bool enableVibration = true;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;

  Position? _selectedPawn;
  List<Position> _validMoves = [];
  Position? _hoverPosition;
  Wall? _previewWall;
  Wall? _lastTappedWall;

  static const double _cellSize = GameConstants.cellSize;
  static const double _wallThickness = GameConstants.wallThickness;
  static const double _boardPadding = 50.0;

  final AudioPlayer _audioPlayer = AudioPlayer();

  final Map<String, String> _soundAssets = {
    'move_p1': 'sounds/move_player1.wav',
    'move_p2': 'sounds/move_player2.wav',
    'wall_p1': 'sounds/wall_player1.wav',
    'wall_p2': 'sounds/wall_player2.wav',
    'win': 'sounds/win.wav',
  };

  BoardComponent(this._gameState) {
    size = Vector2(
      GameConstants.boardSize * _cellSize + _boardPadding * 2,
      GameConstants.boardSize * _cellSize + _boardPadding * 2,
    );
  }

  @override
  void onRemove() {
    _audioPlayer.dispose();
    super.onRemove();
  }

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;
    _selectedPawn = null;
    _validMoves.clear();
    _hoverPosition = null;
    _previewWall = null;
    _lastTappedWall = null;
  }

  @override
  void render(Canvas canvas) {
    _drawBackground(canvas);
    _drawGrid(canvas);
    _drawValidMoves(canvas);
    _drawWalls(canvas);
    _drawPreviewWall(canvas);
    _drawPawns(canvas);
    _drawSelection(canvas);
    _drawGoalLines(canvas);
  }

  void _triggerFeedback({String? soundKey}) async {
    if (enableSound && soundKey != null && _soundAssets.containsKey(soundKey)) {
      try {
        await _audioPlayer.play(AssetSource(_soundAssets[soundKey]!));
      } catch (e) {
        print('Error playing sound: \$e');
      }
    }
  }

  void handleTap(Vector2 position) {
    final offset = Offset(position.x, position.y);
    final tappedPosition = _getPositionFromOffset(offset);
    final tappedWall = _getWallFromOffset(offset);

    if (tappedPosition != null) {
      _handlePositionTap(tappedPosition);
    } else if (tappedWall != null) {
      _handleWallTap(tappedWall);
    }
  }

  void _handlePositionTap(Position position) {
    _previewWall = null;
    _lastTappedWall = null;

    final currentPlayerPosition = _gameState.currentPlayer.position;
    final playerId = _gameState.currentPlayer.id;

    if (position == currentPlayerPosition) {
      if (_selectedPawn == position) {
        _selectedPawn = null;
        _validMoves.clear();
      } else {
        _selectedPawn = position;
        _validMoves = _gameState.getValidMoves(position);
      }
    } else if (_selectedPawn != null && _validMoves.contains(position)) {
      onMoveAttempted?.call(position);
      _triggerFeedback(soundKey: playerId == 1 ? 'move_p1' : 'move_p2');
      _selectedPawn = null;
      _validMoves.clear();
    } else {
      _selectedPawn = null;
      _validMoves.clear();
    }
  }

  void _handleWallTap(Wall wall) {
    final playerId = _gameState.currentPlayer.id;

    if (_previewWall == null || _previewWall != wall) {
      _previewWall = wall;
      _lastTappedWall = wall;
    } else if (_previewWall == wall && _lastTappedWall == wall) {
      if (_gameState.currentPlayer.hasWallsRemaining) {
        onWallPlaceAttempted?.call(wall);
        _triggerFeedback(soundKey: playerId == 1 ? 'wall_p1' : 'wall_p2');
        _previewWall = null;
        _lastTappedWall = null;
      }
    } else {
      _previewWall = null;
      _lastTappedWall = null;
    }
  }

  void handleHover(Vector2 position) {
    final offset = Offset(position.x, position.y);
    _hoverPosition = _getPositionFromOffset(offset);
    _previewWall = _getWallFromOffset(offset);
  }

  void playWinSound() {
    _triggerFeedback(soundKey: 'win');
  }

  // _draw and helper methods remain unchanged

  void _drawBackground(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFFF1F4F8)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.x, size.y),
        const Radius.circular(12),
      ),
      paint,
    );
  }

  void _drawGrid(Canvas canvas) {
    final lightPaint = Paint()
      ..color = const Color(GameConstants.lightCellColor)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = const Color(GameConstants.darkCellColor)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        final rect = Rect.fromLTWH(
          _boardPadding + col * _cellSize,
          _boardPadding + row * _cellSize,
          _cellSize,
          _cellSize,
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

  void _drawValidMoves(Canvas canvas) {
    if (!showValidMoves || _validMoves.isEmpty) return;

    final paint = Paint()
      ..color = const Color(GameConstants.validMoveColor).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = const Color(GameConstants.validMoveColor)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (final position in _validMoves) {
      final center = _getCellCenter(position);

      canvas.drawCircle(center, _cellSize * 0.3, paint);
      canvas.drawCircle(center, _cellSize * 0.3, borderPaint);
    }
  }

  void _drawWalls(Canvas canvas) {
    final wallPaint = Paint()
      ..color = const Color(GameConstants.wallColor)
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = const Color(GameConstants.wallColor).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (final wall in _gameState.walls) {
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
    if (_previewWall == null) return;

    final isValid = _gameState.currentPlayer.hasWallsRemaining;
    final rect = _getWallRect(_previewWall!);

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
          ? const Color(GameConstants.wallColor).withValues(alpha: 0.5)
          : const Color(0xFFFF0000).withValues(alpha: 0.5)
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

  void _drawPawns(Canvas canvas) {
    _drawPawn(canvas, _gameState.player1.position, 1);
    _drawPawn(canvas, _gameState.player2.position, 2);
  }

  void _drawPawn(Canvas canvas, Position position, int playerId) {
    final center = _getCellCenter(position);
    final isSelected = _selectedPawn == position;
    final radius = _cellSize * 0.35;

    final color = playerId == 1
        ? const Color(GameConstants.player1Color)
        : const Color(GameConstants.player2Color);

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
    if (_hoverPosition == null) return;

    final hoverPaint = Paint()
      ..color = const Color(GameConstants.validMoveColor).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromLTWH(
      _boardPadding + _hoverPosition!.col * _cellSize,
      _boardPadding + _hoverPosition!.row * _cellSize,
      _cellSize,
      _cellSize,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      hoverPaint,
    );
  }

  void _drawGoalLines(Canvas canvas) {
    final player1GoalPaint = Paint()
      ..color = const Color(GameConstants.player1Color).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final player2GoalPaint = Paint()
      ..color = const Color(GameConstants.player2Color).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // Player 1 goal (bottom row)
    canvas.drawRect(
      Rect.fromLTWH(
        _boardPadding,
        _boardPadding + (GameConstants.boardSize - 1) * _cellSize,
        GameConstants.boardSize * _cellSize,
        _cellSize,
      ),
      player1GoalPaint,
    );

    // Player 2 goal (top row)
    canvas.drawRect(
      Rect.fromLTWH(
        _boardPadding,
        _boardPadding,
        GameConstants.boardSize * _cellSize,
        _cellSize,
      ),
      player2GoalPaint,
    );
  }

  Offset _getCellCenter(Position position) {
    return Offset(
      _boardPadding + position.col * _cellSize + _cellSize / 2,
      _boardPadding + position.row * _cellSize + _cellSize / 2,
    );
  }

  Rect _getWallRect(Wall wall) {
    if (wall.orientation == WallOrientation.horizontal) {
      return Rect.fromLTWH(
        _boardPadding + wall.position.col * _cellSize,
        _boardPadding + wall.position.row * _cellSize - _wallThickness / 2,
        _cellSize * 2,
        _wallThickness,
      );
    } else {
      return Rect.fromLTWH(
        _boardPadding + wall.position.col * _cellSize - _wallThickness / 2,
        _boardPadding + wall.position.row * _cellSize,
        _wallThickness,
        _cellSize * 2,
      );
    }
  }

  Position? _getPositionFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final col = (localX / _cellSize).floor();
    final row = (localY / _cellSize).floor();

    print('Calculated position - row: $row, col: $col'); // Debug log

    if (row < 0 ||
        row >= GameConstants.boardSize ||
        col < 0 ||
        col >= GameConstants.boardSize) {
      return null;
    }

    return Position(row, col);
  }

  Wall? _getWallFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final cellCol = (localX / _cellSize).floor();
    final cellRow = (localY / _cellSize).floor();

    final cellX = localX % _cellSize;
    final cellY = localY % _cellSize;

    // Check if click is near cell edge for wall placement
    const edgeThreshold =
        _cellSize * 0.6; // Increased threshold for easier wall placement

    print(
      'Wall placement check - cellX: $cellX, cellY: $cellY, threshold: $edgeThreshold',
    ); // Debug log

    // Check horizontal walls
    if (cellY < edgeThreshold && cellRow > 0) {
      print(
        'Horizontal wall above at row: ${cellRow}, col: $cellCol',
      ); // Debug log
      return Wall(Position(cellRow, cellCol), WallOrientation.horizontal);
    } else if (cellY > _cellSize - edgeThreshold &&
        cellRow < GameConstants.boardSize - 1) {
      print(
        'Horizontal wall below at row: ${cellRow + 1}, col: $cellCol',
      ); // Debug log
      return Wall(Position(cellRow + 1, cellCol), WallOrientation.horizontal);
    }

    // Check vertical walls
    if (cellX < edgeThreshold && cellCol > 0) {
      print(
        'Vertical wall left at row: $cellRow, col: ${cellCol}',
      ); // Debug log
      return Wall(Position(cellRow, cellCol), WallOrientation.vertical);
    } else if (cellX > _cellSize - edgeThreshold &&
        cellCol < GameConstants.boardSize - 1) {
      print(
        'Vertical wall right at row: $cellRow, col: ${cellCol + 1}',
      ); // Debug log
      return Wall(Position(cellRow, cellCol + 1), WallOrientation.vertical);
    }

    return null;
  }
}
