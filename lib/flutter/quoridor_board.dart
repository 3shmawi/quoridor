import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../models/player.dart';

class QuoridorBoard extends StatefulWidget {
  final GameState gameState;
  final Function(Position)? onMoveAttempted;
  final Function(Wall)? onWallPlaceAttempted;
  final bool showValidMoves;

  const QuoridorBoard({
    super.key,
    required this.gameState,
    this.onMoveAttempted,
    this.onWallPlaceAttempted,
    this.showValidMoves = true,
  });

  @override
  State<QuoridorBoard> createState() => _QuoridorBoardState();
}

class _QuoridorBoardState extends State<QuoridorBoard> {
  Position? _selectedPawn;
  List<Position> _validMoves = [];
  Position? _hoverPosition;
  Wall? _previewWall;

  static const double _cellSize = 40.0;
  static const double _wallThickness = 6.0;
  static const double _boardPadding = 20.0;

  @override
  void didUpdateWidget(QuoridorBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameState != widget.gameState) {
      _selectedPawn = null;
      _validMoves.clear();
      _hoverPosition = null;
      _previewWall = null;
    }
  }

  void _selectPawn(Position position) {
    if (widget.gameState.currentPlayer.position == position) {
      setState(() {
        _selectedPawn = position;
        _validMoves = _getValidMoves(position);
      });
      HapticFeedback.selectionClick();
    }
  }

  void _attemptMove(Position position) {
    if (_validMoves.contains(position)) {
      widget.onMoveAttempted?.call(position);
      setState(() {
        _selectedPawn = null;
        _validMoves.clear();
      });
      HapticFeedback.lightImpact();
    }
  }

  void _attemptWallPlace(Position position, bool isHorizontal) {
    final wall = Wall(
      position,
      isHorizontal ? WallOrientation.horizontal : WallOrientation.vertical,
    );

    widget.onWallPlaceAttempted?.call(wall);
    setState(() {
      _previewWall = null;
    });
    HapticFeedback.mediumImpact();
  }

  List<Position> _getValidMoves(Position from) {
    List<Position> moves = [];

    // Basic adjacency moves
    final directions = [
      Position(0, 1),  // Down
      Position(0, -1), // Up
      Position(1, 0),  // Right
      Position(-1, 0), // Left
    ];

    for (final dir in directions) {
      final newPos = Position(from.row + dir.row, from.col + dir.col);

      if (_isValidPosition(newPos) && !_isBlockedByWall(from, newPos)) {
        // Check if there's another pawn at this position
        if (_isPawnAt(newPos)) {
          // Try to jump over
          final jumpPos = Position(newPos.row + dir.row, newPos.col + dir.col);
          if (_isValidPosition(jumpPos) && !_isBlockedByWall(newPos, jumpPos) && !_isPawnAt(jumpPos)) {
            moves.add(jumpPos);
          } else {
            // Diagonal moves if can't jump straight
            final diagDir1 = Position(dir.col, dir.row);
            final diagDir2 = Position(-dir.col, -dir.row);

            for (final diagDir in [diagDir1, diagDir2]) {
              final diagPos = Position(newPos.row + diagDir.row, newPos.col + diagDir.col);
              if (_isValidPosition(diagPos) && !_isBlockedByWall(newPos, diagPos) && !_isPawnAt(diagPos)) {
                moves.add(diagPos);
              }
            }
          }
        } else {
          moves.add(newPos);
        }
      }
    }

    return moves;
  }

  bool _isValidPosition(Position pos) {
    return pos.row >= 0 && pos.row < GameConstants.boardSize &&
        pos.col >= 0 && pos.col < GameConstants.boardSize;
  }

  bool _isPawnAt(Position pos) {
    return widget.gameState.player1.position == pos ||
        widget.gameState.player2.position == pos;
  }

  bool _isBlockedByWall(Position from, Position to) {
    // Check if there's a wall blocking the path
    for (final wall in widget.gameState.walls) {
      if (_wallBlocksPath(wall, from, to)) {
        return true;
      }
    }
    return false;
  }

  bool _wallBlocksPath(Wall wall, Position from, Position to) {
    if (wall.orientation == WallOrientation.horizontal) {
      // Horizontal wall blocks vertical movement
      if (from.row == to.row && (from.col - to.col).abs() == 1) {
        final wallCol = wall.position.col;
        final pathCol = [from.col, to.col].reduce((a, b) => a > b ? a : b);

        if (wallCol == pathCol &&
            wall.position.row <= from.row &&
            from.row < wall.position.row + 2) {
          return true;
        }
      }
    } else {
      // Vertical wall blocks horizontal movement
      if (from.col == to.col && (from.row - to.row).abs() == 1) {
        final wallRow = wall.position.row;
        final pathRow = [from.row, to.row].reduce((a, b) => a > b ? a : b);

        if (wallRow == pathRow &&
            wall.position.col <= from.col &&
            from.col < wall.position.col + 2) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final boardSize = GameConstants.boardSize * _cellSize + _boardPadding * 2;

    return Container(
      width: boardSize,
      height: boardSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(_boardPadding),
        child: CustomPaint(
          painter: BoardPainter(
            gameState: widget.gameState,
            selectedPawn: _selectedPawn,
            validMoves: widget.showValidMoves ? _validMoves : [],
            hoverPosition: _hoverPosition,
            previewWall: _previewWall,
            theme: Theme.of(context),
          ),
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details.localPosition),
            onPanUpdate: (details) => _handleHover(details.localPosition),
            child: Container(),
          ),
        ),
      ),
    );
  }

  void _handleTap(Offset localPosition) {
    final cellRow = (localPosition.dy / _cellSize).floor();
    final cellCol = (localPosition.dx / _cellSize).floor();

    if (cellRow >= 0 && cellRow < GameConstants.boardSize &&
        cellCol >= 0 && cellCol < GameConstants.boardSize) {
      final position = Position(cellRow, cellCol);

      if (_selectedPawn != null && _validMoves.contains(position)) {
        _attemptMove(position);
      } else if (_isPawnAt(position)) {
        _selectPawn(position);
      } else {
        // Try wall placement
        _tryWallPlacement(localPosition);
      }
    }
  }

  void _handleHover(Offset localPosition) {
    final cellRow = (localPosition.dy / _cellSize).floor();
    final cellCol = (localPosition.dx / _cellSize).floor();

    if (cellRow >= 0 && cellRow < GameConstants.boardSize &&
        cellCol >= 0 && cellCol < GameConstants.boardSize) {
      setState(() {
        _hoverPosition = Position(cellRow, cellCol);
      });
    }
  }

  void _tryWallPlacement(Offset localPosition) {
    // Determine if we're closer to a horizontal or vertical wall position
    final cellCol = localPosition.dx / _cellSize;
    final cellRow = localPosition.dy / _cellSize;

    final fracCol = cellCol - cellCol.floor();
    final fracRow = cellRow - cellRow.floor();

    // If we're near the edge between cells, try to place a wall
    if (fracCol > 0.8 || fracRow > 0.8) {
      final wallCol = fracCol > 0.8 ? cellCol.floor() : cellCol.floor() - 1;
      final wallRow = fracRow > 0.8 ? cellRow.floor() : cellRow.floor() - 1;

      if (wallCol >= 0 && wallCol < GameConstants.boardSize - 1 &&
          wallRow >= 0 && wallRow < GameConstants.boardSize - 1) {
        final isHorizontal = fracRow > fracCol;
        _attemptWallPlace(Position(wallRow, wallCol), isHorizontal);
      }
    }
  }
}

