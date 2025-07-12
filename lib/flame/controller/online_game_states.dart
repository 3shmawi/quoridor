import '../models/room_state.dart';
import '../models/game_state.dart';
import '../constants.dart';

// Online game states
abstract class OnlineGameStates {}

// Initial state
class OnlineGameInitialState extends OnlineGameStates {}

// Loading state
class OnlineGameLoadingState extends OnlineGameStates {
  final String message;

  OnlineGameLoadingState({required this.message});
}

// Room lobby state
class RoomLobbyState extends OnlineGameStates {
  final RoomState roomState;
  final bool isHost;
  final bool isReady;
  final List<RoomState> availableRooms;

  RoomLobbyState({
    required this.roomState,
    required this.isHost,
    required this.isReady,
    this.availableRooms = const [],
  });
}

// Online game playing state
class OnlineGamePlayingState extends OnlineGameStates {
  final GameState gameState;
  final RoomState roomState;
  final bool isMyTurn;
  final bool isHost;
  final int myPlayerId;
  final List<String> chatMessages;
  final bool showValidMoves;
  final List<Position> validMoves;
  final Wall? previewWall;
  final String? currentMessage;

  OnlineGamePlayingState({
    required this.gameState,
    required this.roomState,
    required this.isMyTurn,
    required this.isHost,
    required this.myPlayerId,
    this.chatMessages = const [],
    this.showValidMoves = true,
    this.validMoves = const [],
    this.previewWall,
    this.currentMessage,
  });

  OnlineGamePlayingState copyWith({
    GameState? gameState,
    RoomState? roomState,
    bool? isMyTurn,
    bool? isHost,
    int? myPlayerId,
    List<String>? chatMessages,
    bool? showValidMoves,
    List<Position>? validMoves,
    Wall? previewWall,
    String? currentMessage,
  }) {
    return OnlineGamePlayingState(
      gameState: gameState ?? this.gameState,
      roomState: roomState ?? this.roomState,
      isMyTurn: isMyTurn ?? this.isMyTurn,
      isHost: isHost ?? this.isHost,
      myPlayerId: myPlayerId ?? this.myPlayerId,
      chatMessages: chatMessages ?? this.chatMessages,
      showValidMoves: showValidMoves ?? this.showValidMoves,
      validMoves: validMoves ?? this.validMoves,
      previewWall: previewWall ?? this.previewWall,
      currentMessage: currentMessage ?? this.currentMessage,
    );
  }
}

// Online game over state
class OnlineGameOverState extends OnlineGameStates {
  final GameState gameState;
  final RoomState roomState;
  final String winner;
  final int totalMoves;
  final Duration gameDuration;
  final bool isHost;

  OnlineGameOverState({
    required this.gameState,
    required this.roomState,
    required this.winner,
    required this.totalMoves,
    required this.gameDuration,
    required this.isHost,
  });
}

// Room selection state
class RoomSelectionState extends OnlineGameStates {
  final List<RoomState> availableRooms;
  final bool isLoading;

  RoomSelectionState({required this.availableRooms, this.isLoading = false});
}

// Error state
class OnlineGameErrorState extends OnlineGameStates {
  final String error;
  final String suggestion;
  final OnlineGameStates? lastValidState;

  OnlineGameErrorState({
    required this.error,
    required this.suggestion,
    this.lastValidState,
  });
}

// Disconnected state
class OnlineGameDisconnectedState extends OnlineGameStates {
  final String reason;
  final OnlineGameStates? lastValidState;

  OnlineGameDisconnectedState({required this.reason, this.lastValidState});
}

// Waiting for players state
class WaitingForPlayersState extends OnlineGameStates {
  final RoomState roomState;
  final bool isHost;
  final List<String> readyPlayers;
  final List<String> notReadyPlayers;

  WaitingForPlayersState({
    required this.roomState,
    required this.isHost,
    required this.readyPlayers,
    required this.notReadyPlayers,
  });
}
