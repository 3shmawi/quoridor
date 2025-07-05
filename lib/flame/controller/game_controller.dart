import 'dart:async';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter/services.dart';

import '../models/game_state.dart';
import '../services/ai_service.dart';
import '../services/game_service.dart';
import '../services/firebase_service.dart';
import '../services/local_storage.dart';
import '../services/sounds.dart';
import '../constants.dart';
import 'game_states.dart';

// Events that can be dispatched to the game controller
abstract class GameEvent {}

// Initialize a new game
class InitializeGame extends GameEvent {
  final String? player1Name;
  final String? player2Name;
  final bool player2IsAI;
  final AIDifficulty aiDifficulty;

  InitializeGame({
    this.player1Name,
    this.player2Name,
    this.player2IsAI = true,
    this.aiDifficulty = AIDifficulty.medium,
  });
}

// Load existing game
class LoadGame extends GameEvent {
  final String gameId;

  LoadGame(this.gameId);
}

// Make a pawn move
class MakePawnMove extends GameEvent {
  final Position newPosition;

  MakePawnMove(this.newPosition);
}

// Place a wall
class PlaceWall extends GameEvent {
  final Wall wall;

  PlaceWall(this.wall);
}

// Toggle wall orientation
class ToggleWallOrientation extends GameEvent {}

// Toggle valid moves display
class ToggleValidMoves extends GameEvent {}

// Set preview wall
class SetPreviewWall extends GameEvent {
  final Wall? wall;

  SetPreviewWall(this.wall);
}

// Set AI difficulty
class SetAIDifficulty extends GameEvent {
  final AIDifficulty difficulty;

  SetAIDifficulty(this.difficulty);
}

// Toggle player mode (AI vs Human)
class TogglePlayerMode extends GameEvent {}

// Start new game
class StartNewGame extends GameEvent {
  final String? player1Name;
  final String? player2Name;
  final bool player2IsAI;
  final AIDifficulty aiDifficulty;

  StartNewGame({
    this.player1Name,
    this.player2Name,
    this.player2IsAI = true,
    this.aiDifficulty = AIDifficulty.medium,
  });
}

// Pause game
class PauseGame extends GameEvent {
  final String reason;

  PauseGame({this.reason = 'Game paused'});
}

// Resume game
class ResumeGame extends GameEvent {}

// Update settings
class UpdateSettings extends GameEvent {
  final GameSettingsState settings;

  UpdateSettings(this.settings);
}

// Undo last move
class UndoMove extends GameEvent {}

// Redo move
class RedoMove extends GameEvent {}

// Save game
class SaveGame extends GameEvent {}

// Load game from storage
class LoadGameFromStorage extends GameEvent {}

// Update game statistics
class UpdateStatistics extends GameEvent {
  final bool isWin;
  final AIDifficulty difficulty;
  final Duration gameDuration;
  final int totalMoves;
  final int wallsPlaced;

  UpdateStatistics({
    required this.isWin,
    required this.difficulty,
    required this.gameDuration,
    required this.totalMoves,
    required this.wallsPlaced,
  });
}

// Main game controller using BLoC pattern
class GameController extends HydratedBloc<GameEvent, GameStates> {
  Timer? _aiTimer;
  DateTime? _gameStartTime;
  GameState? _lastValidState;
  List<GameState> _moveHistory = [];
  int _currentMoveIndex = -1;

  GameController() : super(const GameInitialState()) {
    on<InitializeGame>(_onInitializeGame);
    on<LoadGame>(_onLoadGame);
    on<MakePawnMove>(_onMakePawnMove);
    on<PlaceWall>(_onPlaceWall);
    on<ToggleWallOrientation>(_onToggleWallOrientation);
    on<ToggleValidMoves>(_onToggleValidMoves);
    on<SetPreviewWall>(_onSetPreviewWall);
    on<SetAIDifficulty>(_onSetAIDifficulty);
    on<TogglePlayerMode>(_onTogglePlayerMode);
    on<StartNewGame>(_onStartNewGame);
    on<PauseGame>(_onPauseGame);
    on<ResumeGame>(_onResumeGame);
    on<UpdateSettings>(_onUpdateSettings);
    on<UndoMove>(_onUndoMove);
    on<RedoMove>(_onRedoMove);
    on<SaveGame>(_onSaveGame);
    on<LoadGameFromStorage>(_onLoadGameFromStorage);
    on<UpdateStatistics>(_onUpdateStatistics);
  }

