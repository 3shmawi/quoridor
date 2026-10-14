import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/settings_service.dart';

/// Records what would have been played.
class FakeAudioOut implements AudioOut {
  final played = <Sfx>[];

  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) => played.add(sfx);

  @override
  void stopAll() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioOut audio;

  setUp(() {
    // A real isolate never finishes on the fake clock these tests run on.
    AIService.search = AIService.searchInline;
    audio = FakeAudioOut();
    AudioService.instance.debugOut = audio;
    AudioService.instance.enabled.value = true;
  });

  /// Player 1 against the computer, player 1 to move.
  GameState againstAI() => GameStateFactory.createNewGame(gameId: 'g');

  /// A two-player game that [seat] has just won.
  GameState wonBy(int seat) =>
      GameStateFactory.createNewGame(gameId: 'g', player2IsAI: false)
        ..status = GameStatus.wonBy(seat);

  Future<QuoridorGame> loaded({AIDifficulty? difficulty}) async {
    final game = QuoridorGame(difficulty: difficulty);
    await game.onLoad();
    return game;
  }

  void goOnline(QuoridorGame game, {int seat = 1}) {
    game.localPlayerId = seat;
    game.turnGate = () => true;
    game.onSubmitMove = (_) async => true;
  }

  group('difficulty', () {
    final saved = SettingsService.instance.difficulty;
    late AIDifficulty before;

    setUp(() => before = saved.value);
    tearDown(() => saved.value = before);

    test('a new game plays at the difficulty saved in settings', () {
      saved.value = AIDifficulty.hard;
      expect(QuoridorGame().difficulty, AIDifficulty.hard);

      saved.value = AIDifficulty.easy;
      expect(QuoridorGame().difficulty, AIDifficulty.easy);
    });
  });

  group('the computer reply', () {
    testWidgets('the player sees their own move before the reply', (
      tester,
    ) async {
      final game = await loaded(difficulty: AIDifficulty.easy);
      game.updateGameState(againstAI());

      game.playForCurrentPlayer();

      // The player's move is on the board straight away, on its own.
      expect(game.gameState.moveHistory, hasLength(1));
      expect(game.gameState.moveHistory.single.playerId, 1);
      expect(game.gameState.currentPlayer.isAI, isTrue);

      await tester.pump(QuoridorGame.aiThinkingDelay);
      await tester.pump();

      expect(game.gameState.moveHistory, hasLength(2));
      expect(game.gameState.moveHistory.last.playerId, 2);
      expect(game.gameState.currentPlayerId, 1);
    });

    testWidgets('a reply for a board that was replaced is dropped', (
      tester,
    ) async {
      final game = await loaded(difficulty: AIDifficulty.easy);
      final aiToMove = againstAI()..currentPlayerId = 2;
      game.updateGameState(aiToMove);

      // A new game arrives while the computer is still "thinking".
      game.startGame(playerCount: 2, againstAI: true);
      await tester.pump(QuoridorGame.aiThinkingDelay);
      await tester.pump();

      expect(game.gameState.moveHistory, isEmpty);
      expect(game.gameState.currentPlayerId, 1);
    });

    testWidgets('an online board never plays a computer move of its own', (
      tester,
    ) async {
      final game = await loaded(difficulty: AIDifficulty.easy);
      goOnline(game);
      game.updateGameState(againstAI()..currentPlayerId = 2);

      await tester.pump(QuoridorGame.aiThinkingDelay);
      await tester.pump();

      expect(game.gameState.moveHistory, isEmpty);
    });
  });

  group('switching seat 2 between computer and person', () {
    test('is offered in a local two-player game', () async {
      final game = await loaded();
      game.updateGameState(againstAI());
      expect(game.canTogglePlayerMode, isTrue);

      game.togglePlayerMode();
      expect(game.gameState.player2.isAI, isFalse);
    });

    test('is not offered online, and does nothing there', () async {
      final game = await loaded();
      goOnline(game);
      game.updateGameState(wonBy(1)..status = GameStatus.playing);

      expect(game.canTogglePlayerMode, isFalse);
      game.togglePlayerMode();
      expect(game.gameState.player2.isAI, isFalse);
    });

    test('is not offered with three or four at the table', () async {
      final game = await loaded();
      game.startGame(playerCount: 4, againstAI: false);

      expect(game.canTogglePlayerMode, isFalse);
      game.togglePlayerMode();
      expect(game.gameState.players.any((p) => p.isAI), isFalse);
    });
  });

  group('the end of the game', () {
    test('a local win is celebrated once', () async {
      final game = await loaded();
      var celebrations = 0;
      game.onGameWon = () => celebrations++;

      game.updateGameState(wonBy(2));
      game.updateGameState(wonBy(2));

      expect(celebrations, 1);
      expect(audio.played, [Sfx.win]);
    });

    test(
      'online, the board leaves the celebration to the controller',
      () async {
        final game = await loaded();
        var celebrations = 0;
        game.onGameWon = () => celebrations++;
        goOnline(game, seat: 1);

        game.updateGameState(wonBy(1));

        // The controller knows who this device is and celebrates a win itself;
        // the board celebrating as well showed the winner two dialogs.
        expect(celebrations, 0);
        expect(audio.played, [Sfx.win]);
      },
    );

    test('online, the losing device gets no fanfare', () async {
      final game = await loaded();
      var celebrations = 0;
      game.onGameWon = () => celebrations++;
      goOnline(game, seat: 1);

      game.updateGameState(wonBy(2));

      expect(celebrations, 0);
      expect(audio.played, isEmpty);
    });
  });

  test('the board sends the page no text of its own', () {
    // Its messages were hard-coded English -- "AI played their move" after
    // every reply -- and showed as they were in the Arabic game. The page
    // says everything now, in the player's language.
    final source = File('lib/flame/game/quoridor_game.dart').readAsStringSync();
    expect(source, isNot(contains('onGameMessage')));
  });
}
