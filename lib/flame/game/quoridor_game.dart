import 'package:audioplayers/audioplayers.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board_component.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  GameState? _gameState;
  late BoardComponent _boardComponent;
  late TextComponent _statusText;
  late TextComponent _player1Info;
  late TextComponent _player2Info;
  bool _isInitialized = false;

  Function(GameState)? onGameStateChanged;
  Function(String)? onGameMessage;

  @override
  Color backgroundColor() => const Color(0xFFF1F4F8);

  @override
  Future<void> onLoad() async {
    // Initialize game state
    _gameState = GameStateFactory.createNewGame();

    // Create board component
    _boardComponent = BoardComponent(_gameState!);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = _handleWallPlaceAttempt;

    // Position board in center
    _boardComponent.position = Vector2(
      (size.x - _boardComponent.size.x) / 2,
      (size.y - _boardComponent.size.y) / 2,
    );

    add(_boardComponent);

    // Add UI components
    _createUIComponents();
    _updateUI();

    _isInitialized = true;
  }

  void _createUIComponents() {
    // Status text at top
    _statusText = TextComponent(
      text: 'Player 1\'s Turn',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(0xFF15161E),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    _statusText.position = Vector2(size.x / 2, 50);
    _statusText.anchor = Anchor.center;
    add(_statusText);

    // Player 1 info (left side)
    _player1Info = TextComponent(
      text: 'Player 1\nWalls: 10',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(GameConstants.player1Color),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    _player1Info.position = Vector2(50, size.y / 2);
    _player1Info.anchor = Anchor.centerLeft;
    add(_player1Info);

    // Player 2 info (right side)
    _player2Info = TextComponent(
      text: 'AI Player\nWalls: 10',
      textRenderer: TextPaint(
        style: const TextStyle(
          color: Color(GameConstants.player2Color),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    _player2Info.position = Vector2(size.x - 50, size.y / 2);
    _player2Info.anchor = Anchor.bottomRight;
    add(_player2Info);
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  void _updateUI() async {
    // Update status text
    if (_gameState!.isGameOver) {
      _statusText.text = '${_gameState!.winner} Wins!';
      _statusText.textRenderer = TextPaint(
        style: const TextStyle(
          color: Color(0xFF6F61EF),
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      );
      await _audioPlayer.play(AssetSource("sounds/win.wav"));
    } else {
      _statusText.text = '${_gameState!.currentPlayer.name}\'s Turn';
      _statusText.textRenderer = TextPaint(
        style: TextStyle(
          color: Color(
            _gameState!.currentPlayerId == 1
                ? GameConstants.player1Color
                : GameConstants.player2Color,
          ),
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    // Update player info
    _player1Info.text =
        '${_gameState!.player1.name}\nWalls: ${_gameState!.player1.wallsRemaining}';
    _player2Info.text =
        '${_gameState!.player2.name}\nWalls: ${_gameState!.player2.wallsRemaining}';
  }

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;
    _boardComponent.updateGameState(newGameState);
    _updateUI();

    // Trigger AI move if needed
    if (!_gameState!.isGameOver && _gameState!.currentPlayer.isAI) {
      _executeAIMove();
    }

    onGameStateChanged?.call(_gameState!);
  }

  Future<void> _executeAIMove() async {
    // Add delay for better UX
    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final newGameState = await GameService.executeAITurn(
        _gameState!,
        AIDifficulty.medium,
      );

      if (newGameState != _gameState) {
        updateGameState(newGameState);
        onGameMessage?.call('AI played their move');
      }
    } catch (e) {
      onGameMessage?.call('AI move failed: $e');
    }
  }

  void _handleMoveAttempt(Position newPosition) {
    if (!GameManager.canPlayerMove(_gameState!, _gameState!.currentPlayerId)) {
      onGameMessage?.call('It\'s not your turn!');
      return;
    }

    final move = GameMove.pawnMove(newPosition, _gameState!.currentPlayerId);

    if (GameService.isValidMove(_gameState!, move)) {
      _processMove(move);
    } else {
      onGameMessage?.call('Invalid move!');
      HapticFeedback.lightImpact();
    }
  }

  void _handleWallPlaceAttempt(Wall wall) {
    if (!GameManager.canPlayerMove(_gameState!, _gameState!.currentPlayerId)) {
      onGameMessage?.call('It\'s not your turn!');
      return;
    }

    if (!_gameState!.currentPlayer.hasWallsRemaining) {
      onGameMessage?.call('No walls remaining!');
      HapticFeedback.lightImpact();
      return;
    }

    final move = GameMove.wallPlace(wall, _gameState!.currentPlayerId);

    if (GameService.isValidMove(_gameState!, move)) {
      _processMove(move);
    } else {
      onGameMessage?.call('Invalid wall placement!');
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _processMove(GameMove move) async {
    try {
      final newGameState = await GameManager.processPlayerMove(
        _gameState!,
        move,
      );
      updateGameState(newGameState);

      HapticFeedback.selectionClick();

      if (newGameState.isGameOver) {
        onGameMessage?.call('${newGameState.winner} wins!');
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      onGameMessage?.call('Move failed: $e');
      HapticFeedback.lightImpact();
    }
  }

  // Game control methods
  void newGame() {
    updateGameState(GameStateFactory.createNewGame());
    onGameMessage?.call('New game started!');
  }

  void setDifficulty(AIDifficulty difficulty) {
    // This could be used to adjust AI behavior in future moves
    onGameMessage?.call('Difficulty set to ${difficulty.name}');
  }

  void showValidMoves(bool show) {
    _boardComponent.showValidMoves = show;
  }

  @override
  void onRemove() {
    _audioPlayer.dispose();
    super.onRemove();
  }

  void togglePlayerMode() {
    // Switch between AI and human player 2
    final newGameState = GameState(
      gameId: _gameState!.gameId,
      player1: _gameState!.player1,
      player2: _gameState!.player2.copyWith(isAI: !_gameState!.player2.isAI),
      walls: _gameState!.walls,
      currentPlayerId: _gameState!.currentPlayerId,
      status: _gameState!.status,
      createdAt: _gameState!.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: _gameState!.moveHistory,
    );

    updateGameState(newGameState);
    onGameMessage?.call(
      newGameState.player2.isAI
          ? 'Switched to AI opponent'
          : 'Switched to human opponent',
    );
  }

  // Input handling
  @override
  bool onTapDown(TapDownEvent event) {
    if (!_isInitialized) return false;

    // Convert screen coordinates to local board coordinates
    final localPosition = event.localPosition - _boardComponent.position;
    print('Tap detected at: $localPosition'); // Debug log

    // Pass tap to board component
    _boardComponent.handleTap(localPosition);
    return true;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    if (!_isInitialized) return;

    // Re-center board
    if (hasLayout) {
      _boardComponent.position = Vector2(
        (size.x - _boardComponent.size.x) / 2,
        (size.y - _boardComponent.size.y) / 2,
      );

      // Update UI positions
      _statusText.position = Vector2(size.x / 2, 50);
      _player1Info.position = Vector2(50, size.y / 2);
      _player2Info.position = Vector2(size.x - 50, size.y / 2);
    }
  }

  bool onHover(PointerHoverEvent event) {
    if (!_isInitialized) return false;

    // Convert screen coordinates to local board coordinates
    final localPosition = Vector2(
      event.localPosition.dx - _boardComponent.position.x,
      event.localPosition.dy - _boardComponent.position.y,
    );

    // Pass hover to board component
    _boardComponent.handleHover(localPosition);
    return true;
  }

  // Getters for external access
  GameState get gameState {
    if (!_isInitialized || _gameState == null) {
      throw StateError(
        'Game state has not been initialized yet. Please wait for the game to load.',
      );
    }
    return _gameState!;
  }

  bool get isGameOver => gameState.isGameOver;

  String? get winner => gameState.winner;

  int get currentPlayerId => gameState.currentPlayerId;

  bool get isInitialized => _isInitialized;
}
