import 'package:audioplayers/audioplayers.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board_component.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';

class PlayerInfoWidget extends StatelessWidget {
  final int playerId;
  final String name;
  final int wallsRemaining;
  final bool isCurrentPlayer;
  final bool isAI;

  const PlayerInfoWidget({
    super.key,
    required this.playerId,
    required this.name,
    required this.wallsRemaining,
    required this.isCurrentPlayer,
    required this.isAI,
  });

  @override
  Widget build(BuildContext context) {
    final color = playerId == 1 ? Colors.deepPurple : Colors.teal;

    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isAI ? "🤖 AI" : name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
              if (isCurrentPlayer) const Spacer(),
              if (isCurrentPlayer)
                CircleAvatar(radius: 6, backgroundColor: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Walls: $wallsRemaining',
            style: TextStyle(color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

final isInitializedProvider = ValueNotifier(false);

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  GameState? _gameState;
  late BoardComponent _boardComponent;
  bool _isInitialized = false;

  Function(GameState)? onGameStateChanged;
  Function(String)? onGameMessage;
  VoidCallback? onGameWon;

  @override
  Future<void> onLoad() async {
    // Initialize game state
    _gameState = GameStateFactory.createNewGame();

    // Create board component
    _boardComponent = BoardComponent(_gameState!);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = _handleWallPlaceAttempt;

    // Position board in center
    _boardComponent.position = Vector2(0, 0);
    add(_boardComponent);

    _updateUI();

    _isInitialized = true;
  }

  final AudioPlayer _audioPlayer = AudioPlayer();
  @override
  Color backgroundColor() => Colors.transparent;

  void _updateUI() async {
    if (_gameState!.isGameOver) {
      onGameMessage?.call('Game Over! ${_gameState!.winner} wins!');
      onGameWon?.call();
      await _audioPlayer.play(AssetSource("sounds/win.wav"));
    }
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

    // Set a specific size for the BoardComponent
    _boardComponent.size = Vector2(
      size.x,
      size.y,
    ); // Example size, adjust as needed

    // Center the BoardComponent
    _boardComponent.position = Vector2(
      (size.x - _boardComponent.size.x) / 2,
      (size.y - _boardComponent.size.y) / 2,
    );
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
