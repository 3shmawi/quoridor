import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/theme.dart';

import 'board/board_metrics.dart';
import 'constants.dart';
import 'models/game_state.dart';
import 'services/game_service.dart';
import 'wall_component.dart';

/// What a tap on the board means right now.
///
/// Walls used to share the pawn's tap handler and were triggered by hitting a
/// narrow strip near a cell edge, which players could not see and mostly
/// discovered by accident. Splitting the two intents into explicit modes makes
/// every tap unambiguous and lets the board advertise what it expects.
enum BoardInteractionMode { move, wall }

class BoardComponent extends PositionComponent {
  GameState _gameState;

  /// Highlights the squares the current player can step onto.
  bool showValidMoves = true;

  BoardInteractionMode _mode = BoardInteractionMode.move;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;

  /// Fires whenever something the surrounding UI renders has changed, so the
  /// page can rebuild its controls (mode, ghost wall, validity message).
  VoidCallback? onInteractionChanged;

  List<Position> _validMoves = const [];

  /// The wall the player is lining up but has not committed yet.
  Wall? _pendingWall;
  WallPlacementResult? _pendingResult;
  WallOrientation _orientation = WallOrientation.horizontal;

  late final WallComponent _wallComponent;

  BoardMetrics _metrics = BoardMetrics.fit(Size.zero);
  Vector2 _metricsSource = Vector2.zero();

  BoardComponent(this._gameState) {
    _wallComponent = WallComponent(_gameState);
    add(_wallComponent);
    _refreshValidMoves();
  }

  BoardInteractionMode get mode => _mode;

  /// The wall currently being lined up, if any.
  Wall? get pendingWall => _pendingWall;

  /// Validity of [pendingWall], including the reason when it is illegal.
  WallPlacementResult? get pendingWallResult => _pendingResult;

  bool get canCommitPendingWall => _pendingResult?.isValid ?? false;

  BoardMetrics get metrics => _metrics;

  set mode(BoardInteractionMode value) {
    if (_mode == value) return;
    _mode = value;
    _clearPendingWall();
    _refreshValidMoves();
    _wallComponent.showSlots = value == BoardInteractionMode.wall;
    onInteractionChanged?.call();
  }

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;
    _wallComponent.gameState = newGameState;
    _clearPendingWall();
    _refreshValidMoves();