  // Initialize a new game
  Future<void> _onInitializeGame(
    InitializeGame event,
    Emitter<GameStates> emit,
  ) async {
    emit(const GameLoadingState(message: 'Initializing game...'));

    try {
      final gameState = GameStateFactory.createNewGame(
        player1Name: event.player1Name ?? 'Player 1',
        player2Name: event.player2Name ?? 'AI',
        player2IsAI: event.player2IsAI,
      );

      gameState.aiDifficulty = event.aiDifficulty;
      _gameStartTime = DateTime.now();
      _lastValidState = gameState;
      _moveHistory = [gameState];
      _currentMoveIndex = 0;

      emit(
        GamePlayingState(
          gameState: gameState,
          isPlayerTurn: true,
          showValidMoves: true,
          validMoves: gameState.getValidMoves(gameState.currentPlayer.position),
        ),
      );

      // Auto-save to Firebase if user is logged in
      if (FirebaseService.currentUser != null) {
        FirebaseService.updateGame(gameState);
      }

      // Trigger AI move if it's AI's turn
      if (gameState.currentPlayer.isAI) {
        _triggerAIMove(gameState, event.aiDifficulty);
      }
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Failed to initialize game: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Load existing game
  Future<void> _onLoadGame(LoadGame event, Emitter<GameStates> emit) async {
    emit(const GameLoadingState(message: 'Loading game...'));

    try {
      final gameState = await FirebaseService.loadGame(event.gameId);
      if (gameState != null) {
        _lastValidState = gameState;
        _gameStartTime = DateTime.now();

        emit(
          GamePlayingState(
            gameState: gameState,
            isPlayerTurn: !gameState.currentPlayer.isAI,
            showValidMoves: gameState.showValidMoves,
            validMoves: gameState.getValidMoves(
              gameState.currentPlayer.position,
            ),
          ),
        );

        // Trigger AI move if it's AI's turn
        if (gameState.currentPlayer.isAI) {
          _triggerAIMove(gameState, gameState.aiDifficulty);
        }
      } else {
        emit(
          const GameErrorState(
            error: 'Game not found',
            suggestion:
                'The game may have been deleted or you may not have access',
          ),
        );
      }
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Failed to load game: $e',
          suggestion: 'Please check your connection and try again',
        ),
      );
    }
  }