class BoardPainter extends CustomPainter {
  final GameState gameState;
  final Position? selectedPawn;
  final List<Position> validMoves;
  final Position? hoverPosition;
  final Wall? previewWall;
  final ThemeData theme;

  static const double _cellSize = 40.0;
  static const double _wallThickness = 6.0;

  BoardPainter({
    required this.gameState,
    this.selectedPawn,
    this.validMoves = const [],
    this.hoverPosition,
    this.previewWall,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);
    _drawGoalLines(canvas, size);
    _drawValidMoves(canvas, size);
    _drawWalls(canvas, size);
    _drawPreviewWall(canvas, size);
    _drawPawns(canvas, size);
    _drawSelection(canvas, size);
    _drawHover(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.colorScheme.surfaceVariant.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.colorScheme.outline.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw grid lines
    for (int i = 0; i <= GameConstants.boardSize; i++) {
      final x = i * _cellSize;
      final y = i * _cellSize;

      // Vertical lines
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, GameConstants.boardSize * _cellSize),
        paint,
      );

      // Horizontal lines
      canvas.drawLine(
        Offset(0, y),
        Offset(GameConstants.boardSize * _cellSize, y),
        paint,
      );
    }

    // Draw checkerboard pattern
    final checkerPaint = Paint()
      ..color = theme.colorScheme.surface
      ..style = PaintingStyle.fill;

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        if ((row + col) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(
              col * _cellSize,
              row * _cellSize,
              _cellSize,
              _cellSize,
            ),
            checkerPaint,
          );
        }
      }
    }
  }

  void _drawGoalLines(Canvas canvas, Size size) {
    final player1Paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.3)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final player2Paint = Paint()
      ..color = theme.colorScheme.secondary.withOpacity(0.3)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Player 1 goal line (top)
    canvas.drawLine(
      const Offset(0, 0),
      Offset(GameConstants.boardSize * _cellSize, 0),
      player1Paint,
    );

    // Player 2 goal line (bottom)
    final bottomY = GameConstants.boardSize * _cellSize;
    canvas.drawLine(
      Offset(0, bottomY),
      Offset(GameConstants.boardSize * _cellSize, bottomY),
      player2Paint,
    );
  }

  void _drawValidMoves(Canvas canvas, Size size) {
    if (validMoves.isEmpty) return;

    final paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    for (final move in validMoves) {
      final centerX = move.col * _cellSize + _cellSize / 2;
      final centerY = move.row * _cellSize + _cellSize / 2;

      canvas.drawCircle(
        Offset(centerX, centerY),
        8.0,
        paint,
      );
    }
  }

  void _drawWalls(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.colorScheme.onSurface
      ..style = PaintingStyle.fill;

    for (final wall in gameState.walls) {
      _drawWall(canvas, wall, paint);
    }
  }

  void _drawPreviewWall(Canvas canvas, Size size) {
    if (previewWall == null) return;

    final paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    _drawWall(canvas, previewWall!, paint);
  }

  void _drawWall(Canvas canvas, Wall wall, Paint paint) {
    if (wall.orientation == WallOrientation.horizontal) {
      // Horizontal wall
      final rect = Rect.fromLTWH(
        wall.position.col * _cellSize,
        wall.position.row * _cellSize - _wallThickness / 2,
        _cellSize * 2,
        _wallThickness,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    } else {
      // Vertical wall
      final rect = Rect.fromLTWH(
        wall.position.col * _cellSize - _wallThickness / 2,
        wall.position.row * _cellSize,
        _wallThickness,
        _cellSize * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }

  void _drawPawns(Canvas canvas, Size size) {
    _drawPawn(canvas, gameState.player1.position, theme.colorScheme.primary);
    _drawPawn(canvas, gameState.player2.position, theme.colorScheme.secondary);
  }

  void _drawPawn(Canvas canvas, Position position, Color color) {
    final centerX = position.col * _cellSize + _cellSize / 2;
    final centerY = position.row * _cellSize + _cellSize / 2;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX + 1, centerY + 1),
      14.0,
      shadowPaint,
    );

    // Draw pawn
    final pawnPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX, centerY),
      12.0,
      pawnPaint,
    );

    // Draw highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(centerX - 3, centerY - 3),
      4.0,
      highlightPaint,
    );
  }

  void _drawSelection(Canvas canvas, Size size) {
    if (selectedPawn == null) return;

    final paint = Paint()
      ..color = theme.colorScheme.primary
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final centerX = selectedPawn!.col * _cellSize + _cellSize / 2;
    final centerY = selectedPawn!.row * _cellSize + _cellSize / 2;

    canvas.drawCircle(
      Offset(centerX, centerY),
      18.0,
      paint,
    );
  }

  void _drawHover(Canvas canvas, Size size) {
    if (hoverPosition == null) return;

    final paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(
        hoverPosition!.col * _cellSize,
        hoverPosition!.row * _cellSize,
        _cellSize,
        _cellSize,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    return gameState != oldDelegate.gameState ||
        selectedPawn != oldDelegate.selectedPawn ||
        validMoves != oldDelegate.validMoves ||
        hoverPosition != oldDelegate.hoverPosition ||
        previewWall != oldDelegate.previewWall;
  }
}