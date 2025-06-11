import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../flame/constants.dart';
import '../../flame/models/game_state.dart';

class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  static const String _gamesCollection = 'games';
  static const String _usersCollection = 'users';

  // Authentication
  static Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      print('Anonymous sign in failed: $e');
      return null;
    }
  }

  static User? get currentUser => _auth.currentUser;

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  // Game operations
  static Future<String?> saveGame(GameState gameState) async {
    try {
      final docRef = await _firestore
          .collection(_gamesCollection)
          .add(gameState.toJson());

      return docRef.id;
    } catch (e) {
      print('Error saving game: $e');
      return null;
    }
  }

  static Future<bool> updateGame(GameState gameState) async {
    try {
      await _firestore
          .collection(_gamesCollection)
          .doc(gameState.gameId)
          .update(gameState.toJson());

      return true;
    } catch (e) {
      print('Error updating game: $e');
      return false;
    }
  }

  static Future<GameState?> loadGame(String gameId) async {
    try {
      final doc = await _firestore
          .collection(_gamesCollection)
          .doc(gameId)
          .get();

      if (doc.exists && doc.data() != null) {
        return GameState.fromJson(doc.data()!);
      }

      return null;
    } catch (e) {
      print('Error loading game: $e');
      return null;
    }
  }

  static Future<List<GameState>> loadRecentGames({int limit = 10}) async {
    try {
      final querySnapshot = await _firestore
          .collection(_gamesCollection)
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) => GameState.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error loading recent games: $e');
      return [];
    }
  }

  static Future<List<GameState>> loadGamesByStatus(
    GameStatus status, {
    int limit = 10,
  }) async {
    try {
      final querySnapshot = await _firestore
          .collection(_gamesCollection)
          .where('status', isEqualTo: status.index)
          .orderBy('updatedAt', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) => GameState.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('Error loading games by status: $e');
      return [];
    }
  }

  static Future<bool> deleteGame(String gameId) async {
    try {
      await _firestore.collection(_gamesCollection).doc(gameId).delete();
      return true;
    } catch (e) {
      print('Error deleting game: $e');
      return false;
    }
  }

  // Real-time game updates
  static Stream<GameState?> watchGame(String gameId) {
    return _firestore.collection(_gamesCollection).doc(gameId).snapshots().map((
      doc,
    ) {
      if (doc.exists && doc.data() != null) {
        return GameState.fromJson(doc.data()!);
      }
      return null;
    });
  }

  // User statistics
  static Future<void> updateUserStats(
    String userId, {
    int? gamesPlayed,
    int? gamesWon,
    int? totalMoves,
  }) async {
    try {
      final userRef = _firestore.collection(_usersCollection).doc(userId);

      await userRef.set({
        'gamesPlayed': FieldValue.increment(gamesPlayed ?? 0),
        'gamesWon': FieldValue.increment(gamesWon ?? 0),
        'totalMoves': FieldValue.increment(totalMoves ?? 0),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating user stats: $e');
    }
  }

  static Future<Map<String, dynamic>?> getUserStats(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();

      return doc.data();
    } catch (e) {
      print('Error getting user stats: $e');
      return null;
    }
  }

  // Batch operations for better performance
  static Future<bool> saveGameWithStats(
    GameState gameState,
    String userId,
    bool didWin,
  ) async {
    try {
      final batch = _firestore.batch();

      // Save game
      final gameRef = _firestore.collection(_gamesCollection).doc();
      final gameData = gameState.toJson();
      gameData['gameId'] = gameRef.id;
      batch.set(gameRef, gameData);

      // Update user stats
      final userRef = _firestore.collection(_usersCollection).doc(userId);
      batch.set(userRef, {
        'gamesPlayed': FieldValue.increment(1),
        'gamesWon': FieldValue.increment(didWin ? 1 : 0),
        'totalMoves': FieldValue.increment(gameState.moveHistory.length),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      return true;
    } catch (e) {
      print('Error saving game with stats: $e');
      return false;
    }
  }

  // Helper methods
  static String generateGameId() {
    return _firestore.collection(_gamesCollection).doc().id;
  }

  static Future<bool> gameExists(String gameId) async {
    try {
      final doc = await _firestore
          .collection(_gamesCollection)
          .doc(gameId)
          .get();

      return doc.exists;
    } catch (e) {
      print('Error checking if game exists: $e');
      return false;
    }
  }

  // Clean up old games (maintenance)
  static Future<void> cleanupOldGames() async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      final querySnapshot = await _firestore
          .collection(_gamesCollection)
          .where('updatedAt', isLessThan: cutoffDate.millisecondsSinceEpoch)
          .limit(100)
          .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      print('Cleaned up ${querySnapshot.docs.length} old games');
    } catch (e) {
      print('Error cleaning up old games: $e');
    }
  }
}
