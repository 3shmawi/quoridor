import 'package:audioplayers/audioplayers.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/theme.dart';

import '../flame/constants.dart';
import '../flame/models/game_state.dart';
import 'wall_component.dart';

class BoardComponent extends PositionComponent
    with HasGameReference<QuoridorGame> {
  GameState _gameState;
  bool showValidMoves = true;
  bool enableSound = true;
  bool enableVibration = true;
  WallOrientation _wallOrientation = WallOrientation.horizontal;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;
  Function(Position)? onWallTapped;

  Position? _selectedPawn;
  List<Position> _validMoves = [];
  Position? _hoverPosition;
  Wall? _previewWall;
  Wall? _lastTappedWall;
  Wall? get previewWall => _previewWall;
  set previewWall(Wall? wall) {
    _previewWall = wall;
    _wallComponent.previewWall = wall;
  }

  late final WallComponent _wallComponent;

  static const double _cellSize = GameConstants.cellSize;
  static const double _wallThickness = GameConstants.wallThickness;
  static const double _boardPadding = GameConstants.boardPadding;
  static const double cellSpacing = GameConstants.cellSpacing;

  final AudioPlayer _audioPlayer = AudioPlayer();

  final Map<String, String> _soundAssets = {
    'move_p1': 'sounds/move_player1.wav',
    'move_p2': 'sounds/move_player2.wav',
    'wall_p1': 'sounds/wall_player1.wav',
    'wall_p2': 'sounds/wall_player2.wav',
    'win': 'sounds/win.wav',
  };

  BoardComponent(this._gameState) {
    if (game.isInitialized) {
      size = game.size;
    }

    _wallComponent = WallComponent(_gameState);
    add(_wallComponent);
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
    _wallComponent.gameState = newGameState;
  }

  @override
  void render(Canvas canvas) {
    _drawGrid(canvas);
    _drawValidMoves(canvas);
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
    final cellPosition = _getPositionFromOffset(offset);
    final wall = _getWallFromOffset(offset);

    print('Tap detected at screen position: (${position.x}, ${position.y})');
    print('Converted to board offset: (${offset.dx}, ${offset.dy})');

    // If a player is selected, prioritize movement
    if (_selectedPawn != null) {
      if (cellPosition != null) {
        print('Player selected, checking move:');
        print(
          '- Selected pawn position: row=${_selectedPawn!.row}, col=${_selectedPawn!.col}',
        );
        print(
          '- Target position: row=${cellPosition.row}, col=${cellPosition.col}',
        );
        print('- Is valid move: ${_validMoves.contains(cellPosition)}');

        if (_validMoves.contains(cellPosition)) {
          print('- Moving to valid position');
          onMoveAttempted?.call(cellPosition);
          _triggerFeedback(
            soundKey: _gameState.currentPlayer.id == 1 ? 'move_p1' : 'move_p2',
          );
          _selectedPawn = null;
          _validMoves.clear();
          return;
        } else {
          print('- Invalid move, clearing selection');
          _selectedPawn = null;
          _validMoves.clear();
          return;
        }
      }
    }

    // If no player is selected, check for player selection first
    if (cellPosition != null) {
      final currentPlayerPosition = _gameState.currentPlayer.position;
      final otherPlayerPosition = _gameState.otherPlayer.position;

      print('Cell tap detected:');
      print(
        '- Cell position: row=${cellPosition.row}, col=${cellPosition.col}',
      );
      print(
        '- Current player position: row=${currentPlayerPosition.row}, col=${currentPlayerPosition.col}',
      );
      print(
        '- Other player position: row=${otherPlayerPosition.row}, col=${otherPlayerPosition.col}',
      );

      // Check if we're tapping on either player
      if (cellPosition == currentPlayerPosition ||
          cellPosition == otherPlayerPosition) {
        print('- Tapped on player at position');
        _handlePositionTap(cellPosition);
        return;
      }
    }

    // If we're not selecting a player or moving, check for wall placement
    if (wall != null) {
      print('Wall tap detected:');
      print(
        '- Wall position: row=${wall.position.row}, col=${wall.position.col}',
      );
      print('- Wall orientation: ${wall.orientation}');
      _handleWallTap(wall);
    } else if (cellPosition != null) {
      // If we're tapping on a cell (not a player), handle as a move
      print('Cell tap detected (not a player):');
      print(
        '- Cell position: row=${cellPosition.row}, col=${cellPosition.col}',
      );
      print(
        '- Is valid move: ${_gameState.getValidMoves(_gameState.currentPlayer.position).contains(cellPosition)}',
      );
      print('- Current player: ${_gameState.currentPlayer.id}');
      print('- Walls remaining: ${_gameState.currentPlayer.wallsRemaining}');

      _handlePositionTap(cellPosition);
    }
  }

  void _handlePositionTap(Position position) {
    final currentPlayerPosition = _gameState.currentPlayer.position;
    final playerId = _gameState.currentPlayer.id;

    print('Position tap handling:');
    print(
      '- Current player position: row=${currentPlayerPosition.row}, col=${currentPlayerPosition.col}',
    );
    print('- Selected position: row=${position.row}, col=${position.col}');
    print('- Is current player position: ${position == currentPlayerPosition}');
    print('- Is already selected: ${_selectedPawn == position}');

    // Clear wall preview when tapping on a position
    _previewWall = null;
    _lastTappedWall = null;
    _wallComponent.previewWall = null;

    if (position == currentPlayerPosition) {
      if (_selectedPawn == position) {
        print('- Deselecting current player');
        _selectedPawn = null;
        _validMoves.clear();
      } else {
        print('- Selecting current player');
        _selectedPawn = position;
        _validMoves = _gameState.getValidMoves(position);
        print('- Valid moves: ${_validMoves.length}');
      }
    }
  }

  void _handleWallTap(Wall wall) {
    final playerId = _gameState.currentPlayer.id;

    print('Wall tap handling:');
    print('- Current player: $playerId');
    print('- Walls remaining: ${_gameState.currentPlayer.wallsRemaining}');
    print(
      '- Wall position: row=${wall.position.row}, col=${wall.position.col}',
    );
    print('- Wall orientation: ${wall.orientation}');

    if (_previewWall == null || _previewWall != wall) {
      _previewWall = Wall(wall.position, _wallOrientation);
      _lastTappedWall = wall;
      _wallComponent.previewWall = _previewWall;
      _wallComponent.isValid = _gameState.currentPlayer.hasWallsRemaining;
      print('- Preview wall set');

      // Notify game page about the last tapped wall position
      if (onWallTapped != null) {
        onWallTapped!(wall.position);
      }
    } else if (_previewWall == wall && _lastTappedWall == wall) {
      if (_gameState.currentPlayer.hasWallsRemaining) {
        print('- Attempting to place wall');
        onWallPlaceAttempted?.call(_previewWall!);
        _triggerFeedback(soundKey: playerId == 1 ? 'wall_p1' : 'wall_p2');
        _previewWall = null;
        _lastTappedWall = null;
        _wallComponent.previewWall = null;
      } else {
        print('- Cannot place wall: No walls remaining');
      }
    } else {
      print('- Clearing wall preview');
      _previewWall = null;
      _lastTappedWall = null;
      _wallComponent.previewWall = null;
    }
  }

  void handleHover(Vector2 position) {
    final offset = Offset(position.x, position.y);
    _hoverPosition = _getPositionFromOffset(offset);
    final wall = _getWallFromOffset(offset);
    if (wall != null) {
      _wallComponent.previewWall = wall;
      _wallComponent.isValid = _gameState.currentPlayer.hasWallsRemaining;
    } else {
      _wallComponent.previewWall = null;
    }
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

    final cellSpacing = 4.0; // Space between cells

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        final rect = Rect.fromLTWH(
          _boardPadding + col * (_cellSize + cellSpacing),
          _boardPadding + row * (_cellSize + cellSpacing),
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
      ..color = const Color(GameConstants.validMoveColor).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    for (final position in _validMoves) {
      final rect = Rect.fromLTWH(
        _boardPadding + position.col * (_cellSize + cellSpacing),
        _boardPadding + position.row * (_cellSize + cellSpacing),
        _cellSize,
        _cellSize,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  void _drawPawns(Canvas canvas) {
    // Draw player 1
    _drawPawn(
      canvas,
      _gameState.player1.position,
      const Color(GameConstants.player1Color),
      _gameState.player1.id == _gameState.currentPlayerId,
      _selectedPawn == _gameState.player1.position,
    );

    // Draw player 2
    _drawPawn(
      canvas,
      _gameState.player2.position,
      const Color(GameConstants.player2Color),
      _gameState.player2.id == _gameState.currentPlayerId,
      _selectedPawn == _gameState.player2.position,
    );
  }

  void _drawPawn(
    Canvas canvas,
    Position position,
    Color color,
    bool isCurrentPlayer,
    bool isSelected,
  ) {
    final center = _getCellCenter(position);
    final radius = _cellSize * 0.4;

    // Draw shadow
    canvas.drawCircle(
      Offset(center.dx + 2, center.dy + 2),
      radius,
      Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );

    // Draw pawn
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    // Draw border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = isCurrentPlayer ? Colors.white : Colors.black.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Draw highlight for current player
    if (isCurrentPlayer) {
      canvas.drawCircle(
        center,
        radius + 4,
        Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    // Draw selection highlight
    if (isSelected) {
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = const Color(GameConstants.validMoveColor)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }

    // Draw player number
    final playerNumber = position == _gameState.player1.position ? '1' : '2';
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: radius * 1.2,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          color: Colors.black.withOpacity(0.5),
          offset: const Offset(1, 1),
          blurRadius: 2,
        ),
      ],
    );

    final textSpan = TextSpan(text: playerNumber, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
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
    if (_selectedPawn != null) {
      final paint = Paint()
        ..color = const Color(GameConstants.validMoveColor).withOpacity(0.3)
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(
        _boardPadding + _selectedPawn!.col * (_cellSize + cellSpacing),
        _boardPadding + _selectedPawn!.row * (_cellSize + cellSpacing),
        _cellSize,
        _cellSize,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  void _drawGoalLines(Canvas canvas) {
    final player1GoalPaint = Paint()
      ..color = const Color(GameConstants.player1Color).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = GameConstants.goalLineThickness;

    final player2GoalPaint = Paint()
      ..color = const Color(GameConstants.player2Color).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = GameConstants.goalLineThickness;

    // Player 1 goal (bottom row)
    final p1StartX = _boardPadding;
    final p1EndX =
        _boardPadding +
        (GameConstants.boardSize - 1) *
            (_cellSize + GameConstants.cellSpacing) +
        _cellSize;
    final p1Y =
        _boardPadding +
        (GameConstants.boardSize - 1) *
            (_cellSize + GameConstants.cellSpacing) +
        _cellSize;

    canvas.drawLine(
      Offset(p1StartX, p1Y),
      Offset(p1EndX, p1Y),
      player1GoalPaint,
    );

    // Player 2 goal (top row)
    final p2StartX = _boardPadding;
    final p2EndX =
        _boardPadding +
        (GameConstants.boardSize - 1) *
            (_cellSize + GameConstants.cellSpacing) +
        _cellSize;
    final p2Y = _boardPadding;

    canvas.drawLine(
      Offset(p2StartX, p2Y),
      Offset(p2EndX, p2Y),
      player2GoalPaint,
    );
  }

  Offset _getCellCenter(Position position) {
    return Offset(
      _boardPadding + position.col * (_cellSize + cellSpacing) + _cellSize / 2,
      _boardPadding + position.row * (_cellSize + cellSpacing) + _cellSize / 2,
    );
  }

  Position? _getPositionFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final cellCol = (localX / (_cellSize + cellSpacing)).floor();
    final cellRow = (localY / (_cellSize + cellSpacing)).floor();

    print('Cell position calculation:');
    print('- Local coordinates: ($localX, $localY)');
    print('- Cell size: $_cellSize');
    print('- Cell spacing: $cellSpacing');
    print('- Calculated cell: row=$cellRow, col=$cellCol');

    if (cellRow >= 0 &&
        cellRow < GameConstants.boardSize &&
        cellCol >= 0 &&
        cellCol < GameConstants.boardSize) {
      return Position(cellRow, cellCol);
    }
    return null;
  }

  Wall? _getWallFromOffset(Offset offset) {
    final localX = offset.dx - _boardPadding;
    final localY = offset.dy - _boardPadding;

    if (localX < 0 || localY < 0) return null;

    final cellCol = (localX / (_cellSize + cellSpacing)).floor();
    final cellRow = (localY / (_cellSize + cellSpacing)).floor();

    final cellX = localX % (_cellSize + cellSpacing);
    final cellY = localY % (_cellSize + cellSpacing);

    // Increased threshold for easier wall placement
    const edgeThreshold = 0.4; // 40% of cell size for wall placement
    final threshold = _cellSize * edgeThreshold;

    print('Wall position calculation:');
    print('- Local coordinates: ($localX, $localY)');
    print('- Cell coordinates: ($cellX, $cellY)');
    print('- Cell position: row=$cellRow, col=$cellCol');
    print('- Edge threshold: $threshold');

    // Check horizontal walls
    if (cellY < threshold && cellRow > 0) {
      print(
        '- Detected horizontal wall above at row: ${cellRow}, col: $cellCol',
      );
      return Wall(Position(cellRow, cellCol), WallOrientation.horizontal);
    } else if (cellY > _cellSize - threshold &&
        cellRow < GameConstants.boardSize - 1) {
      print(
        '- Detected horizontal wall below at row: ${cellRow + 1}, col: $cellCol',
      );
      return Wall(Position(cellRow + 1, cellCol), WallOrientation.horizontal);
    }

    // Check vertical walls
    if (cellX < threshold && cellCol > 0) {
      print('- Detected vertical wall left at row: $cellRow, col: ${cellCol}');
      return Wall(Position(cellRow, cellCol), WallOrientation.vertical);
    } else if (cellX > _cellSize - threshold &&
        cellCol < GameConstants.boardSize - 1) {
      print(
        '- Detected vertical wall right at row: $cellRow, col: ${cellCol + 1}',
      );
      return Wall(Position(cellRow, cellCol + 1), WallOrientation.vertical);
    }

    return null;
  }

  void setWallOrientation(WallOrientation orientation) {
    _wallOrientation = orientation;
    if (_previewWall != null) {
      _previewWall = Wall(_previewWall!.position, orientation);
      _wallComponent.previewWall = _previewWall;
    }
  }
}
