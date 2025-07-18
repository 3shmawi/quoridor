import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../constants.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/room_state.dart';

class OnlineGameService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  static const String _roomsCollection = 'game_rooms';
  static const String _gamesCollection = 'online_games';
  static const String _playersCollection = 'room_players';

  // Stream controllers for real-time updates
  static final Map<String, StreamController<GameState>> _gameStreams = {};
  static final Map<String, StreamController<RoomState>> _roomStreams = {};

  // Cache latest room states for immediate emission to new listeners
  static final Map<String, RoomState> _latestRoomStates = {};

  // Current room and game subscriptions
  static StreamSubscription<DocumentSnapshot>? _currentRoomSubscription;
  static StreamSubscription<DocumentSnapshot>? _currentGameSubscription;

  // Current user's room and game info
  static String? _currentRoomId;
  static String? _currentGameId;
  static int? _currentPlayerId;

  // Create a new game room
  static Future<String?> createRoom({
    required String roomName,
    int maxPlayers = 2,
    bool isPrivate = false,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('DEBUG: No current user found');
        return null;
      }

      print('DEBUG: Creating room for user: ${user.uid}');
      final roomId = _firestore.collection(_roomsCollection).doc().id;
      final roomPlayer = RoomPlayer(
        userId: user.uid,
        displayName: user.displayName ?? 'Player ${user.uid.substring(0, 6)}',
        playerId: 1,
        isReady: true,
      );

      final roomState = RoomState(
        roomId: roomId,
        roomName: roomName,
        players: [roomPlayer],
        maxPlayers: maxPlayers,
        isPrivate: isPrivate,
        hostId: user.uid,
      );

      print('DEBUG: Saving room to Firestore: $roomId');
      await _firestore
          .collection(_roomsCollection)
          .doc(roomId)
          .set(roomState.toJson());

      _currentRoomId = roomId;
      _currentPlayerId = 1;

      print('DEBUG: Room created successfully: $roomId');
      return roomId;
    } catch (e) {
      print('Error creating room: $e');
      return null;
    }
  }

  // Join an existing room
  static Future<bool> joinRoom(String roomId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final roomDoc = await _firestore
          .collection(_roomsCollection)
          .doc(roomId)
          .get();

      if (!roomDoc.exists) return false;

      final roomState = RoomState.fromJson(roomDoc.data()!);

      if (roomState.isFull) return false;

      // Check if user is already in the room
      final existingPlayer = roomState.players
          .where((p) => p.userId == user.uid)
          .firstOrNull;

      if (existingPlayer != null) {
        _currentRoomId = roomId;
        _currentPlayerId = existingPlayer.playerId;
        return true;
      }

      // Add new player
      final newPlayerId = roomState.players.length + 1;
      final newPlayer = RoomPlayer(
        userId: user.uid,
        displayName: user.displayName ?? 'Player ${user.uid.substring(0, 6)}',
        playerId: newPlayerId,
      );

      final updatedPlayers = [...roomState.players, newPlayer];
      final updatedRoomState = RoomState(
        roomId: roomState.roomId,
        roomName: roomState.roomName,
        players: updatedPlayers,
        status: roomState.status,
        createdAt: roomState.createdAt,
        updatedAt: DateTime.now(),
        maxPlayers: roomState.maxPlayers,
        isPrivate: roomState.isPrivate,
        hostId: roomState.hostId,
      );

      await _firestore
          .collection(_roomsCollection)
          .doc(roomId)
          .update(updatedRoomState.toJson());

      _currentRoomId = roomId;
      _currentPlayerId = newPlayerId;

      return true;
    } catch (e) {
      print('Error joining room: $e');
      return false;
    }
  }

  // Leave current room
  static Future<void> leaveRoom() async {
    try {
      if (_currentRoomId == null) return;

      final user = _auth.currentUser;
      if (user == null) return;

      final roomDoc = await _firestore
          .collection(_roomsCollection)
          .doc(_currentRoomId!)
          .get();

      if (roomDoc.exists) {
        final roomState = RoomState.fromJson(roomDoc.data()!);
        final updatedPlayers = roomState.players
            .where((p) => p.userId != user.uid)
            .toList();

        if (updatedPlayers.isEmpty) {
          // Delete room if empty
          await _firestore
              .collection(_roomsCollection)
              .doc(_currentRoomId!)
              .delete();
        } else {
          // Update room with remaining players
          final updatedRoomState = RoomState(
            roomId: roomState.roomId,
            roomName: roomState.roomName,
            players: updatedPlayers,
            status: roomState.status,
            createdAt: roomState.createdAt,
            updatedAt: DateTime.now(),
            maxPlayers: roomState.maxPlayers,
            isPrivate: roomState.isPrivate,
            hostId: updatedPlayers.first.userId, // New host
          );

          await _firestore
              .collection(_roomsCollection)
              .doc(_currentRoomId!)
              .update(updatedRoomState.toJson());
        }
      }

      _disconnectFromCurrentRoom();
    } catch (e) {
      print('Error leaving room: $e');
    }
  }

  // Start the game
  static Future<String?> startGame() async {
    try {
      print('DEBUG: startGame() called');
      print('DEBUG: Current room ID: $_currentRoomId');

      if (_currentRoomId == null) {
        print('DEBUG: No current room ID, returning null');
        return null;
      }

      print('DEBUG: Getting room document');
      final roomDoc = await _firestore
          .collection(_roomsCollection)
          .doc(_currentRoomId!)
          .get();

      if (!roomDoc.exists) {
        print('DEBUG: Room document does not exist, returning null');
        return null;
      }

      print('DEBUG: Parsing room state');
      final roomState = RoomState.fromJson(roomDoc.data()!);
      print('DEBUG: Room can start: ${roomState.canStart}');

      if (!roomState.canStart) {
        print('DEBUG: Room cannot start, returning null');
        return null;
      }

      print('DEBUG: Creating game state');
      // Create game state
      final players = roomState.players.map((rp) {
        return Player(
          id: rp.playerId,
          name: rp.displayName,
          position: _getStartingPosition(rp.playerId),
          wallsRemaining: GameConstants.getWallsForPlayerCount(
            roomState.players.length,
          ),
          goalRow: _getGoalRow(rp.playerId),
          goalCol: _getGoalCol(rp.playerId),
          isAI: false,
        );
      }).toList();

      final gameState = GameState(
        gameId: _firestore.collection(_gamesCollection).doc().id,
        players: players,
        currentPlayerId: 1,
        status: GameStatus.playing,
      );

      print('DEBUG: Saving game to Firestore');
      // Save game
      await _firestore
          .collection(_gamesCollection)
          .doc(gameState.gameId)
          .set(gameState.toJson());

      print('DEBUG: Updating room status to playing');
      // Update room status
      await _firestore
          .collection(_roomsCollection)
          .doc(_currentRoomId!)
          .update({
            'status': GameStatus.playing.index,
            'gameId': gameState.gameId,
            'updatedAt': DateTime.now().toIso8601String(),
          });

      _currentGameId = gameState.gameId;
      print('DEBUG: Game started successfully, ID: ${gameState.gameId}');

      return gameState.gameId;
    } catch (e) {
      print('DEBUG: Error starting game: $e');
      return null;
    }
  }

  // Make a move in the online game
  static Future<bool> makeMove(GameMove move) async {
    try {
      if (_currentGameId == null) return false;

      final gameDoc = await _firestore
          .collection(_gamesCollection)
          .doc(_currentGameId!)
          .get();

      if (!gameDoc.exists) return false;

      final gameState = GameState.fromJson(gameDoc.data()!);

      // Validate that it's the current player's turn
      if (gameState.currentPlayerId != _currentPlayerId) return false;

      // Execute the move
      final updatedGameState = _executeMove(gameState, move);

      // Save updated game state
      await _firestore
          .collection(_gamesCollection)
          .doc(_currentGameId!)
          .update(updatedGameState.toJson());

      return true;
    } catch (e) {
      print('Error making move: $e');
      return false;
    }
  }

  // Watch room state changes
  static Stream<RoomState> watchRoom(String roomId) {
    print('DEBUG: Setting up watch for room: $roomId');

    if (_roomStreams.containsKey(roomId)) {
      print('DEBUG: Using existing stream for room: $roomId');
      final existingStream = _roomStreams[roomId]!.stream;
      print('DEBUG: Returning existing broadcast stream');

      // If we have cached data, emit it immediately to the new listener
      if (_latestRoomStates.containsKey(roomId)) {
        print('DEBUG: Emitting cached room state to new listener');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _roomStreams[roomId]!.add(_latestRoomStates[roomId]!);
        });
      }

      return existingStream;
    }

    print('DEBUG: Creating new stream for room: $roomId');
    final controller = StreamController<RoomState>.broadcast();
    _roomStreams[roomId] = controller;

    print('DEBUG: Setting up Firestore listener for room: $roomId');
    _currentRoomSubscription = _firestore
        .collection(_roomsCollection)
        .doc(roomId)
        .snapshots()
        .listen(
          (snapshot) {
            print('DEBUG: Firestore snapshot received for room: $roomId');
            print('DEBUG: Snapshot exists: ${snapshot.exists}');
            print('DEBUG: Snapshot data: ${snapshot.data()}');

            if (snapshot.exists && snapshot.data() != null) {
              final roomState = RoomState.fromJson(snapshot.data()!);
              print(
                'DEBUG: Emitting room state to stream: ${roomState.roomName}',
              );
              print('DEBUG: Adding room state to broadcast stream controller');

              // Cache the latest room state
              _latestRoomStates[roomId] = roomState;

              controller.add(roomState);
              print('DEBUG: Room state emitted to stream');
            } else {
              print('DEBUG: Snapshot is empty or null');
            }
          },
          onError: (error) {
            print('DEBUG: Firestore listener error: $error');
          },
        );

    print('DEBUG: Stream created and Firestore listener set up');
    return controller.stream;
  }

  // Watch game state changes
  static Stream<GameState> watchGame(String gameId) {
    if (_gameStreams.containsKey(gameId)) {
      return _gameStreams[gameId]!.stream;
    }

    final controller = StreamController<GameState>.broadcast();
    _gameStreams[gameId] = controller;

    _currentGameSubscription = _firestore
        .collection(_gamesCollection)
        .doc(gameId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final gameState = GameState.fromJson(snapshot.data()!);
            controller.add(gameState);
          }
        });

    return controller.stream;
  }

  // Set player ready status
  static Future<void> setPlayerReady(bool isReady) async {
    try {
      print('DEBUG: setPlayerReady called with isReady: $isReady');
      print('DEBUG: Current room ID: $_currentRoomId');

      if (_currentRoomId == null) {
        print('DEBUG: No current room ID, returning');
        return;
      }

      final user = _auth.currentUser;
      if (user == null) {
        print('DEBUG: No current user, returning');
        return;
      }

      print('DEBUG: Getting room document for: $_currentRoomId');
      final roomDoc = await _firestore
          .collection(_roomsCollection)
          .doc(_currentRoomId!)
          .get();

      if (roomDoc.exists) {
        print('DEBUG: Room document exists, updating ready status');
        final roomState = RoomState.fromJson(roomDoc.data()!);
        print('DEBUG: Current players: ${roomState.players.length}');

        final updatedPlayers = roomState.players.map((p) {
          if (p.userId == user.uid) {
            print(
              'DEBUG: Updating player ${p.displayName} ready status to: $isReady',
            );
            return p.copyWith(isReady: isReady);
          }
          return p;
        }).toList();

        final updatedRoomState = RoomState(
          roomId: roomState.roomId,
          roomName: roomState.roomName,
          players: updatedPlayers,
          status: roomState.status,
          createdAt: roomState.createdAt,
          updatedAt: DateTime.now(),
          maxPlayers: roomState.maxPlayers,
          isPrivate: roomState.isPrivate,
          hostId: roomState.hostId,
        );

        print('DEBUG: Updating room in Firestore');
        print('DEBUG: Database update timestamp: ${DateTime.now()}');
        await _firestore
            .collection(_roomsCollection)
            .doc(_currentRoomId!)
            .update(updatedRoomState.toJson());
        print('DEBUG: Room updated successfully');
        print('DEBUG: Database update completed timestamp: ${DateTime.now()}');
      } else {
        print('DEBUG: Room document does not exist');
      }
    } catch (e) {
      print('Error setting player ready: $e');
    }
  }

  // Get available rooms
  static Future<List<RoomState>> getAvailableRooms() async {
    try {
      final querySnapshot = await _firestore
          .collection(_roomsCollection)
          .where('status', isEqualTo: GameStatus.waiting.index)
          .where('isPrivate', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      return querySnapshot.docs
          .map((doc) => RoomState.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error getting available rooms: $e');
      return [];
    }
  }

  // Helper methods
  static Position _getStartingPosition(int playerId) {
    switch (playerId) {
      case 1:
        return GameConstants.player1Start;
      case 2:
        return GameConstants.player2Start;
      case 3:
        return GameConstants.player3Start;
      case 4:
        return GameConstants.player4Start;
      default:
        return GameConstants.player1Start;
    }
  }

  static int _getGoalRow(int playerId) {
    switch (playerId) {
      case 1:
        return GameConstants.player1Goal;
      case 2:
        return GameConstants.player2Goal;
      case 3:
        return GameConstants.player3Goal;
      case 4:
        return GameConstants.player4Goal;
      default:
        return GameConstants.player1Goal;
    }
  }

  static int _getGoalCol(int playerId) {
    switch (playerId) {
      case 1:
        return GameConstants.player1GoalCol;
      case 2:
        return GameConstants.player2GoalCol;
      case 3:
        return GameConstants.player3GoalCol;
      case 4:
        return GameConstants.player4GoalCol;
      default:
        return GameConstants.player1GoalCol;
    }
  }

  static GameState _executeMove(GameState gameState, GameMove move) {
    if (move.type == MoveType.pawnMove) {
      gameState.movePawn(move.newPosition!);
    } else if (move.type == MoveType.wallPlace) {
      gameState.addWall(move.wall!);
    }

    gameState.addMoveToHistory(move);
    gameState.checkWinCondition();

    if (gameState.status == GameStatus.playing) {
      gameState.switchTurn();
    }

    return gameState;
  }

  static void _disconnectFromCurrentRoom() {
    _currentRoomSubscription?.cancel();
    _currentGameSubscription?.cancel();
    _currentRoomId = null;
    _currentGameId = null;
    _currentPlayerId = null;
  }

  // Remove a specific room stream
  static void removeRoomStream(String roomId) {
    print('DEBUG: Removing room stream for: $roomId');
    final controller = _roomStreams.remove(roomId);
    controller?.close();
  }

  // Remove a specific game stream
  static void removeGameStream(String gameId) {
    print('DEBUG: Removing game stream for: $gameId');
    final controller = _gameStreams.remove(gameId);
    controller?.close();
  }

  // Cleanup
  static void dispose() {
    _currentRoomSubscription?.cancel();
    _currentGameSubscription?.cancel();
    _gameStreams.values.forEach((controller) => controller.close());
    _roomStreams.values.forEach((controller) => controller.close());
    _gameStreams.clear();
    _roomStreams.clear();
  }

  // Getters
  static String? get currentRoomId => _currentRoomId;
  static String? get currentGameId => _currentGameId;
  static int? get currentPlayerId => _currentPlayerId;
}