  // Make a pawn move
  Future<void> _onMakePawnMove(
    MakePawnMove event,
    Emitter<GameStates> emit,
  ) async {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    // Validate move
    if (!GameService.isValidMove(
      gameState,
      GameMove.pawnMove(event.newPosition, gameState.currentPlayerId),
    )) {
      emit(currentState.copyWith(currentMessage: 'Invalid move'));
      HapticFeedback.lightImpact();
      return;
    }

    try {
      // Execute move
      final newGameState = GameService.executeMove(
        gameState,
        GameMove.pawnMove(event.newPosition, gameState.currentPlayerId),
      );

      // Add to move history
      _addToMoveHistory(newGameState);

      // Play sound
      if (CacheHelper.getData(key: 'enableSound') ?? true) {
        GameSounds.triggerFeedback(
          soundKey: newGameState.currentPlayer.id == 1 ? 'move_p1' : 'move_p2',
        );
      }

      // Check if game is over
      if (newGameState.isGameOver) {
        _handleGameOver(newGameState, emit);
        return;
      }

      // Update state
      emit(
        GamePlayingState(
          gameState: newGameState,
          isPlayerTurn: !newGameState.currentPlayer.isAI,
          showValidMoves: newGameState.showValidMoves,
          validMoves: newGameState.getValidMoves(
            newGameState.currentPlayer.position,
          ),
          currentMessage: 'Move completed',
        ),
      );

      // Trigger AI move if it's AI's turn
      if (newGameState.currentPlayer.isAI) {
        _triggerAIMove(newGameState, newGameState.aiDifficulty);
      }

      // Auto-save
      if (FirebaseService.currentUser != null) {
        FirebaseService.updateGame(newGameState);
      }
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Move failed: $e',
          suggestion: 'Please try again',
          lastValidState: _lastValidState,
        ),
      );
    }
  }

  // Place a wall
  Future<void> _onPlaceWall(PlaceWall event, Emitter<GameStates> emit) async {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;

    // Validate wall placement
    if (!GameService.isValidMove(
      gameState,
      GameMove.wallPlace(event.wall, gameState.currentPlayerId),
    )) {
      emit(currentState.copyWith(currentMessage: 'Invalid wall placement'));
      HapticFeedback.lightImpact();
      return;
    }

    try {
      // Execute wall placement
      final newGameState = GameService.executeMove(
        gameState,
        GameMove.wallPlace(event.wall, gameState.currentPlayerId),
      );

      // Add to move history
      _addToMoveHistory(newGameState);

      // Play sound
      if (CacheHelper.getData(key: 'enableSound') ?? true) {
        GameSounds.triggerFeedback(
          soundKey: newGameState.currentPlayer.id == 1 ? 'wall_p1' : 'wall_p2',
        );
      }

      // Check if game is over
      if (newGameState.isGameOver) {
        _handleGameOver(newGameState, emit);
        return;
      }

      // Update state
      emit(
        GamePlayingState(
          gameState: newGameState,
          isPlayerTurn: !newGameState.currentPlayer.isAI,
          showValidMoves: newGameState.showValidMoves,
          validMoves: newGameState.getValidMoves(
            newGameState.currentPlayer.position,
          ),
          currentMessage: 'Wall placed',
        ),
      );

      // Trigger AI move if it's AI's turn
      if (newGameState.currentPlayer.isAI) {
        _triggerAIMove(newGameState, newGameState.aiDifficulty);
      }

      // Auto-save
      if (FirebaseService.currentUser != null) {
        FirebaseService.updateGame(newGameState);
      }
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Wall placement failed: $e',
          suggestion: 'Please try again',
          lastValidState: _lastValidState,
        ),
      );
    }
  }

  // Toggle wall orientation
  void _onToggleWallOrientation(
    ToggleWallOrientation event,
    Emitter<GameStates> emit,
  ) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    final newOrientation =
        gameState.wallOrientation == WallOrientation.horizontal
        ? WallOrientation.vertical
        : WallOrientation.horizontal;

    final updatedGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: gameState.player2,
      walls: gameState.walls,
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      aiDifficulty: gameState.aiDifficulty,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: gameState.moveHistory,
      showValidMoves: gameState.showValidMoves,
      wallOrientation: newOrientation,
      previewWall: gameState.previewWall,
    );

    emit(currentState.copyWith(gameState: updatedGameState));
  }

  // Toggle valid moves display
  void _onToggleValidMoves(ToggleValidMoves event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    final newShowValidMoves = !gameState.showValidMoves;

    final updatedGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: gameState.player2,
      walls: gameState.walls,
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      aiDifficulty: gameState.aiDifficulty,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: gameState.moveHistory,
      showValidMoves: newShowValidMoves,
      wallOrientation: gameState.wallOrientation,
      previewWall: gameState.previewWall,
    );

    emit(
      currentState.copyWith(
        gameState: updatedGameState,
        showValidMoves: newShowValidMoves,
      ),
    );
  }

  // Set preview wall
  void _onSetPreviewWall(SetPreviewWall event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    final updatedGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: gameState.player2,
      walls: gameState.walls,
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      aiDifficulty: gameState.aiDifficulty,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: gameState.moveHistory,
      showValidMoves: gameState.showValidMoves,
      wallOrientation: gameState.wallOrientation,
      previewWall: event.wall,
    );

    emit(
      currentState.copyWith(
        gameState: updatedGameState,
        previewWall: event.wall,
      ),
    );
  }

  // Set AI difficulty
  void _onSetAIDifficulty(SetAIDifficulty event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    final updatedGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: gameState.player2,
      walls: gameState.walls,
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      aiDifficulty: event.difficulty,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: gameState.moveHistory,
      showValidMoves: gameState.showValidMoves,
      wallOrientation: gameState.wallOrientation,
      previewWall: gameState.previewWall,
    );

    emit(
      currentState.copyWith(
        gameState: updatedGameState,
        currentMessage: 'AI difficulty set to ${event.difficulty.name}',
      ),
    );
  }

  // Toggle player mode
  void _onTogglePlayerMode(TogglePlayerMode event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    final gameState = currentState.gameState;
    final newPlayer2 = gameState.player2.copyWith(
      isAI: !gameState.player2.isAI,
    );

    final updatedGameState = GameState(
      gameId: gameState.gameId,
      player1: gameState.player1,
      player2: newPlayer2,
      walls: gameState.walls,
      currentPlayerId: gameState.currentPlayerId,
      status: gameState.status,
      aiDifficulty: gameState.aiDifficulty,
      createdAt: gameState.createdAt,
      updatedAt: DateTime.now(),
      moveHistory: gameState.moveHistory,
      showValidMoves: gameState.showValidMoves,
      wallOrientation: gameState.wallOrientation,
      previewWall: gameState.previewWall,
    );

    emit(
      currentState.copyWith(
        gameState: updatedGameState,
        isPlayerTurn: !newPlayer2.isAI,
        currentMessage: newPlayer2.isAI
            ? 'Switched to AI'
            : 'Switched to two players',
      ),
    );
  }

  // Start new game
  Future<void> _onStartNewGame(
    StartNewGame event,
    Emitter<GameStates> emit,
  ) async {
    add(
      InitializeGame(
        player1Name: event.player1Name,
        player2Name: event.player2Name,
        player2IsAI: event.player2IsAI,
        aiDifficulty: event.aiDifficulty,
      ),
    );
  }

  // Pause game
  void _onPauseGame(PauseGame event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    emit(
      GamePausedState(gameState: currentState.gameState, reason: event.reason),
    );
  }

  // Resume game
  void _onResumeGame(ResumeGame event, Emitter<GameStates> emit) {
    final currentState = state;
    if (currentState is! GamePausedState) return;

    emit(
      GamePlayingState(
        gameState: currentState.gameState,
        isPlayerTurn: !currentState.gameState.currentPlayer.isAI,
        showValidMoves: currentState.gameState.showValidMoves,
        validMoves: currentState.gameState.getValidMoves(
          currentState.gameState.currentPlayer.position,
        ),
      ),
    );
  }

  // Update settings
  void _onUpdateSettings(UpdateSettings event, Emitter<GameStates> emit) {
    // Save settings to local storage
    CacheHelper.saveData(
      key: 'aiDifficulty',
      value: event.settings.aiDifficulty.index,
    );
    CacheHelper.saveData(
      key: 'showValidMoves',
      value: event.settings.showValidMoves,
    );
    CacheHelper.saveData(key: 'enableSound', value: event.settings.enableSound);
    CacheHelper.saveData(
      key: 'enableHapticFeedback',
      value: event.settings.enableHapticFeedback,
    );
    CacheHelper.saveData(key: 'language', value: event.settings.language);
    CacheHelper.saveData(key: 'isDarkMode', value: event.settings.isDarkMode);

    emit(event.settings);
  }

  // Undo move
  void _onUndoMove(UndoMove event, Emitter<GameStates> emit) {
    if (_currentMoveIndex > 0) {
      _currentMoveIndex--;
      final previousState = _moveHistory[_currentMoveIndex];

      emit(
        GamePlayingState(
          gameState: previousState,
          isPlayerTurn: !previousState.currentPlayer.isAI,
          showValidMoves: previousState.showValidMoves,
          validMoves: previousState.getValidMoves(
            previousState.currentPlayer.position,
          ),
          currentMessage: 'Move undone',
        ),
      );
    }
  }

  // Redo move
  void _onRedoMove(RedoMove event, Emitter<GameStates> emit) {
    if (_currentMoveIndex < _moveHistory.length - 1) {
      _currentMoveIndex++;
      final nextState = _moveHistory[_currentMoveIndex];

      emit(
        GamePlayingState(
          gameState: nextState,
          isPlayerTurn: !nextState.currentPlayer.isAI,
          showValidMoves: nextState.showValidMoves,
          validMoves: nextState.getValidMoves(nextState.currentPlayer.position),
          currentMessage: 'Move redone',
        ),
      );
    }
  }

  // Save game
  Future<void> _onSaveGame(SaveGame event, Emitter<GameStates> emit) async {
    final currentState = state;
    if (currentState is! GamePlayingState) return;

    try {
      await FirebaseService.updateGame(currentState.gameState);
      emit(currentState.copyWith(currentMessage: 'Game saved successfully'));
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Failed to save game: $e',
          suggestion: 'Please check your connection and try again',
          lastValidState: currentState.gameState,
        ),
      );
    }
  }

  // Load game from storage
  Future<void> _onLoadGameFromStorage(
    LoadGameFromStorage event,
    Emitter<GameStates> emit,
  ) async {
    emit(const GameLoadingState(message: 'Loading saved game...'));

    try {
      final savedGameId = CacheHelper.getData(key: 'lastGameId') as String?;
      if (savedGameId != null) {
        add(LoadGame(savedGameId));
      } else {
        emit(
          const GameErrorState(
            error: 'No saved game found',
            suggestion: 'Start a new game',
          ),
        );
      }
    } catch (e) {
      emit(
        GameErrorState(
          error: 'Failed to load saved game: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Update statistics
  void _onUpdateStatistics(UpdateStatistics event, Emitter<GameStates> emit) {
    // Load current statistics
    final gamesPlayed = (CacheHelper.getData(key: 'gamesPlayed') as int?) ?? 0;
    final gamesWon = (CacheHelper.getData(key: 'gamesWon') as int?) ?? 0;
    final gamesLost = (CacheHelper.getData(key: 'gamesLost') as int?) ?? 0;
    final gamesDrawn = (CacheHelper.getData(key: 'gamesDrawn') as int?) ?? 0;
    final totalWallsPlaced =
        (CacheHelper.getData(key: 'totalWallsPlaced') as int?) ?? 0;
    final totalMovesMade =
        (CacheHelper.getData(key: 'totalMovesMade') as int?) ?? 0;
    final totalGameTime =
        (CacheHelper.getData(key: 'totalGameTime') as int?) ?? 0;

    // Update statistics
    final newGamesPlayed = gamesPlayed + 1;
    final newGamesWon = gamesWon + (event.isWin ? 1 : 0);
    final newGamesLost = gamesLost + (event.isWin ? 0 : 1);
    final newTotalWallsPlaced = totalWallsPlaced + event.wallsPlaced;
    final newTotalMovesMade = totalMovesMade + event.totalMoves;
    final newTotalGameTime = totalGameTime + event.gameDuration.inSeconds;

    // Calculate averages
    final newWinRate = newGamesPlayed > 0 ? newGamesWon / newGamesPlayed : 0.0;
    final newAverageGameTime = Duration(
      seconds: newTotalGameTime ~/ newGamesPlayed,
    );

    // Save to local storage
    CacheHelper.saveData(key: 'gamesPlayed', value: newGamesPlayed);
    CacheHelper.saveData(key: 'gamesWon', value: newGamesWon);
    CacheHelper.saveData(key: 'gamesLost', value: newGamesLost);
    CacheHelper.saveData(key: 'gamesDrawn', value: gamesDrawn);
    CacheHelper.saveData(key: 'totalWallsPlaced', value: newTotalWallsPlaced);
    CacheHelper.saveData(key: 'totalMovesMade', value: newTotalMovesMade);
    CacheHelper.saveData(key: 'totalGameTime', value: newTotalGameTime);

    // Update wins by difficulty
    final winsByDifficulty = Map<AIDifficulty, int>.from(
      (CacheHelper.getData(key: 'winsByDifficulty') as Map<String, dynamic>?)
              ?.map(
                (key, value) =>
                    MapEntry(AIDifficulty.values[int.parse(key)], value as int),
              ) ??
          {},
    );
    if (event.isWin) {
      winsByDifficulty[event.difficulty] =
          (winsByDifficulty[event.difficulty] ?? 0) + 1;
    }
    CacheHelper.saveData(
      key: 'winsByDifficulty',
      value: winsByDifficulty.map(
        (key, value) => MapEntry(key.index.toString(), value),
      ),
    );

    emit(
      GameStatisticsState(
        gamesPlayed: newGamesPlayed,
        gamesWon: newGamesWon,
        gamesLost: newGamesLost,
        gamesDrawn: gamesDrawn,
        winRate: newWinRate,
        averageGameTime: newAverageGameTime,
        totalWallsPlaced: newTotalWallsPlaced,
        totalMovesMade: newTotalMovesMade,
        winsByDifficulty: winsByDifficulty,
      ),
    );
  }

  // Helper method to trigger AI move
  void _triggerAIMove(GameState gameState, AIDifficulty difficulty) {
    _aiTimer?.cancel();

    emit(GameAIThinkingState(gameState: gameState, difficulty: difficulty));

    _aiTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final aiMove = await AIService.generateMove(gameState, difficulty);

        if (aiMove != null) {
          if (aiMove.type == MoveType.pawnMove) {
            add(MakePawnMove(aiMove.newPosition!));
          } else {
            add(PlaceWall(aiMove.wall!));
          }
        }
      } catch (e) {
        emit(
          GameErrorState(
            error: 'AI move failed: $e',
            suggestion: 'Please try again',
            lastValidState: gameState,
          ),
        );
      }
    });
  }

  // Helper method to handle game over
  void _handleGameOver(GameState gameState, Emitter<GameStates> emit) {
    final gameDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!)
        : Duration.zero;

    final isWin = gameState.winner == gameState.player1.name;
    final totalMoves = gameState.moveHistory.length;
    final wallsPlaced = gameState.walls.length;

    // Update statistics
    add(
      UpdateStatistics(
        isWin: isWin,
        difficulty: gameState.aiDifficulty,
        gameDuration: gameDuration,
        totalMoves: totalMoves,
        wallsPlaced: wallsPlaced,
      ),
    );

    emit(
      GameOverState(
        gameState: gameState,
        winner: gameState.winner ?? 'Unknown',
        totalMoves: totalMoves,
        gameDuration: gameDuration,
      ),
    );

    // Play win sound
    if (CacheHelper.getData(key: 'enableSound') ?? true) {
      GameSounds.triggerFeedback(soundKey: 'win');
    }
  }

  // Helper method to add state to move history
  void _addToMoveHistory(GameState gameState) {
    // Remove any moves after current index (for redo functionality)
    if (_currentMoveIndex < _moveHistory.length - 1) {
      _moveHistory = _moveHistory.sublist(0, _currentMoveIndex + 1);
    }

    _moveHistory.add(gameState);
    _currentMoveIndex = _moveHistory.length - 1;
    _lastValidState = gameState;
  }

  @override
  Future<void> close() {
    _aiTimer?.cancel();
    return super.close();
  }

  // HydratedBloc persistence methods
  @override
  GameStates? fromJson(Map<String, dynamic> json) {
    try {
      final stateType = json['stateType'] as String;
      final stateData = json['stateData'] as Map<String, dynamic>;

      switch (stateType) {
        case 'GamePlayingState':
          return GamePlayingState(
            gameState: GameState.fromJson(stateData['gameState']),
            isPlayerTurn: stateData['isPlayerTurn'] as bool,
            showValidMoves: stateData['showValidMoves'] as bool,
            validMoves: (stateData['validMoves'] as List)
                .map((e) => Position.fromJson(e))
                .toList(),
            previewWall: stateData['previewWall'] != null
                ? Wall.fromJson(stateData['previewWall'])
                : null,
            currentMessage: stateData['currentMessage'] as String?,
          );
        case 'GameSettingsState':
          return GameSettingsState(
            aiDifficulty: AIDifficulty.values[stateData['aiDifficulty'] as int],
            showValidMoves: stateData['showValidMoves'] as bool,
            enableSound: stateData['enableSound'] as bool,
            enableHapticFeedback: stateData['enableHapticFeedback'] as bool,
            language: stateData['language'] as String,
            isDarkMode: stateData['isDarkMode'] as bool,
          );
        default:
          return const GameInitialState();
      }
    } catch (e) {
      return const GameInitialState();
    }
  }

  @override
  Map<String, dynamic>? toJson(GameStates state) {
    if (state is GamePlayingState) {
      return {
        'stateType': 'GamePlayingState',
        'stateData': {
          'gameState': state.gameState.toJson(),
          'isPlayerTurn': state.isPlayerTurn,
          'showValidMoves': state.showValidMoves,
          'validMoves': state.validMoves.map((e) => e.toJson()).toList(),
          'previewWall': state.previewWall?.toJson(),
          'currentMessage': state.currentMessage,
        },
      };
    } else if (state is GameSettingsState) {
      return {
        'stateType': 'GameSettingsState',
        'stateData': {
          'aiDifficulty': state.aiDifficulty.index,
          'showValidMoves': state.showValidMoves,
          'enableSound': state.enableSound,
          'enableHapticFeedback': state.enableHapticFeedback,
          'language': state.language,
          'isDarkMode': state.isDarkMode,
        },
      };
    }
    return null;
  }
}
