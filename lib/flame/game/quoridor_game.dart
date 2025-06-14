import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quoridor/flame/services/localizations.dart';

import '/flame/services/sounds.dart';
import '../components/board_component.dart';
import '../components/emoji_animation_component.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';
import '../services/game_session_service.dart';

final isInitializedProvider = ValueNotifier(false);

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  GameState? _gameState;
  late BoardComponent _boardComponent;
  bool _isInitialized = false;
  final GameSessionService _sessionService = GameSessionService();
  final String? _sessionId;
  final bool? _isHost;
  StreamSubscription? _gameStateSubscription;
  EmojiAnimationComponent? _currentEmojiAnimation;

  Function(GameState)? onGameStateChanged;
  Function(String)? onGameMessage;
  VoidCallback? onGameWon;
  final VoidCallback? onGameOver;

  QuoridorGame({String? sessionId, bool? isHost, this.onGameOver})
    : _sessionId = sessionId,
      _isHost = isHost,
      super() {
    _gameState = GameStateFactory.createNewGame();
    _boardComponent = BoardComponent(_gameState!);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = handleWallPlaceAttempt;
    add(_boardComponent);
    _updateUI();
    _isInitialized = true;

    if (_sessionId != null) {
      _setupOnlineGame();
    }
  }

  Future<void> _setupOnlineGame() async {
    if (_sessionId == null) return;

    // Listen for game state updates
    _gameStateSubscription = _sessionService.streamGameState(_sessionId).listen(
      (newState) {
        if (newState != null && newState != _gameState) {
          updateGameState(newState);
        }
      },
    );
  }

  @override
  Future<void> onLoad() async {
    await GameSounds.preload();
  }

  @override
  void onRemove() {
    _gameStateSubscription?.cancel();
    super.onRemove();
  }

  @override
  Color backgroundColor() => Colors.transparent;

  void _updateUI() async {
    if (_gameState!.isGameOver) {
      onGameMessage?.call(
        '${AppLocale.gameOver} ${_gameState!.winner} ${AppLocale.wins}!',
      );
      onGameWon?.call();
      GameSounds.triggerFeedback(soundKey: 'win');

      // End online session if game is over
      if (_sessionId != null) {
        await _sessionService.endSession(_sessionId!);
      }
    }
  }

  void updateGameState(GameState newGameState) {
    _gameState = newGameState;
    _boardComponent.updateGameState(newGameState);
    _updateUI();

    // Update online game state if in online mode
    if (_sessionId != null) {
      _sessionService.updateGameState(_sessionId!, newGameState);
    }

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
        onGameMessage?.call(AppLocale.aiPlayedTheirMove);
      }
    } catch (e) {
      onGameMessage?.call('AI move failed: $e');
    }
  }

  void _handleMoveAttempt(Position newPosition) {
    if (!GameManager.canPlayerMove(_gameState!, _gameState!.currentPlayerId)) {
      onGameMessage?.call('${AppLocale.itsNotYourTurn}!');
      return;
    }

    // In online mode, only allow moves for the current player
    if (_sessionId != null) {
      final isPlayer1 = _isHost ?? true; // Default to true if not set
      final currentPlayerId = _gameState!.currentPlayerId;
      if ((isPlayer1 && currentPlayerId != 1) ||
          (!isPlayer1 && currentPlayerId != 2)) {
        onGameMessage?.call('${AppLocale.itsNotYourTurn}!');
        return;
      }
    }

    final move = GameMove.pawnMove(newPosition, _gameState!.currentPlayerId);

    if (GameService.isValidMove(_gameState!, move)) {
      _processMove(move);
    } else {
      onGameMessage?.call(AppLocale.invalidMove);
      HapticFeedback.lightImpact();
    }
  }

  void handleWallPlaceAttempt(Wall wall) {
    if (!GameManager.canPlayerMove(_gameState!, _gameState!.currentPlayerId)) {
      onGameMessage?.call(AppLocale.itsNotYourTurn);
      return;
    }

    // In online mode, only allow wall placement for the current player
    if (_sessionId != null) {
      final isPlayer1 = _isHost ?? true; // Default to true if not set
      final currentPlayerId = _gameState!.currentPlayerId;
      if ((isPlayer1 && currentPlayerId != 1) ||
          (!isPlayer1 && currentPlayerId != 2)) {
        onGameMessage?.call('${AppLocale.itsNotYourTurn}!');
        return;
      }
    }

    if (!_gameState!.currentPlayer.hasWallsRemaining) {
      onGameMessage?.call(AppLocale.noWallsRemaining);
      HapticFeedback.lightImpact();
      return;
    }

    final move = GameMove.wallPlace(
      Wall(wall.position, gameState.wallOrientation),
      _gameState!.currentPlayerId,
    );

    if (GameService.isValidMove(_gameState!, move)) {
      _boardComponent.wallComponent.lastTappedWall = null;
      _gameState!.previewWall = null;
      GameSounds.triggerFeedback(
        soundKey: _gameState!.currentPlayer.id == 1 ? 'wall_p1' : 'wall_p2',
      );
      _processMove(move);
    } else {
      onGameMessage?.call(AppLocale.invalidWallPlacement);
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
        onGameMessage?.call('${newGameState.winner} ${AppLocale.wins}!');
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      onGameMessage?.call('${AppLocale.moveFailed}: $e');
      HapticFeedback.lightImpact();
    }
  }

  // Game control methods
  void newGame() {
    updateGameState(GameStateFactory.createNewGame());
    onGameMessage?.call(AppLocale.newGameStarted);
  }

  void setDifficulty(AIDifficulty difficulty) {
    _gameState!.difficulty = difficulty;
    onGameMessage?.call('${AppLocale.difficultySetTo} ${difficulty.name}');
  }

  void showValidMoves() {
    gameState.toggleShowValidMoves();
    _boardComponent.showValidMoves = gameState.showValidMoves;
    _boardComponent.updateGameState(gameState);

    onGameMessage?.call(
      gameState.showValidMoves
          ? AppLocale.validMovesHighlighted
          : AppLocale.validMovesHidden,
    );
  }

  void toggleWallOrientation() {
    final orientation =
        _gameState!.getWallOrientation == WallOrientation.horizontal
        ? WallOrientation.vertical
        : WallOrientation.horizontal;
    _gameState!.setWallOrientation = orientation;
    _boardComponent.updateGameState(_gameState!);
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
          ? AppLocale.switchedToAI
          : AppLocale.switchedToTwoPlayers,
    );
  }

  // Input handling
  @override
  bool onTapDown(TapDownEvent event) {
    if (!_isInitialized) return false;

    // Convert screen coordinates to local board coordinates
    final localPosition = event.localPosition - _boardComponent.position;
    debugPrint('Tap detected at: $localPosition'); // Debug log

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
        '${AppLocale.gameStateNotInitialized} ${AppLocale.pleaseWait}',
      );
    }
    return _gameState!;
  }

  bool get isGameOver => gameState.isGameOver;

  String? get winner => gameState.winner;

  int get currentPlayerId => gameState.currentPlayerId;

  bool get isInitialized => _isInitialized;

  void _handleGameOver() {
    onGameOver?.call();
  }

  void showEmojiAnimation(String emoji) {
    // Remove any existing animation
    _currentEmojiAnimation?.removeFromParent();

    // Create and add new animation
    _currentEmojiAnimation = EmojiAnimationComponent(
      emoji: emoji,
      gameSize: size,
    );

    add(_currentEmojiAnimation!);
    _currentEmojiAnimation!.playAnimation();

    // Remove animation after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      _currentEmojiAnimation?.removeFromParent();
      _currentEmojiAnimation = null;
    });
  }
}
