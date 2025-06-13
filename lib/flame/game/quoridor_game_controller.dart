// import 'package:audioplayers/audioplayers.dart';
// import 'package:flutter/material.dart';
//
// import '../constants.dart';
// import '../models/game_state.dart';
// import '../services/ai_service.dart';
// import 'quoridor_game.dart';
//
// /// Controller for managing the Quoridor game state and logic.
// ///
// /// This class wraps a [QuoridorGame] instance and exposes methods
// /// for interacting with the game. It notifies listeners when the
// /// game state changes, so the UI can rebuild accordingly.
// class QuoridorGameController extends ChangeNotifier {
//   late QuoridorGame _game;
//
//   /// The current message to display in the UI.
//   String? _currentMessage;
//
//   String? get currentMessage => _currentMessage;
//
//   /// Whether the game is currently showing a message.
//   bool _showMessage = false;
//
//   bool get isShowingMessage => _showMessage;
//
//   /// Whether the game is over.
//   bool get isGameOver => _game.isGameOver;
//
//   /// The current game state.
//   GameState get gameState => _game.gameState;
//
//   /// The current player ID.
//   int get currentPlayerId => _game.currentPlayerId;
//
//   /// The winner, if any.
//   String? get winner => _game.winner;
//
//   /// Whether the game is initialized.
//   bool get isInitialized => _game.isInitialized;
//
//   final messageController = TextEditingController();
//
//   QuoridorGameController({GameState? initialGameState}) {
//     _game = QuoridorGame();
//     if (initialGameState != null) {
//       _game.updateGameState(initialGameState);
//     }
//     _game.onGameStateChanged = _onGameStateChanged;
//     _game.onGameMessage = _onGameMessage;
//     _game.onGameWon = _onGameWon;
//   }
//
//   final _audioPlayer = AudioPlayer();
//
//   void _onGameStateChanged(GameState state) {
//     notifyListeners();
//   }
//
//   void _onGameMessage(String message) {
//     _currentMessage = message;
//     _showMessage = true;
//     notifyListeners();
//     Future.delayed(const Duration(seconds: 2), () {
//       _showMessage = false;
//       notifyListeners();
//     });
//   }
//
//   void _onGameWon() async {
//     _onGameMessage("Game Over! ${_game.winner} wins!");
//     await _audioPlayer.play(AssetSource("sounds/win.wav"));
//   }
//
//   /// Starts a new game.
//   void newGame() {
//     _game.newGame();
//     notifyListeners();
//   }
//
//   /// Toggles the player mode (AI vs Human).
//   void togglePlayerMode() {
//     _game.togglePlayerMode();
//     notifyListeners();
//   }
//
//   /// Sets the wall orientation.
//   void setWallOrientation(WallOrientation orientation) {
//     _game.setWallOrientation(orientation);
//     notifyListeners();
//   }
//
//   /// Shows or hides valid moves.
//   void showValidMoves(bool show) {
//     _game.showValidMoves(show);
//     notifyListeners();
//   }
//
//   /// Sets the AI difficulty.
//   void setDifficulty(AIDifficulty difficulty) {
//     _game.setDifficulty(difficulty);
//     notifyListeners();
//   }
//
//   /// Updates the game state.
//   void updateGameState(GameState state) {
//     _game.updateGameState(state);
//     notifyListeners();
//   }
//
//   /// Shows a message in the UI and notifies listeners.
//   void showMessage({
//     required AnimationController messageController,
//     required String message,
//     required bool mounted,
//   }) {
//     _onGameMessage(message);
//     // Start the fade-in animation
//     messageController.forward(from: 0);
//
//     // After 2 seconds, fade out
//     Future.delayed(const Duration(seconds: 2), () {
//       if (mounted) {
//         messageController.reverse();
//       }
//     });
//   }
//
//   /// Exposes the underlying QuoridorGame instance for advanced use.
//   QuoridorGame get game => _game;
// }
