import 'package:equatable/equatable.dart';

import '../constants.dart';
import '../models/game_state.dart';
import '../services/ai_service.dart';

// Base abstract class for all game states
abstract class GameStates extends Equatable {
  const GameStates();

  @override
  List<Object?> get props => [];
}

// Initial state when the game is first loaded
class GameInitialState extends GameStates {
  const GameInitialState();
}

// Loading state while initializing the game
class GameLoadingState extends GameStates {
  final String message;

  const GameLoadingState({this.message = 'Loading game...'});

  @override
  List<Object?> get props => [message];
}

// Active playing state
class GamePlayingState extends GameStates {
  final GameState gameState;
  final bool isPlayerTurn;
  final bool showValidMoves;
  final List<Position> validMoves;
  final Wall? previewWall;
  final String? currentMessage;

  const GamePlayingState({
    required this.gameState,
    required this.isPlayerTurn,
    this.showValidMoves = true,
    this.validMoves = const [],
    this.previewWall,
    this.currentMessage,
  });

  @override
  List<Object?> get props => [
    gameState,
    isPlayerTurn,
    showValidMoves,
    validMoves,
    previewWall,
    currentMessage,
  ];

  GamePlayingState copyWith({
    GameState? gameState,
    bool? isPlayerTurn,
    bool? showValidMoves,
    List<Position>? validMoves,
    Wall? previewWall,
    String? currentMessage,
  }) {
    return GamePlayingState(
      gameState: gameState ?? this.gameState,
      isPlayerTurn: isPlayerTurn ?? this.isPlayerTurn,
      showValidMoves: showValidMoves ?? this.showValidMoves,
      validMoves: validMoves ?? this.validMoves,
      previewWall: previewWall ?? this.previewWall,
      currentMessage: currentMessage ?? this.currentMessage,
    );
  }
}

// AI thinking state
class GameAIThinkingState extends GameStates {
  final GameState gameState;
  final AIDifficulty difficulty;
  final String message;

  const GameAIThinkingState({
    required this.gameState,
    required this.difficulty,
    this.message = 'AI is thinking...',
  });

  @override
  List<Object?> get props => [gameState, difficulty, message];
}

// Game over state
class GameOverState extends GameStates {
  final GameState gameState;
  final String winner;
  final bool isDraw;
  final int totalMoves;
  final Duration gameDuration;

  const GameOverState({
    required this.gameState,
    required this.winner,
    this.isDraw = false,
    required this.totalMoves,
    required this.gameDuration,
  });

  @override
  List<Object?> get props => [
    gameState,
    winner,
    isDraw,
    totalMoves,
    gameDuration,
  ];
}

// Paused state
class GamePausedState extends GameStates {
  final GameState gameState;
  final String reason;

  const GamePausedState({required this.gameState, this.reason = 'Game paused'});

  @override
  List<Object?> get props => [gameState, reason];
}

// Error state
class GameErrorState extends GameStates {
  final String error;
  final String? suggestion;
  final GameState? lastValidState;

  const GameErrorState({
    required this.error,
    this.suggestion,
    this.lastValidState,
  });

  @override
  List<Object?> get props => [error, suggestion, lastValidState];
}

// Settings state
class GameSettingsState extends GameStates {
  final AIDifficulty aiDifficulty;
  final bool showValidMoves;
  final bool enableSound;
  final bool enableHapticFeedback;
  final String language;
  final bool isDarkMode;

  const GameSettingsState({
    this.aiDifficulty = AIDifficulty.medium,
    this.showValidMoves = true,
    this.enableSound = true,
    this.enableHapticFeedback = true,
    this.language = 'en',
    this.isDarkMode = false,
  });

  @override
  List<Object?> get props => [
    aiDifficulty,
    showValidMoves,
    enableSound,
    enableHapticFeedback,
    language,
    isDarkMode,
  ];

  GameSettingsState copyWith({
    AIDifficulty? aiDifficulty,
    bool? showValidMoves,
    bool? enableSound,
    bool? enableHapticFeedback,
    String? language,
    bool? isDarkMode,
  }) {
    return GameSettingsState(
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      showValidMoves: showValidMoves ?? this.showValidMoves,
      enableSound: enableSound ?? this.enableSound,
      enableHapticFeedback: enableHapticFeedback ?? this.enableHapticFeedback,
      language: language ?? this.language,
      isDarkMode: isDarkMode ?? this.isDarkMode,
    );
  }
}

// Game statistics state
class GameStatisticsState extends GameStates {
  final int gamesPlayed;
  final int gamesWon;
  final int gamesLost;
  final int gamesDrawn;
  final double winRate;
  final Duration averageGameTime;
  final int totalWallsPlaced;
  final int totalMovesMade;
  final Map<AIDifficulty, int> winsByDifficulty;
  final String? winner;

  const GameStatisticsState({
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.gamesLost = 0,
    this.gamesDrawn = 0,
    this.winRate = 0.0,
    this.averageGameTime = Duration.zero,
    this.totalWallsPlaced = 0,
    this.totalMovesMade = 0,
    this.winsByDifficulty = const {},
    this.winner,
  });

  @override
  List<Object?> get props => [
    gamesPlayed,
    gamesWon,
    gamesLost,
    gamesDrawn,
    winRate,
    averageGameTime,
    totalWallsPlaced,
    totalMovesMade,
    winsByDifficulty,
  ];
}
