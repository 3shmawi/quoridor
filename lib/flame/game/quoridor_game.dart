import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quoridor/flame/services/localizations.dart';

import '/flame/services/sounds.dart';
import '../components/board_component.dart';
import '../constants.dart';
import '../controller/game_controller.dart';
import '../controller/game_states.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';

final isInitializedProvider = ValueNotifier(false);

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  late BoardComponent _boardComponent;
  bool _isInitialized = false;
  GameController? _gameController;

  Function(GameState)? onGameStateChanged;
  Function(String)? onGameMessage;
  VoidCallback? onGameWon;

  QuoridorGame({GameController? gameController}) {
    _gameController = gameController;

    _boardComponent = BoardComponent(gameController: gameController);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = handleWallPlaceAttempt;
    add(_boardComponent);
    _updateUI();
    _isInitialized = true;
  }

  void setGameController(GameController controller) {
    _gameController = controller;
    _boardComponent.setGameController(controller);
  }

  @override
  Color backgroundColor() => Colors.transparent;

  void _updateUI() async {
    if (_gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    if (gameState.isGameOver) {
      onGameMessage?.call(
        '${AppLocale.gameOver} ${gameState.winner} ${AppLocale.wins}!',
      );
      onGameWon?.call();
      GameSounds.triggerFeedback(soundKey: 'win');
    }
  }

  void updateFromController() {
    if (!_isInitialized || _gameController == null) return;

    final currentState = _gameController!.state;
    if (currentState is GamePlayingState) {
      _boardComponent.updateFromState(currentState);
      _updateUI();
      onGameStateChanged?.call(currentState.gameState);
    }
  }

  void _handleMoveAttempt(Position newPosition) {
    // If using controller, let it handle the move
    if (_gameController != null) {
      _gameController!.add(MakePawnMove(newPosition));
      return;
    }

    // Fallback to direct game logic (legacy support)
    onGameMessage?.call('${AppLocale.itsNotYourTurn}!');
  }

  void handleWallPlaceAttempt(Wall wall) {
    // If using controller, let it handle the wall placement
    if (_gameController != null) {
      _gameController!.add(PlaceWall(wall));
      return;
    }

    // Fallback to direct game logic (legacy support)
    onGameMessage?.call(AppLocale.noWallsRemaining);
    HapticFeedback.lightImpact();
  }

  // Game control methods
  void newGame() {
    if (_gameController != null) {
      _gameController!.add(StartNewMultiPlayerGame(playerCount: 3));
    } else {
      onGameMessage?.call(AppLocale.newGameStarted);
    }
  }

  void setDifficulty(AIDifficulty difficulty) {
    if (_gameController != null) {
      _gameController!.add(SetAIDifficulty(difficulty));
    } else {
      onGameMessage?.call('${AppLocale.difficultySetTo} ${difficulty.name}');
    }
  }

  void showValidMoves() {
    if (_gameController != null) {
      _gameController!.add(ToggleValidMoves());
    } else {
      onGameMessage?.call(AppLocale.validMovesHighlighted);
    }
  }

  void toggleWallOrientation() {
    if (_gameController != null) {
      _gameController!.add(ToggleWallOrientation());
    } else {
      onGameMessage?.call('Wall orientation toggled');
    }
  }

  void togglePlayerMode() {
    if (_gameController != null) {
      _gameController!.add(TogglePlayerMode());
    } else {
      onGameMessage?.call(AppLocale.switchedToAI);
    }
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
  GameState? get gameState {
    if (!_isInitialized || _gameController == null) {
      return null;
    }

    final currentState = _gameController!.state;
    if (currentState is GamePlayingState) {
      return currentState.gameState;
    }
    return null;
  }

  bool get isGameOver {
    final state = gameState;
    return state?.isGameOver ?? false;
  }

  String? get winner {
    final state = gameState;
    return state?.winner;
  }

  int get currentPlayerId {
    final state = gameState;
    return state?.currentPlayerId ?? 1;
  }

  bool get isInitialized => _isInitialized;
}
