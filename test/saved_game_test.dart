import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/game_service.dart';
import 'package:quoridor/flame/services/saved_game_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saves = SavedGameService.instance;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  GameState oneMoveIn() => GameService.executeMove(
    GameStateFactory.createNewGame(gameId: 'g'),
    const GameMove.pawnMove(Position(7, 4), 1),
  );

  test('a game under way comes back as it was', () async {
    await saves.save(oneMoveIn());

    final loaded = await saves.load();
    expect(loaded, isNotNull);
    expect(loaded!.gameId, 'g');
    expect(loaded.player1.position, const Position(7, 4));
    expect(loaded.currentPlayerId, 2);
    expect(loaded.player2.isAI, isTrue);
    expect(loaded.moveHistory, hasLength(1));
  });

  test('a finished game is not offered again', () async {
    await saves.save(oneMoveIn());
    await saves.save(oneMoveIn()..status = GameStatus.player1Won);
    expect(await saves.load(), isNull);
  });

  test('starting a new game forgets the old one', () async {
    await saves.save(oneMoveIn());
    await saves.save(GameStateFactory.createNewGame(gameId: 'fresh'));
    expect(await saves.load(), isNull);
  });

  test('an unreadable save is dropped, not fatal', () async {
    SharedPreferences.setMockInitialValues({
      'savedGame.local': jsonEncode({'not': 'a game'}),
    });
    expect(await saves.load(), isNull);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('savedGame.local'), isNull);
  });
}
