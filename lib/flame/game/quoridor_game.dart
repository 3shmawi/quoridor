import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board_component.dart';
import '../services/audio_service.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';

final isInitializedProvider = ValueNotifier(false);

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  GameState? _gameState;
  late BoardComponent _boardComponent;
  bool _isInitialized = false;

  /// Guards the game-over announcement so the win sound and confetti fire once
  /// per game rather than on every state update that follows the win.
  bool _announcedGameOver = false;

  /// How many moves have already had their sound played, so replays of the
  /// same state never retrigger effects.
  int _soundedMoveCount = 0;

  Function(GameState)? onGameStateChanged;
  Function(String)? onGameMessage;
  VoidCallback? onGameWon;

  /// Fires when the board's interaction state changes (mode, pending wall),
  /// so the surrounding page can rebuild its controls.
  VoidCallback? onInteractionChanged;

  @override
  Future<void> onLoad() async {
    // Initialize game state
    _gameState = GameStateFactory.createNewGame();

    // Create board component
    _boardComponent = BoardComponent(_gameState!);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = _handleWallPlaceAttempt;
    _boardComponent.onInteractionChanged = () => onInteractionChanged?.call();

    // Load the sound effects once, up front, so the first move does not stall
    // on asset resolution.
    unawaited(AudioService.instance.initialize());

    // Position board in center
    _boardComponent.position = Vector2(0, 0);
    add(_boardComponent);

    _updateUI();

    _isInitialized = true;
  }

  @override
  Color backgroundColor() => Colors.transparent;

  void _updateUI() {
    if (_gameState!.isGameOver && !_announcedGameOver) {
      _announcedGameOver = true;
      onGameMessage?.call('Game Over! ${_gameState!.winner} wins!');
      onGameWon?.call();
      AudioService.instance.play(GameSound.win);
    }
  }

  void updateGameState(GameState newGameState) {
    final previous = _gameState;
    _gameState = newGameState;
    _boardComponent.updateGameState(newGameState);

    // A new game resets the history, so the sound cursor has to follow it back.
    if (previous != null && previous.gameId != newGameState.gameId) {
      _soundedMoveCount = 0;
      _announcedGameOver = false;
    }
    _playSoundsForNewMoves(newGameState);

    _updateUI();

    // Trigger AI move if needed
    if (!_gameState!.isGameOver && _gameState!.currentPlayer.isAI) {
      _executeAIMove();
    }

    onGameStateChanged?.call(_gameState!);
  }

  /// Plays one effect per move that has landed since the last update.
  ///
  /// Driving sound from the move history means a player's move and the AI's
  /// reply each get their own effect even though they arrive together, and it
  /// keeps working unchanged once moves start arriving from a remote player.
  void _playSoundsForNewMoves(GameState state) {
    final history = state.moveHistory;
    if (history.length <= _soundedMoveCount) {
      _soundedMoveCount = history.length;
      return;
    }

    final newMoves = history.sublist(_soundedMoveCount);
    _soundedMoveCount = history.length;

    for (var i = 0; i < newMoves.length; i++) {
      final move = newMoves[i];
      final sound = move.type == MoveType.pawnMove
          ? GameSound.move(move.playerId)
          : GameSound.wall(move.playerId);

      if (i == 0) {
        AudioService.instance.play(sound);
      } else {
        // Stagger the rest so simultaneous moves do not collide into one blip.
        Timer(Duration(milliseconds: 220 * i), () {
          AudioService.instance.play(sound);
        });
      }
    }
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
    _announcedGameOver = false;
    _soundedMoveCount = 0;
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

  // --- Board interaction ---------------------------------------------------

  BoardInteractionMode get boardMode => _boardComponent.mode;

  set boardMode(BoardInteractionMode value) => _boardComponent.mode = value;

  /// The wall the player is lining up, before committing it.
  Wall? get pendingWall => _boardComponent.pendingWall;

  /// Whether the pending wall is legal, with the reason when it is not.
  WallPlacementResult? get pendingWallResult =>
      _boardComponent.pendingWallResult;

  bool get canCommitPendingWall => _boardComponent.canCommitPendingWall;

  void rotatePendingWall() => _boardComponent.rotatePendingWall();

  void cancelPendingWall() => _boardComponent.cancelPendingWall();

  /// Commits the pending wall, reporting why nothing happened when it cannot
  /// be placed.
  void commitPendingWall() {
    if (_boardComponent.pendingWall == null) {
      onGameMessage?.call('Tap the board to choose where the wall goes');
      return;
    }

    if (!_boardComponent.commitPendingWall()) {
      final reason = _boardComponent.pendingWallResult?.message;
      onGameMessage?.call(reason ?? 'That wall cannot go there');
      HapticFeedback.lightImpact();
    }
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
