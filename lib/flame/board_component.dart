import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:quoridor/theme.dart';

import 'board/board_metrics.dart';
import 'constants.dart';
import 'models/game_state.dart';
import 'services/game_service.dart';
import 'wall_component.dart';

class BoardComponent extends PositionComponent {
  GameState _gameState;

  /// Highlights the squares the current player can step onto.
  bool showValidMoves = true;

  Function(Position)? onMoveAttempted;
  Function(Wall)? onWallPlaceAttempted;

  /// Fires whenever something the surrounding UI renders has changed, so the
  /// page can rebuild its controls (mode, ghost wall, validity message).
  VoidCallback? onInteractionChanged;

  /// The pawn the player has picked up, if any.
  ///
  /// Moving is two taps again: one on your pawn to pick it up, one on where
  /// you want it. Nothing is highlighted until you pick the pawn up, which
  /// keeps the board quiet while you are thinking.
  Position? _selectedPawn;

  List<Position> _validMoves = const [];

  /// The wall the player is lining up but has not committed yet.
  Wall? _pendingWall;
  WallPlacementResult? _pendingResult;
  late final WallComponent _wallComponent;

  BoardMetrics _metrics = BoardMetrics.fit(Size.zero);
  Vector2 _metricsSource = Vector2.zero();

  BoardComponent(this._gameState) {
    _wallComponent = WallComponent(_gameState);
    add(_wallComponent);
    _refreshValidMoves();
  }

  /// The wall currently being lined up, if any.
  Wall? get pendingWall => _pendingWall;

  /// Validity of [pendingWall], including the reason when it is illegal.
  WallPlacementResult? get pendingWallResult => _pendingResult;

  bool get canCommitPendingWall => _pendingResult?.isValid ?? false;

