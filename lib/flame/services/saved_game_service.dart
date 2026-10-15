import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_state.dart';

/// Keeps the local game in progress, so closing the app does not lose it.
///
/// Phones close apps behind the player's back all the time -- a call, low
/// memory, a swipe -- and a game of Quoridor runs long enough for that to
/// happen mid-game. Only local games are kept: an online game already lives
/// on the server and is resumed from the lobby.
class SavedGameService {
  SavedGameService._();

  static final SavedGameService instance = SavedGameService._();

  static const String _key = 'savedGame.local';

  /// The game left unfinished last time, or null if there is none.
  ///
  /// A save that cannot be read -- from a build with a different format, or
  /// cut short -- is dropped rather than allowed to stop the app starting.
  Future<GameState?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;

      final state = GameState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (state.isGameOver || state.moveHistory.isEmpty) return null;
      return state;
    } catch (error) {
      debugPrint('SavedGameService: dropping unreadable save: $error');
      await clear();
      return null;
    }
  }

  /// Keeps [state] as the game to come back to, or forgets the saved game
  /// once [state] is over or has not started.
  Future<void> save(GameState state) async {
    if (state.isGameOver || state.moveHistory.isEmpty) return clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (error) {
      debugPrint('SavedGameService: save failed: $error');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      debugPrint('SavedGameService: clear failed: $error');
    }
  }
}
