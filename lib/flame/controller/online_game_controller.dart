import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants.dart';
import '../models/game_state.dart';
import '../models/room_state.dart';
import '../services/online_game_service.dart';
import '../services/sounds.dart';
import '../services/local_storage.dart';
import 'online_game_events.dart';
import 'online_game_states.dart';

class OnlineGameController
    extends HydratedBloc<OnlineGameEvent, OnlineGameStates> {
  StreamSubscription<RoomState>? _roomSubscription;
  StreamSubscription<GameState>? _gameSubscription;
  Timer? _heartbeatTimer;
  DateTime? _gameStartTime;
  OnlineGameStates? _lastValidState;

  OnlineGameController() : super(OnlineGameInitialState()) {
    on<CreateRoom>(_onCreateRoom);
    on<JoinRoom>(_onJoinRoom);
    on<LeaveRoom>(_onLeaveRoom);
    on<SetPlayerReady>(_onSetPlayerReady);
    on<StartOnlineGame>(_onStartOnlineGame);
    on<MakeOnlineMove>(_onMakeOnlineMove);
    on<WatchRoom>(_onWatchRoom);
    on<WatchGame>(_onWatchGame);
    on<GetAvailableRooms>(_onGetAvailableRooms);
    on<ConnectToOnlineGame>(_onConnectToOnlineGame);
    on<DisconnectFromOnlineGame>(_onDisconnectFromOnlineGame);
    on<UpdatePlayerStatus>(_onUpdatePlayerStatus);
    on<SendChatMessage>(_onSendChatMessage);
    on<KickPlayer>(_onKickPlayer);
    on<TransferOwnership>(_onTransferOwnership);
    on<UpdateRoomSettings>(_onUpdateRoomSettings);
  }

  // Create a new room
  Future<void> _onCreateRoom(
    CreateRoom event,
    Emitter<OnlineGameStates> emit,
  ) async {
    print('DEBUG: Creating room: ${event.roomName}');
    emit(OnlineGameLoadingState(message: 'Creating room...'));

    try {
      final roomId = await OnlineGameService.createRoom(
        roomName: event.roomName,
        maxPlayers: event.maxPlayers,
        isPrivate: event.isPrivate,
      );

      print('DEBUG: Room created with ID: $roomId');

      if (roomId != null) {
        // Start watching the room
        print('DEBUG: Starting to watch room: $roomId');
        add(WatchRoom(roomId));
      } else {
        print('DEBUG: Failed to create room - roomId is null');
        emit(
          OnlineGameErrorState(
            error: 'Failed to create room',
            suggestion: 'Please check your connection and try again',
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error creating room: $e');
      emit(
        OnlineGameErrorState(
          error: 'Error creating room: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Join an existing room
  Future<void> _onJoinRoom(
    JoinRoom event,
    Emitter<OnlineGameStates> emit,
  ) async {
    emit(OnlineGameLoadingState(message: 'Joining room...'));

    try {
      final success = await OnlineGameService.joinRoom(event.roomId);

      if (success) {
        // Start watching the room
        add(WatchRoom(event.roomId));
      } else {
        emit(
          OnlineGameErrorState(
            error: 'Failed to join room',
            suggestion: 'Room may be full or no longer available',
          ),
        );
      }
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error joining room: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Leave current room
  Future<void> _onLeaveRoom(
    LeaveRoom event,
    Emitter<OnlineGameStates> emit,
  ) async {
    try {
      await OnlineGameService.leaveRoom();
      _disconnectFromCurrentRoom();
      emit(OnlineGameInitialState());
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error leaving room: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Set player ready status
  Future<void> _onSetPlayerReady(
    SetPlayerReady event,
    Emitter<OnlineGameStates> emit,
  ) async {
    try {
      await OnlineGameService.setPlayerReady(event.isReady);
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error setting ready status: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Start the online game
  Future<void> _onStartOnlineGame(
    StartOnlineGame event,
    Emitter<OnlineGameStates> emit,
  ) async {
    try {
      final gameId = await OnlineGameService.startGame();

      if (gameId != null) {
        _gameStartTime = DateTime.now();
        // Start watching the game
        add(WatchGame(gameId));
      } else {
        emit(
          OnlineGameErrorState(
            error: 'Failed to start game',
            suggestion: 'Make sure all players are ready',
          ),
        );
      }
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error starting game: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Make a move in the online game
  Future<void> _onMakeOnlineMove(
    MakeOnlineMove event,
    Emitter<OnlineGameStates> emit,
  ) async {
    final currentState = state;
    if (currentState is! OnlineGamePlayingState) return;

    // Validate that it's the player's turn
    if (!currentState.isMyTurn) {
      emit(currentState.copyWith(currentMessage: 'Not your turn'));
      HapticFeedback.lightImpact();
      return;
    }

    try {
      final success = await OnlineGameService.makeMove(event.move);

      if (success) {
        // Play sound
        if (CacheHelper.getData(key: 'enableSound') ?? true) {
          final playerId = event.move.playerId;
          final soundKey = playerId == 1 ? 'move_p1' : 'move_p2';
          GameSounds.triggerFeedback(soundKey: soundKey);
        }
      } else {
        emit(currentState.copyWith(currentMessage: 'Invalid move'));
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error making move: $e',
          suggestion: 'Please try again',
          lastValidState: currentState,
        ),
      );
    }
  }

  // Watch room state changes
  void _onWatchRoom(WatchRoom event, Emitter<OnlineGameStates> emit) {
    print('DEBUG: Starting to watch room: ${event.roomId}');
    _roomSubscription?.cancel();

    _roomSubscription = OnlineGameService.watchRoom(event.roomId).listen(
      (roomState) {
        print('DEBUG: Room state received from stream: ${roomState.roomName}');
        if (roomState != null) {
          // Process the room state directly in the stream listener
          print('DEBUG: Processing room state update');
          _processRoomStateUpdate(roomState);
        } else {
          print('DEBUG: Room state is null');
        }
      },
      onError: (error) {
        print('DEBUG: Error watching room: $error');
        // Handle error by emitting error state directly
        emit(
          OnlineGameErrorState(
            error: 'Error watching room: $error',
            suggestion: 'Please check your connection',
          ),
        );
      },
    );
  }

  // Process room state update without emit parameter
  void _processRoomStateUpdate(RoomState roomState) {
    print('DEBUG: Room state update received: ${roomState.roomName}');
    print('DEBUG: Room status: ${roomState.status}');
    print('DEBUG: Players: ${roomState.players.length}');
    print('DEBUG: Can start: ${roomState.canStart}');

    final currentUser = FirebaseAuth.instance.currentUser;
    print('DEBUG: Current user: ${currentUser?.uid}');

    final isHost = roomState.isHost;
    print('DEBUG: Is host: $isHost');

    final myPlayer = roomState.players.firstWhere(
      (p) => p.userId == currentUser?.uid,
      orElse: () => roomState.players.first,
    );
    final isReady = myPlayer.isReady;
    print('DEBUG: My player ready: $isReady');

    if (roomState.status == GameStatus.waiting) {
      if (roomState.canStart && isHost) {
        print('DEBUG: Emitting WaitingForPlayersState');
        emit(
          WaitingForPlayersState(
            roomState: roomState,
            isHost: isHost,
            readyPlayers: roomState.players
                .where((p) => p.isReady)
                .map((p) => p.displayName)
                .toList(),
            notReadyPlayers: roomState.players
                .where((p) => !p.isReady)
                .map((p) => p.displayName)
                .toList(),
          ),
        );
      } else {
        print('DEBUG: Emitting RoomLobbyState');
        emit(
          RoomLobbyState(
            roomState: roomState,
            isHost: isHost,
            isReady: isReady,
          ),
        );
      }
    } else if (roomState.status == GameStatus.playing) {
      // Game is already started, watch for game state
      if (OnlineGameService.currentGameId != null) {
        add(WatchGame(OnlineGameService.currentGameId!));
      }
    }
  }

  // Watch game state changes
  void _onWatchGame(WatchGame event, Emitter<OnlineGameStates> emit) {
    _gameSubscription?.cancel();
    _gameSubscription = OnlineGameService.watchGame(event.gameId).listen(
      (gameState) {
        if (gameState != null && !emit.isDone) {
          _handleGameStateUpdate(gameState, emit);
        }
      },
      onError: (error) {
        if (!emit.isDone) {
          emit(
            OnlineGameErrorState(
              error: 'Error watching game: $error',
              suggestion: 'Please check your connection',
            ),
          );
        }
      },
    );
  }

  // Get available rooms
  Future<void> _onGetAvailableRooms(
    GetAvailableRooms event,
    Emitter<OnlineGameStates> emit,
  ) async {
    emit(RoomSelectionState(availableRooms: [], isLoading: true));

    try {
      final rooms = await OnlineGameService.getAvailableRooms();
      emit(RoomSelectionState(availableRooms: rooms, isLoading: false));
    } catch (e) {
      emit(
        OnlineGameErrorState(
          error: 'Error loading rooms: $e',
          suggestion: 'Please try again',
        ),
      );
    }
  }

  // Connect to online game
  void _onConnectToOnlineGame(
    ConnectToOnlineGame event,
    Emitter<OnlineGameStates> emit,
  ) {
    // Start heartbeat timer
    _startHeartbeat();

    // Start watching the game
    add(WatchGame(event.gameId));
  }

  // Disconnect from online game
  void _onDisconnectFromOnlineGame(
    DisconnectFromOnlineGame event,
    Emitter<OnlineGameStates> emit,
  ) {
    _disconnectFromCurrentRoom();
    emit(
      OnlineGameDisconnectedState(
        reason: 'Disconnected from game',
        lastValidState: _lastValidState,
      ),
    );
  }

  // Update player status
  Future<void> _onUpdatePlayerStatus(
    UpdatePlayerStatus event,
    Emitter<OnlineGameStates> emit,
  ) async {
    // This would typically update the player's online status
    // Implementation depends on your specific requirements
  }

  // Send chat message
  void _onSendChatMessage(
    SendChatMessage event,
    Emitter<OnlineGameStates> emit,
  ) {
    // This would typically send a chat message to other players
    // Implementation depends on your specific requirements
  }

  // Kick player from room
  Future<void> _onKickPlayer(
    KickPlayer event,
    Emitter<OnlineGameStates> emit,
  ) async {
    // This would typically kick a player from the room
    // Implementation depends on your specific requirements
  }

  // Transfer room ownership
  Future<void> _onTransferOwnership(
    TransferOwnership event,
    Emitter<OnlineGameStates> emit,
  ) async {
    // This would typically transfer room ownership
    // Implementation depends on your specific requirements
  }

  // Update room settings
  Future<void> _onUpdateRoomSettings(
    UpdateRoomSettings event,
    Emitter<OnlineGameStates> emit,
  ) async {
    // This would typically update room settings
    // Implementation depends on your specific requirements
  }

  // Handle room state updates
  void _handleRoomStateUpdate(
    RoomState roomState,
    Emitter<OnlineGameStates> emit,
  ) {
    if (emit.isDone) return;

    print('DEBUG: Room state update received: ${roomState.roomName}');
    print('DEBUG: Room status: ${roomState.status}');
    print('DEBUG: Players: ${roomState.players.length}');
    print('DEBUG: Can start: ${roomState.canStart}');

    final currentState = state;
    final currentUser = FirebaseAuth.instance.currentUser;
    print('DEBUG: Current user: ${currentUser?.uid}');

    final isHost = roomState.isHost;
    print('DEBUG: Is host: $isHost');

    final myPlayer = roomState.players.firstWhere(
      (p) => p.userId == currentUser?.uid,
      orElse: () => roomState.players.first,
    );
    final isReady = myPlayer.isReady;
    print('DEBUG: My player ready: $isReady');

    if (roomState.status == GameStatus.waiting) {
      if (roomState.canStart && isHost) {
        print('DEBUG: Emitting WaitingForPlayersState');
        if (!emit.isDone) {
          emit(
            WaitingForPlayersState(
              roomState: roomState,
              isHost: isHost,
              readyPlayers: roomState.players
                  .where((p) => p.isReady)
                  .map((p) => p.displayName)
                  .toList(),
              notReadyPlayers: roomState.players
                  .where((p) => !p.isReady)
                  .map((p) => p.displayName)
                  .toList(),
            ),
          );
        }
      } else {
        print('DEBUG: Emitting RoomLobbyState');
        if (!emit.isDone) {
          emit(
            RoomLobbyState(
              roomState: roomState,
              isHost: isHost,
              isReady: isReady,
            ),
          );
        }
      }
    } else if (roomState.status == GameStatus.playing) {
      // Game is already started, watch for game state
      if (OnlineGameService.currentGameId != null) {
        add(WatchGame(OnlineGameService.currentGameId!));
      }
    }
  }

  // Handle game state updates
  void _handleGameStateUpdate(
    GameState gameState,
    Emitter<OnlineGameStates> emit,
  ) {
    if (emit.isDone) return;

    final currentState = state;
    final myPlayerId = OnlineGameService.currentPlayerId;
    final isMyTurn = gameState.currentPlayerId == myPlayerId;
    final isHost =
        gameState.players.firstWhere((p) => p.id == myPlayerId).name == 'Host';

    if (gameState.isGameOver) {
      _handleGameOver(gameState, emit);
      return;
    }

    final validMoves = gameState.getValidMoves(
      gameState.currentPlayer.position,
    );

    if (currentState is OnlineGamePlayingState) {
      if (!emit.isDone) {
        emit(
          currentState.copyWith(
            gameState: gameState,
            isMyTurn: isMyTurn,
            validMoves: validMoves,
          ),
        );
      }
    } else {
      if (!emit.isDone) {
        emit(
          OnlineGamePlayingState(
            gameState: gameState,
            roomState: RoomState(
              roomId: OnlineGameService.currentRoomId ?? '',
              roomName: 'Game Room',
              players: gameState.players
                  .map(
                    (p) => RoomPlayer(
                      userId: p.name,
                      displayName: p.name,
                      playerId: p.id,
                    ),
                  )
                  .toList(),
            ),
            isMyTurn: isMyTurn,
            isHost: isHost,
            myPlayerId: myPlayerId ?? 1,
            validMoves: validMoves,
          ),
        );
      }
    }

    _lastValidState = state;
  }

  // Handle game over
  void _handleGameOver(GameState gameState, Emitter<OnlineGameStates> emit) {
    if (emit.isDone) return;

    final gameDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!)
        : Duration.zero;

    final winner = gameState.winner ?? 'Unknown';
    final totalMoves = gameState.moveHistory.length;
    final isHost =
        gameState.players
            .firstWhere((p) => p.id == OnlineGameService.currentPlayerId)
            .name ==
        'Host';

    if (!emit.isDone) {
      emit(
        OnlineGameOverState(
          gameState: gameState,
          roomState: RoomState(
            roomId: OnlineGameService.currentRoomId ?? '',
            roomName: 'Game Room',
            players: gameState.players
                .map(
                  (p) => RoomPlayer(
                    userId: p.name,
                    displayName: p.name,
                    playerId: p.id,
                  ),
                )
                .toList(),
          ),
          winner: winner,
          totalMoves: totalMoves,
          gameDuration: gameDuration,
          isHost: isHost,
        ),
      );
    }

    // Play win sound
    if (CacheHelper.getData(key: 'enableSound') ?? true) {
      GameSounds.triggerFeedback(soundKey: 'win');
    }
  }

  // Start heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      add(UpdatePlayerStatus(isOnline: true, lastSeen: DateTime.now()));
    });
  }

  // Disconnect from current room
  void _disconnectFromCurrentRoom() {
    _roomSubscription?.cancel();
    _gameSubscription?.cancel();
    _heartbeatTimer?.cancel();
    OnlineGameService.dispose();
  }

  @override
  Future<void> close() {
    _disconnectFromCurrentRoom();
    return super.close();
  }

  // HydratedBloc persistence methods
  @override
  OnlineGameStates? fromJson(Map<String, dynamic> json) {
    // Implement persistence if needed
    return null;
  }

  @override
  Map<String, dynamic>? toJson(OnlineGameStates state) {
    // Implement persistence if needed
    return null;
  }
}
