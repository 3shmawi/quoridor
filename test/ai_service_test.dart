import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/game_service.dart';

void main() {
  test(
    'the computer thinks on a background isolate and plays legally',
    () async {
      // The default search, not the inline one other tests swap in.
      expect(AIService.search, isNot(same(AIService.searchInline)));

      final state = GameStateFactory.createNewGame(gameId: 'g')
        ..currentPlayerId = 2;
      final move = await AIService.generateMove(state, AIDifficulty.easy);

      expect(move, isNotNull);
      expect(GameService.isValidMove(state, move!), isTrue);
    },
  );
}
