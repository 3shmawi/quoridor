import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GameSessionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> createSession() async {
    try {
      // Get the current session counter
      final counterRef = _db.collection('counters').doc('session_counter');
      String sessionId = '10001'; // Default value

      await _db.runTransaction((transaction) async {
        final counterDoc = await transaction.get(counterRef);
        if (!counterDoc.exists) {
          // Initialize counter if it doesn't exist
          transaction.set(counterRef, {'count': 10000});
        } else {
          final currentCount = (counterDoc.data()?['count'] as int?) ?? 10000;
          sessionId = (currentCount + 1).toString();
          transaction.update(counterRef, {'count': currentCount + 1});
        }
      });

      // Create the game session document
      await _db.collection('game_sessions').doc(sessionId).set({
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'waiting',
        'isJoinable': true,
        'isChatEnabled': false, // Chat starts disabled
        'hostId': _auth.currentUser?.uid,
        'players': {
          'player1': {
            'id': _auth.currentUser?.uid,
            'name': _auth.currentUser?.displayName ?? 'Player 1',
            'color': 'red',
            'joined': true,
          },
          'player2': {
            'id': null,
            'name': 'Waiting for player...',
            'color': 'blue',
            'joined': false,
          },
          'player3': {
            'id': null,
            'name': 'Waiting for player...',
            'color': 'green',
            'joined': false,
          },
          'player4': {
            'id': null,
            'name': 'Waiting for player...',
            'color': 'yellow',
            'joined': false,
          },
        },
        'currentTurn': 1,
        'walls': [],
        'player1Position': {'x': 4, 'y': 8},
        'player2Position': {'x': 4, 'y': 0},
        'player3Position': {'x': 0, 'y': 4},
        'player4Position': {'x': 8, 'y': 4},
        'player1Walls': 10,
        'player2Walls': 10,
        'player3Walls': 10,
        'player4Walls': 10,
      });

      return sessionId;
    } catch (e) {
      print('Error creating session: $e');
      rethrow;
    }
  }

  Future<bool> joinSession(String sessionId, {String? playerName}) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);

      // First check if the session exists and is joinable
      final sessionDoc = await sessionRef.get();
      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Check if joining is enabled
      if (sessionData['isJoinable'] != true) {
        return false;
      }

      // Find the first available player slot
      String? availableSlot;
      for (var i = 2; i <= 4; i++) {
        final playerKey = 'player$i';
        final playerData =
            sessionData['players'][playerKey] as Map<String, dynamic>;
        if (playerData['joined'] == false) {
          availableSlot = playerKey;
          break;
        }
      }

      if (availableSlot == null) {
        return false; // No available slots
      }

      // Use provided name or default to display name or player number
      final displayName =
          playerName ??
          _auth.currentUser?.displayName ??
          'Player ${availableSlot.substring(6)}';

      // Update the session with player information
      await sessionRef.update({
        'players.$availableSlot': {
          'id': _auth.currentUser?.uid,
          'name': displayName,
          'color': sessionData['players'][availableSlot]['color'],
          'joined': true,
        },
      });

      return true;
    } catch (e) {
      print('Error joining session: $e');
      return false;
    }
  }

  Future<bool> isSessionJoinable(String sessionId) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Check if joining is enabled by host
      if (sessionData['isJoinable'] != true) {
        return false;
      }

      // Check if there are any available slots
      final players = sessionData['players'] as Map<String, dynamic>;
      for (var i = 2; i <= 4; i++) {
        final playerKey = 'player$i';
        final playerData = players[playerKey] as Map<String, dynamic>;
        if (playerData['joined'] == false) {
          return true;
        }
      }

      return false;
    } catch (e) {
      print('Error checking session joinability: $e');
      return false;
    }
  }

  // Host can disable joining
  Future<bool> setSessionJoinable(String sessionId, bool isJoinable) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);
      final sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Only host can change this setting
      if (sessionData['hostId'] != _auth.currentUser?.uid) {
        return false;
      }

      await sessionRef.update({'isJoinable': isJoinable});

      return true;
    } catch (e) {
      print('Error updating session joinable status: $e');
      return false;
    }
  }

  // Get the number of players who have joined
  Future<int> getJoinedPlayerCount(String sessionId) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return 0;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final players = sessionData['players'] as Map<String, dynamic>;

      int count = 0;
      for (var i = 1; i <= 4; i++) {
        final playerKey = 'player$i';
        final playerData = players[playerKey] as Map<String, dynamic>;
        if (playerData['joined'] == true) {
          count++;
        }
      }

      return count;
    } catch (e) {
      print('Error getting joined player count: $e');
      return 0;
    }
  }

  // Stream game state updates
  Stream<GameState?> streamGameState(String sessionId) {
    return _db.collection('game_sessions').doc(sessionId).snapshots().map((
      doc,
    ) {
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      return GameState.fromJson(data['gameState']);
    });
  }

  // Update game state
  Future<void> updateGameState(String sessionId, GameState newState) async {
    await _db.collection('game_sessions').doc(sessionId).update({
      'gameState': newState.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // End game session
  Future<void> endSession(String sessionId) async {
    await _db.collection('game_sessions').doc(sessionId).update({
      'status': 'completed',
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  // Validate session ID format
  bool isValidSessionId(String sessionId) {
    // Check if it's a 5-digit number
    if (sessionId.length != 5) return false;

    try {
      final number = int.parse(sessionId);
      return number >= 10001 && number <= 99999;
    } catch (e) {
      return false;
    }
  }

  // Update player name (can be used by host or other players)
  Future<bool> updatePlayerName(
    String sessionId,
    String playerSlot,
    String newName,
  ) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);
      final sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final players = sessionData['players'] as Map<String, dynamic>;
      final playerData = players[playerSlot] as Map<String, dynamic>;

      // Check if the user is either the host or the player whose name they're trying to change
      if (sessionData['hostId'] != _auth.currentUser?.uid &&
          playerData['id'] != _auth.currentUser?.uid) {
        return false;
      }

      // Update the player's name
      await sessionRef.update({'players.$playerSlot.name': newName});

      return true;
    } catch (e) {
      print('Error updating player name: $e');
      return false;
    }
  }

  // Get current player name
  Future<String?> getPlayerName(String sessionId, String playerSlot) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return null;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final players = sessionData['players'] as Map<String, dynamic>;
      final playerData = players[playerSlot] as Map<String, dynamic>;

      return playerData['name'] as String?;
    } catch (e) {
      print('Error getting player name: $e');
      return null;
    }
  }

  // Check if current user is host
  Future<bool> isHost(String sessionId) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      return sessionData['hostId'] == _auth.currentUser?.uid;
    } catch (e) {
      print('Error checking host status: $e');
      return false;
    }
  }

  // Get player slot for current user
  Future<String?> getCurrentPlayerSlot(String sessionId) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return null;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final players = sessionData['players'] as Map<String, dynamic>;

      for (var i = 1; i <= 4; i++) {
        final playerKey = 'player$i';
        final playerData = players[playerKey] as Map<String, dynamic>;
        if (playerData['id'] == _auth.currentUser?.uid) {
          return playerKey;
        }
      }

      return null;
    } catch (e) {
      print('Error getting current player slot: $e');
      return null;
    }
  }

  // Enable/disable chat (host only)
  Future<bool> setChatEnabled(String sessionId, bool enabled) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);
      final sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Only host can enable/disable chat
      if (sessionData['hostId'] != _auth.currentUser?.uid) {
        return false;
      }

      await sessionRef.update({'isChatEnabled': enabled});

      return true;
    } catch (e) {
      print('Error updating chat status: $e');
      return false;
    }
  }

  // Check if chat is enabled
  Future<bool> isChatEnabled(String sessionId) async {
    try {
      final sessionDoc = await _db
          .collection('game_sessions')
          .doc(sessionId)
          .get();
      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      return sessionData['isChatEnabled'] == true;
    } catch (e) {
      print('Error checking chat status: $e');
      return false;
    }
  }

  // Add chat message
  Future<bool> sendChatMessage(
    String sessionId,
    String message, {
    String? emoji,
  }) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);
      final sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Check if chat is enabled
      if (sessionData['isChatEnabled'] != true) {
        return false;
      }

      final players = sessionData['players'] as Map<String, dynamic>;

      // Find current player's slot and name
      String? playerSlot;
      String? playerName;
      for (var i = 1; i <= 4; i++) {
        final playerKey = 'player$i';
        final playerData = players[playerKey] as Map<String, dynamic>;
        if (playerData['id'] == _auth.currentUser?.uid) {
          playerSlot = playerKey;
          playerName = playerData['name'] as String?;
          break;
        }
      }

      if (playerSlot == null || playerName == null) {
        return false;
      }

      // Add message to chat collection
      await sessionRef.collection('chat').add({
        'message': message,
        'emoji': emoji,
        'playerSlot': playerSlot,
        'playerName': playerName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error sending chat message: $e');
      return false;
    }
  }

  // Stream chat messages
  Stream<List<Map<String, dynamic>>> streamChatMessages(String sessionId) {
    return _db
        .collection('game_sessions')
        .doc(sessionId)
        .collection('chat')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              ...data,
              'timestamp': (data['timestamp'] as Timestamp?)?.toDate(),
            };
          }).toList();
        });
  }

  // Restart session (host only)
  Future<bool> restartSession(String sessionId) async {
    try {
      final sessionRef = _db.collection('game_sessions').doc(sessionId);
      final sessionDoc = await sessionRef.get();

      if (!sessionDoc.exists) {
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;

      // Only host can restart
      if (sessionData['hostId'] != _auth.currentUser?.uid) {
        return false;
      }

      // Reset game state
      await sessionRef.update({
        'status': 'waiting',
        'isJoinable': true,
        'currentTurn': 1,
        'walls': [],
        'player1Position': {'x': 4, 'y': 8},
        'player2Position': {'x': 4, 'y': 0},
        'player3Position': {'x': 0, 'y': 4},
        'player4Position': {'x': 8, 'y': 4},
        'player1Walls': 10,
        'player2Walls': 10,
        'player3Walls': 10,
        'player4Walls': 10,
      });

      return true;
    } catch (e) {
      print('Error restarting session: $e');
      return false;
    }
  }
}
