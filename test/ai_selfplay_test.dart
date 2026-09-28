import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai/quoridor_engine.dart';
import 'package:quoridor/flame/services/game_service.dart';

/// Plays one full game between two strengths and reports who won.
///
/// This is the only check that the engine actually *plays*: the unit tests
/// pin individual decisions, but a strength that searched badly could still
/// satisfy all of them while losing every game.
({int? winner, int plies}) playGame({
  required EngineStrength strengthForSeat1,
  required EngineStrength strengthForSeat2,
  required int seed,
  int maxPlies = 200,
}) {
  var state = GameStateFactory.createNewGame(player2IsAI: true);
  final random = Random(seed);
  var plies = 0;

  while (!state.isGameOver && plies < maxPlies) {
    final strength = state.currentPlayerId == 1
        ? strengthForSeat1
        : strengthForSeat2;

    final move = QuoridorEngine.bestMove(state, strength, random: random);
    if (move == null) break;

    state = GameService.executeMove(state, move);
    plies++;
  }

  if (!state.isGameOver) return (winner: null, plies: plies);
  return (winner: state.status == GameStatus.player1Won ? 1 : 2, plies: plies);
}

void main() {
  group('self play', () {
    test('hard beats easy from either seat', () {
      var hardWins = 0;
      var finished = 0;

      for (var seed = 0; seed < 4; seed++) {
        // Alternate seats so the first-move advantage cancels out.
        final hardSeat = seed.isEven ? 1 : 2;
        final result = playGame(
          strengthForSeat1: hardSeat == 1
              ? EngineStrength.hard
              : EngineStrength.easy,
          strengthForSeat2: hardSeat == 2
              ? EngineStrength.hard
              : EngineStrength.easy,
          seed: seed,
        );

        if (result.winner != null) finished++;
        if (result.winner == hardSeat) hardWins++;
      }

      expect(finished, 4, reason: 'a game failed to finish');
      expect(
        hardWins,
        greaterThanOrEqualTo(3),
        reason: 'hard won only $hardWins of 4 against easy',
      );
    });

    test('games end rather than shuffling until the ply cap', () {
      final result = playGame(
        strengthForSeat1: EngineStrength.medium,
        strengthForSeat2: EngineStrength.medium,
        seed: 7,
      );

      expect(result.winner, isNotNull, reason: 'medium vs medium never ended');
      // Two pawns eight steps apart cannot finish instantly, and a game that
      // drags near the cap means someone is going in circles.
      expect(result.plies, lessThan(120));
    });
  });
}
