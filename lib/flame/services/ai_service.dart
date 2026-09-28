import '../../flame/constants.dart';
import '../../flame/models/game_state.dart';
import 'ai/quoridor_engine.dart';

/// Difficulty of the computer opponent, as the player picks it.
enum AIDifficulty { easy, medium, hard }

/// The computer opponent.
///
/// This used to ask a remote language model for a "strategy" and fall back to
/// a local heuristic when that failed. The heuristic was what shipped, since
/// the remote call is unconfigured by default, and it chose moves by the
/// difference between its row and its goal row — which ignores walls, so a
/// wall across its route left it shuffling between two squares.
///
/// The opponent is now [QuoridorEngine]: a search over real shortest-path
/// distances. It is stronger, it is instant, and it costs no network call per
/// move, which matters in a game people play on mobile data.
class AIService {
  AIService._();

  static EngineStrength strengthFor(AIDifficulty difficulty) {
    switch (difficulty) {
      case AIDifficulty.easy:
        return EngineStrength.easy;
      case AIDifficulty.medium:
        return EngineStrength.medium;
      case AIDifficulty.hard:
        return EngineStrength.hard;
    }
  }

  /// Chooses a move for the player to move, or null when there is none.
  static Future<GameMove?> generateMove(
    GameState gameState,
    AIDifficulty difficulty,
  ) async {
    return QuoridorEngine.bestMove(gameState, strengthFor(difficulty));
  }
}