    // A player with no walls left can only move.
    if (_mode == BoardInteractionMode.wall &&
        !newGameState.currentPlayer.hasWallsRemaining) {
      _mode = BoardInteractionMode.move;
      _wallComponent.showSlots = false;
    }
    onInteractionChanged?.call();
  }

  @override
  void render(Canvas canvas) {
    _ensureMetrics();
    _drawBoardSurface(canvas);
    _drawGoalRows(canvas);
    _drawGrid(canvas);
    _drawValidMoves(canvas);
    _drawPawns(canvas);
  }

  /// Recomputes geometry when the component's size changes.
  void _ensureMetrics() {
    if (_metricsSource == size) return;
    _metricsSource = size.clone();
    _metrics = BoardMetrics.fit(Size(size.x, size.y));
    _wallComponent.metrics = _metrics;
  }

  // --- Input -------------------------------------------------------------

  void handleTap(Vector2 position) {
    _ensureMetrics();
    final offset = Offset(position.x, position.y);

    if (_mode == BoardInteractionMode.wall) {
      _handleWallTap(offset);
    } else {
      _handleMoveTap(offset);
    }
  }

  void _handleMoveTap(Offset offset) {
    final tapped = _metrics.positionAt(offset);
    if (tapped == null) return;

    // Pawns no longer have to be selected before moving: the legal squares are
    // always on screen, so one tap on a highlighted square is the whole move.
    if (_validMoves.contains(tapped)) {
      onMoveAttempted?.call(tapped);
    }
  }

  void _handleWallTap(Offset offset) {
    // Any tap on the board snaps to the closest slot, so the player never has
    // to hit a thin target.
    final slot = _metrics.nearestIntersection(offset);
    final candidate = BoardMetrics.wallAtIntersection(
      slot.row,
      slot.col,
      _orientation,
    );

    _setPendingWall(candidate);
  }

  /// Flips the pending wall between horizontal and vertical, keeping it on the
  /// same slot.
  void rotatePendingWall() {
    _orientation = _orientation == WallOrientation.horizontal
        ? WallOrientation.vertical
        : WallOrientation.horizontal;

    final current = _pendingWall;
    if (current == null) {
      onInteractionChanged?.call();
      return;
    }

    final slot = BoardMetrics.intersectionOfWall(current);
    _setPendingWall(
      BoardMetrics.wallAtIntersection(slot.row, slot.col, _orientation),
    );
  }

  void _setPendingWall(Wall wall) {
    _pendingWall = wall;
    _pendingResult = GameService.validateWallPlacement(
      _gameState,
      _gameState.currentPlayer,
      wall,
    );

    _wallComponent.previewWall = wall;
    _wallComponent.isValid = _pendingResult!.isValid;
    onInteractionChanged?.call();
  }

  /// Commits the pending wall. Returns false when there is nothing legal to
  /// place, leaving the ghost on screen so the player can adjust it.
  bool commitPendingWall() {
    final wall = _pendingWall;
    if (wall == null || !(_pendingResult?.isValid ?? false)) return false;

    onWallPlaceAttempted?.call(wall);
    return true;
  }

  void cancelPendingWall() {
    _clearPendingWall();
    onInteractionChanged?.call();
  }

  void _clearPendingWall() {
    _pendingWall = null;
    _pendingResult = null;
    _wallComponent.previewWall = null;
  }

  void handleHover(Vector2 position) {
    if (_mode != BoardInteractionMode.wall) return;
    _ensureMetrics();
    _handleWallTap(Offset(position.x, position.y));
  }

  void _refreshValidMoves() {
    _validMoves = _gameState.isGameOver
        ? const []
        : _gameState.getValidMoves(_gameState.currentPlayer.position);
  }

  // --- Rendering ---------------------------------------------------------

  bool get _isDark => isDarkModeNotifier.value;

  void _drawBoardSurface(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        _metrics.boardRect,
        Radius.circular(_metrics.cellSize * 0.25),
      ),
      Paint()
        ..color = _isDark ? const Color(0xFF16202B) : const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill,
    );
  }

  /// Tints each player's target row so the direction of play is obvious at a
  /// glance instead of being a thin line at the board edge.
  void _drawGoalRows(Canvas canvas) {
    void tintRow(int row, Color color) {
      final rect = Rect.fromLTRB(
        _metrics.cellRect(Position(row, 0)).left - _metrics.spacing,
        _metrics.cellRect(Position(row, 0)).top - _metrics.spacing,
        _metrics.cellRect(Position(row, GameConstants.boardSize - 1)).right +
            _metrics.spacing,
        _metrics.cellRect(Position(row, 0)).bottom + _metrics.spacing,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          Radius.circular(_metrics.cellSize * 0.2),
        ),
        Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
    }

    // Player 1 runs to the top row, player 2 to the bottom row.
    tintRow(GameConstants.player1Goal, const Color(GameConstants.player1Color));
    tintRow(GameConstants.player2Goal, const Color(GameConstants.player2Color));
  }

  void _drawGrid(Canvas canvas) {
    final lightPaint = Paint()
      ..color = _isDark ? const Color(0xFF2C3E50) : const Color(GameConstants.lightCellColor)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = _isDark ? const Color(0xFF1A2530) : const Color(GameConstants.darkCellColor)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = _isDark ? const Color(0xFF34495E) : const Color(0xFFB0BEC5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final radius = Radius.circular(_metrics.cellSize * 0.16);

    for (int row = 0; row < GameConstants.boardSize; row++) {
      for (int col = 0; col < GameConstants.boardSize; col++) {
        final rrect = RRect.fromRectAndRadius(
          _metrics.cellRect(Position(row, col)),
          radius,
        );
        canvas.drawRRect(rrect, (row + col) % 2 == 0 ? lightPaint : darkPaint);
        canvas.drawRRect(rrect, borderPaint);
      }
    }
  }

  void _drawValidMoves(Canvas canvas) {
    if (!showValidMoves ||
        _mode != BoardInteractionMode.move ||
        _validMoves.isEmpty) {
      return;
    }

    final color = _gameState.currentPlayerId == 1
        ? const Color(GameConstants.player1Color)
        : const Color(GameConstants.player2Color);

    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final ring = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _metrics.cellSize * 0.07;

    for (final position in _validMoves) {
      final center = _metrics.cellCenter(position);
      canvas.drawCircle(center, _metrics.cellSize * 0.28, fill);
      canvas.drawCircle(center, _metrics.cellSize * 0.28, ring);
    }
  }

  void _drawPawns(Canvas canvas) {
    _drawPawn(
      canvas,
      _gameState.player1.position,
      const Color(GameConstants.player1Color),
      '1',
      _gameState.currentPlayerId == 1,
    );
    _drawPawn(
      canvas,
      _gameState.player2.position,
      const Color(GameConstants.player2Color),
      '2',
      _gameState.currentPlayerId == 2,
    );
  }

  void _drawPawn(
    Canvas canvas,
    Position position,
    Color color,
    String label,
    bool isCurrentPlayer,
  ) {
    final center = _metrics.cellCenter(position);
    final radius = _metrics.cellSize * 0.36;

    canvas.drawCircle(
      center.translate(0, radius * 0.12),
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = isCurrentPlayer
            ? Colors.white
            : Colors.black.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.12,
    );

    // A halo marks whose turn it is.
    if (isCurrentPlayer) {
      canvas.drawCircle(
        center,
        radius * 1.22,
        Paint()
          ..color = color.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.1,
      );
    }

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }
}