  BoardMetrics get metrics => _metrics;

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;
    _wallComponent.gameState = newGameState;
    _selectedPawn = null;
    _clearPendingWall();
    _refreshValidMoves();
    _wallComponent.showSlots = newGameState.currentPlayer.hasWallsRemaining;
    onInteractionChanged?.call();
  }

  @override
  void render(Canvas canvas) {
    _ensureMetrics();
    _drawBoardSurface(canvas);
    _drawGoalRows(canvas);
    _drawGrid(canvas);
    _drawGoalFlags(canvas);
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
    final tapped = _metrics.positionAt(offset);

    // Tapping your own pawn picks it up, or puts it back down.
    if (tapped != null && tapped == _gameState.currentPlayer.position) {
      _clearPendingWall();
      _selectedPawn = _selectedPawn == tapped ? null : tapped;
      _refreshValidMoves();
      onInteractionChanged?.call();
      return;
    }

    // While a pawn is held, the board is about moving it and nothing else.
    if (_selectedPawn != null) {
      if (tapped != null && _validMoves.contains(tapped)) {
        onMoveAttempted?.call(tapped);
      } else {
        _selectedPawn = null;
        _refreshValidMoves();
        onInteractionChanged?.call();
      }
      return;
    }

    // Pawn down: the rest of the board aims a wall, which gives a whole cell
    // to aim with rather than the few pixels of the gap itself.
    if (_gameState.currentPlayer.hasWallsRemaining) _aimWall(offset);
  }

  /// Places, rotates or moves the wall being lined up, from one tap.
  ///
  /// The slot is the nearest gap between cells, and the orientation is
  /// whichever groove the tap sits closer to — so nudging the tap towards the
  /// other groove turns the wall, and there is no rotate button to find.
  /// Tapping the same wall a second time commits it.
  void _aimWall(Offset offset) {
    final slot = _metrics.nearestIntersection(offset);
    final centre = _metrics.intersectionCenter(slot.row, slot.col);

    final orientation =
        (offset.dy - centre.dy).abs() <= (offset.dx - centre.dx).abs()
        ? WallOrientation.horizontal
        : WallOrientation.vertical;

    final candidate = BoardMetrics.wallAtIntersection(
      slot.row,
      slot.col,
      orientation,
    );

    // Second tap on the same wall confirms it.
    if (_pendingWall == candidate) {
      if (_pendingResult?.isValid ?? false) {
        onWallPlaceAttempted?.call(candidate);
        _clearPendingWall();
      }
      onInteractionChanged?.call();
      return;
    }

    _setPendingWall(candidate);
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
    if (_selectedPawn != null) return;
    _ensureMetrics();
    if (_gameState.currentPlayer.hasWallsRemaining) {
      _aimWall(Offset(position.x, position.y));
    }
  }

  void _refreshValidMoves() {
    final selected = _selectedPawn;
    _validMoves = (selected == null || _gameState.isGameOver)
        ? const []
        : _gameState.getValidMoves(selected);
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

  /// The goal row belonging to whoever is to move.
  ({int row, Color color}) get _currentGoal => _gameState.currentPlayerId == 1
      ? (
          row: GameConstants.player1Goal,
          color: const Color(GameConstants.player1Color),
        )
      : (
          row: GameConstants.player2Goal,
          color: const Color(GameConstants.player2Color),
        );

  /// Tints the row the player to move is heading for. The flags go on top, in
  /// [_drawGoalFlags].
  void _drawGoalRows(Canvas canvas) {
    void markRow(int row, Color color) {
      final first = _metrics.cellRect(Position(row, 0));
      final last = _metrics.cellRect(
        Position(row, GameConstants.boardSize - 1),
      );

      final rect = Rect.fromLTRB(
        first.left - _metrics.spacing,
        first.top - _metrics.spacing,
        last.right + _metrics.spacing,
        first.bottom + _metrics.spacing,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(_metrics.cellSize * 0.2)),
        Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill,
      );
    }

    // Only the player to move sees their target row. Showing both at once
    // says where the ends are; showing one says where *you* are going, and the
    // strip appearing on your turn is what answers "which way am I running".
    final goal = _currentGoal;
    markRow(goal.row, goal.color);
  }

  /// Flags at both ends of each goal row.
  ///
  /// Drawn after the grid: the cells are opaque, so anything painted with the
  /// row tint underneath them would simply be covered up.
  void _drawGoalFlags(Canvas canvas) {
    void flagsOn(int row, Color color) {
      _drawFlag(canvas, _metrics.cellCenter(Position(row, 0)), color);
      _drawFlag(
        canvas,
        _metrics.cellCenter(Position(row, GameConstants.boardSize - 1)),
        color,
      );
    }

    final goal = _currentGoal;
    flagsOn(goal.row, goal.color);
  }

  /// A small pennant on a pole, centred on [center].
  void _drawFlag(Canvas canvas, Offset center, Color color) {
    final height = _metrics.cellSize * 0.52;
    final width = _metrics.cellSize * 0.3;
    final poleWidth = _metrics.cellSize * 0.06;

    final top = center.dy - height / 2;
    final poleX = center.dx - width / 2;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(poleX, top, poleWidth, height),
        Radius.circular(poleWidth / 2),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );

    // The pennant hangs from the top of the pole.
    final pennant = Path()
      ..moveTo(poleX + poleWidth, top)
      ..lineTo(poleX + poleWidth + width, top + height * 0.18)
      ..lineTo(poleX + poleWidth, top + height * 0.36)
      ..close();

    canvas.drawPath(
      pennant,
      Paint()
        ..color = color.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawGrid(Canvas canvas) {
    final lightPaint = Paint()
      ..color = _isDark
          ? const Color(0xFF2C3E50)
          : const Color(GameConstants.lightCellColor)
      ..style = PaintingStyle.fill;

    final darkPaint = Paint()
      ..color = _isDark
          ? const Color(0xFF1A2530)
          : const Color(GameConstants.darkCellColor)
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
    if (!showValidMoves || _validMoves.isEmpty) return;

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
      _selectedPawn == _gameState.player1.position,
    );
    _drawPawn(
      canvas,
      _gameState.player2.position,
      const Color(GameConstants.player2Color),
      '2',
      _gameState.currentPlayerId == 2,
      _selectedPawn == _gameState.player2.position,
    );
  }

  void _drawPawn(
    Canvas canvas,
    Position position,
    Color color,
    String label,
    bool isCurrentPlayer,
    bool isSelected,
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

    // A halo marks whose turn it is; a solid ring marks a pawn picked up.
    if (isCurrentPlayer || isSelected) {
      canvas.drawCircle(
        center,
        radius * (isSelected ? 1.34 : 1.22),
        Paint()
          ..color = color.withValues(alpha: isSelected ? 1 : 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * (isSelected ? 0.16 : 0.1),
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
