import 'dart:async';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board_component.dart';
import '../services/audio_service.dart';
import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai/quoridor_engine.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';
import '../services/settings_service.dart';

final isInitializedProvider = ValueNotifier(false);

class QuoridorGame extends FlameGame
    with TapCallbacks, HasKeyboardHandlerComponents, HoverCallbacks {
  /// [difficulty] defaults to the one saved in settings. It used to default
  /// to medium, so after a restart the menu showed the saved choice while the
  /// computer quietly played medium until the player picked it again.
  QuoridorGame({AIDifficulty? difficulty})
    : _difficulty = difficulty ?? SettingsService.instance.difficulty.value;

  GameState? _gameState;
  late BoardComponent _boardComponent;
  bool _isInitialized = false;

  /// Guards the game-over announcement so the win sound and confetti fire once
  /// per game rather than on every state update that follows the win.
  bool _announcedGameOver = false;

  /// How many moves have already had their sound played, so replays of the
  /// same state never retrigger effects.
  int _soundedMoveCount = 0;

  /// How hard the computer opponent plays. Set from the settings drawer.
  AIDifficulty _difficulty;

  /// Which seat this device plays, when the game is online.
  ///
  /// Null means a local game, where whoever is holding the phone plays both
  /// sides. In an online game this is the difference that matters: the board
  /// must refuse input during the opponent's turn even though that turn is
  /// perfectly active, which a hotseat game has no reason to do.
  int? localPlayerId;

  /// Whether this device may act on the current turn.
  /// Online, the server's view of whose turn it is. Set while a game is
  /// online, so the board also stays still while seats are still filling or
  /// a move is on its way to the server -- times when the board alone would
  /// say this seat may move.
  bool Function()? turnGate;

  /// Quarter turns the board is shown rotated by. Set from the seat this
  /// device holds online; zero on a shared device.
  set viewTurns(int turns) {
    _viewTurns = turns;
    if (_isInitialized) _boardComponent.viewTurns = turns;
  }

  int get viewTurns => _viewTurns;
  int _viewTurns = 0;

  bool get canActNow {
    final state = _gameState;
    if (state == null || state.isGameOver) return false;
    if (state.currentPlayer.isAI) return false;
    final gate = turnGate;
    if (gate != null && !gate()) return false;
    final seat = localPlayerId;
    return seat == null || state.currentPlayerId == seat;
  }

  Function(GameState)? onGameStateChanged;

  /// Fires for each pass that lands, with the seat that passed, so the page
  /// can say why the turn moved on with nothing on the board changing.
  void Function(int seat)? onTurnPassed;

  /// Fires once when a local game ends. Online, the controller announces the
  /// result instead, because only it knows which side this device was on.
  VoidCallback? onGameWon;

  /// Fires when the board's interaction state changes (mode, pending wall),
  /// so the surrounding page can rebuild its controls.
  VoidCallback? onInteractionChanged;

  /// When set, a validated move is handed to this instead of being applied
  /// locally.
  ///
  /// This is what makes an online game different from a local one: the board
  /// shown here follows the server's copy rather than advancing on its own, so
  /// a move the server refuses never appears to have happened. Returning false
  /// leaves the board exactly as it was.
  Future<bool> Function(GameMove move)? onSubmitMove;

  @override
  Future<void> onLoad() async {
    // Initialize game state
    _gameState = GameStateFactory.createNewGame();

    // Create board component
    _boardComponent = BoardComponent(_gameState!);
    _boardComponent.onMoveAttempted = _handleMoveAttempt;
    _boardComponent.onWallPlaceAttempted = _handleWallPlaceAttempt;
    _boardComponent.onInteractionChanged = () => onInteractionChanged?.call();
    _boardComponent.canInteract = () => canActNow;
    _boardComponent.viewTurns = _viewTurns;

    // Position board in center
    _boardComponent.position = Vector2(0, 0);
    add(_boardComponent);

    _updateUI();

    _isInitialized = true;
  }

  @override
  Color backgroundColor() => Colors.transparent;

  /// Whether the board follows a server rather than playing on its own.
  bool get _isOnline => onSubmitMove != null;

  void _updateUI() {
    final state = _gameState!;
    if (!state.isGameOver || _announcedGameOver) return;
    _announcedGameOver = true;

    // Online, the losing device used to get the fanfare, the confetti and a
    // "play again" dialog too, and the winner got that dialog twice: once
    // from here and once from the controller's own game-over callback.
    if (_isOnline) {
      if (state.winnerId == localPlayerId) AudioService.instance.play(Sfx.win);
      return;
    }

    onGameWon?.call();
    AudioService.instance.play(Sfx.win);
  }

  /// Boards this game has been through, oldest first, for [undo].
  final List<GameState> _undoStack = [];

  /// Set while [undo] puts an earlier board back, so that board is not
  /// itself recorded as a step to undo.
  bool _restoring = false;

  void updateGameState(GameState newGameState) {
    final previous = _gameState;
    _gameState = newGameState;
    _boardComponent.updateGameState(newGameState);

    // A new game resets the history, so the sound cursor has to follow it back.
    if (previous != null && previous.gameId != newGameState.gameId) {
      _soundedMoveCount = 0;
      _announcedGameOver = false;
    }
    // An undone win is a game in play again, and winning it a second time
    // deserves its celebration too.
    if (!newGameState.isGameOver) _announcedGameOver = false;
    _recordForUndo(previous, newGameState);
    _playSoundsForNewMoves(newGameState);

    _updateUI();

    // Trigger AI move if needed. Never online: the server's board is the
    // truth there, and a move made here would never reach it.
    if (!_isOnline &&
        !_gameState!.isGameOver &&
        _gameState!.currentPlayer.isAI) {
      _executeAIMove();
    } else if (canActNow && GameService.mustPass(_gameState!)) {
      _passWhenStuck();
    }

    onGameStateChanged?.call(_gameState!);
  }

  void _recordForUndo(GameState? previous, GameState next) {
    if (_isOnline || previous == null || previous.gameId != next.gameId) {
      _undoStack.clear();
      return;
    }
    if (_restoring) return;
    if (next.moveHistory.length > previous.moveHistory.length) {
      _undoStack.add(previous);
    }
  }

  /// Where [undo] would go back to: the latest board on which a person was
  /// to move. Against the computer that skips its reply, so one undo takes
  /// back the player's own move rather than leaving the computer to replay
  /// the same answer at once.
  int? get _undoTarget {
    for (var i = _undoStack.length - 1; i >= 0; i--) {
      if (!_undoStack[i].currentPlayer.isAI) return i;
    }
    return null;
  }

  /// Whether there is a move to take back. Never online, where the move is
  /// already on the server and the other players have seen it.
  bool get canUndo => !_isOnline && _undoTarget != null;

  /// Takes back the last move made by a person, and the computer's reply to
  /// it if there was one.
  void undo() {
    final index = _undoTarget;
    if (_isOnline || index == null) return;

    final target = _undoStack[index];
    _undoStack.removeRange(index, _undoStack.length);

    // Keep who is the computer as it is now: switching seat 2 between the
    // computer and a person is a choice about the table, not a move.
    final current = _gameState!;
    final restored = target.copyWith(
      players: [
        for (final player in target.players)
          player.copyWith(isAI: current.playerById(player.id).isAI),
      ],
    );

    _restoring = true;
    try {
      updateGameState(restored);
    } finally {
      _restoring = false;
    }
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
      final sound = switch (move.type) {
        MoveType.pawnMove => Sfx.move(move.playerId),
        MoveType.wallPlace => Sfx.wall(move.playerId),
        MoveType.pass => null,
      };
      if (sound == null) {
        onTurnPassed?.call(move.playerId);
        continue;
      }

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

  /// How long a boxed-in player's board stays up before their turn passes.
  static const Duration forcedPassDelay = Duration(milliseconds: 1200);

  /// Passes for the player to move, who has nothing else to play.
  ///
  /// Done for them rather than offered as a button: a pass is only ever legal
  /// when it is the only move, so there is no choice to make, and a stuck
  /// player left staring at a board that refuses every tap reads as a hang.
  Future<void> _passWhenStuck() async {
    final expected = _gameState!;
    await Future.delayed(forcedPassDelay);
    if (!identical(_gameState, expected) || !canActNow) return;

    _boardComponent.clearInteraction();
    await _processMove(GameMove.pass(expected.currentPlayerId));
  }

  /// How long the computer appears to think before it replies.
  static const Duration aiThinkingDelay = Duration(milliseconds: 800);

  Future<void> _executeAIMove() async {
    final expected = _gameState;

    // A pause, so the player sees their own move land before the reply.
    await Future.delayed(aiThinkingDelay);

    // Anything that replaced the board meanwhile -- a new game, a switch to
    // two players -- has scheduled its own reply if it needs one.
    if (!identical(_gameState, expected)) return;

    try {
      final newGameState = await GameService.executeAITurn(
        expected!,
        _difficulty,
      );

      if (identical(_gameState, expected) &&
          !identical(newGameState, expected)) {
        updateGameState(newGameState);
      }
    } catch (e) {
      debugPrint('QuoridorGame: AI move failed: $e');
    }
  }

  void _handleMoveAttempt(Position newPosition) {
    if (!canActNow) return;

    final move = GameMove.pawnMove(newPosition, _gameState!.currentPlayerId);

    if (GameService.isValidMove(_gameState!, move)) {
      _processMove(move);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  void _handleWallPlaceAttempt(Wall wall) {
    if (!canActNow) return;

    final move = GameMove.wallPlace(wall, _gameState!.currentPlayerId);

    if (GameService.isValidMove(_gameState!, move)) {
      _processMove(move);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  /// Plays a move on behalf of the player to move, because their time ran out.
  ///
  /// Running out of time forfeits the turn, not the game. A phone game gets
  /// put down mid-turn constantly — for a notification, a bus stop, a person
  /// talking to you — and ending the game over that would punish the player
  /// far more than it discourages stalling. So the engine plays a quick, sane
  /// move and the game carries on.
  ///
  /// It goes through the same path as a tap, so online the move is submitted
  /// to the server like any other and the board still waits for it to land.
  void playForCurrentPlayer() {
    if (!canActNow) return;

    // A step forward, never a wall: see [QuoridorEngine.stepTowardsGoal].
    final move =
        QuoridorEngine.stepTowardsGoal(_gameState!) ??
        QuoridorEngine.bestMove(_gameState!, EngineStrength.easy);
    if (move == null) return;

    _boardComponent.clearInteraction();
    unawaited(_processMove(move));
  }

  /// Puts down a lifted pawn or a wall being lined up. Called for taps that
  /// land outside the game area altogether.
  void clearInteraction() {
    if (!_isInitialized) return;
    _boardComponent.clearInteraction();
  }

  Future<void> _processMove(GameMove move) async {
    final submit = onSubmitMove;
    if (submit != null) {
      // Online: the server decides. The board updates when the change comes
      // back through the game listener, not here.
      HapticFeedback.selectionClick();
      final accepted = await submit(move);
      if (!accepted) HapticFeedback.lightImpact();
      return;
    }

    // Only the player's own move is applied here. The computer's reply used
    // to be worked out in the same call, before the board was redrawn, so the
    // player's pawn sat still for as long as the engine thought and then both
    // moves appeared at once. [updateGameState] schedules the reply instead.
    try {
      final newGameState = GameService.executeMove(_gameState!, move);
      updateGameState(newGameState);

      HapticFeedback.selectionClick();
      if (newGameState.isGameOver) HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('QuoridorGame: move failed: $e');
      HapticFeedback.lightImpact();
    }
  }

  // Game control methods

  /// Starts a fresh game, keeping the table as it is.
  void newGame() => startGame(
    playerCount: _gameState?.playerCount ?? 2,
    againstAI: _gameState?.players.any((player) => player.isAI) ?? true,
  );

  /// Starts a fresh game with [playerCount] at the board.
  ///
  /// [againstAI] makes every seat but the first the computer. At a table of
  /// three or four it plays each seat for itself, against whoever is nearest
  /// to getting home; self-play games at both sizes run to a finish in
  /// seventy to ninety moves with every wall spent.
  void startGame({int playerCount = 2, bool againstAI = true}) {
    _announcedGameOver = false;
    _soundedMoveCount = 0;
    updateGameState(
      GameStateFactory.createNewGame(
        playerCount: playerCount,
        player2IsAI: againstAI,
        player2Name: againstAI ? 'AI' : 'Player 2',
        othersAreAI: againstAI,
      ),
    );
  }

  void setDifficulty(AIDifficulty difficulty) {
    _difficulty = difficulty;
  }

  AIDifficulty get difficulty => _difficulty;

  void showValidMoves(bool show) {
    _boardComponent.showValidMoves = show;
  }

  /// Whether the other seats can be switched between the computer and
  /// people. Never online: a computer seat here would play moves the server
  /// never hears about.
  bool get canTogglePlayerMode => _isInitialized && !_isOnline;

  /// Hands every seat but the first to the computer, or back to people.
  void togglePlayerMode() {
    if (!canTogglePlayerMode) return;

    final toAI = !_gameState!.player2.isAI;
    final newGameState = _gameState!.copyWith(
      players: [
        for (final player in _gameState!.players)
          player.id == 1 ? player : player.copyWith(isAI: toAI),
      ],
      updatedAt: DateTime.now(),
    );

    updateGameState(newGameState);
  }

  // Input handling
  @override
  bool onTapDown(TapDownEvent event) {
    if (!_isInitialized) return false;

    // Refuse the tap before the board reacts to it at all.
    //
    // Checking only when a move is submitted was too late: picking the pawn up
    // and lining a wall up both happen on the board first, so during the
    // opponent's turn the board still lit up and showed a wall preview that
    // could never be placed.
    // The board is dimmed while it is not this device's turn, which says
    // so already; a toast on every tap only got in the way.
    if (!canActNow) {
      _boardComponent.clearInteraction();
      return true;
    }

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
    // Hover previews a wall, so it is gated for the same reason taps are.
    if (!canActNow) {
      _boardComponent.clearInteraction();
      return true;
    }

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
