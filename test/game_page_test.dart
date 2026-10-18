import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/game_service.dart';
import 'package:quoridor/flame/services/settings_service.dart';
import 'package:quoridor/flame/services/turn_clock.dart';
import 'package:quoridor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudio implements AudioOut {
  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) {}

  @override
  void stopAll() {}
}

/// The time the page's turn clock reads; [runClock] moves it on.
DateTime clockNow = DateTime(2026, 1, 1, 12);

void main() {
  setUp(() {
    clockNow = DateTime(2026, 1, 1, 12);
    SharedPreferences.setMockInitialValues({});
    AIService.search = AIService.searchInline;
    AudioService.instance.debugOut = _SilentAudio();
  });

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens the page and picks [mode] from the sheet it starts with, or
  /// leaves the sheet up when [mode] is null.
  Future<QuoridorGame> openPage(
    WidgetTester tester, {
    String? mode = 'Two Players',
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        locale: locale,
        supportedLocales: SettingsService.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: GamePage(now: () => clockNow),
      ),
    );
    await settle(tester);
    if (mode == null) return _gameOf(tester);

    // The sheet scrolls, and builds its lower cards only once scrolled to.
    await tester.scrollUntilVisible(
      find.text(mode),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await settle(tester, frames: 3);
    await tester.tap(find.text(mode));
    await settle(tester);
    return _gameOf(tester);
  }

  /// Takes the page down and lets its toasts and clock run out, so no timer
  /// outlives the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  IconButton button(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(Key(key)));

  testWidgets('the menu credits Mohager', (tester) async {
    await openPage(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, frames: 5);

    expect(find.text('@copyWrite Mohager', findRichText: true), findsOneWidget);
    expect(find.textContaining('ASHMAWY'), findsNothing);
    await finish(tester);
  });

  testWidgets('the menu links to the privacy policy', (tester) async {
    await openPage(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, frames: 5);

    expect(find.byKey(const Key('privacyPolicy')), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('undo is greyed out until there is a move to take back', (
    tester,
  ) async {
    final game = await openPage(tester);
    expect(button(tester, 'undo').onPressed, isNull);

    game.playForCurrentPlayer();
    await settle(tester, frames: 2);
    expect(button(tester, 'undo').onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('undo')));
    await settle(tester, frames: 2);
    expect(game.gameState.moveHistory, isEmpty);
    expect(button(tester, 'undo').onPressed, isNull);

    await finish(tester);
  });

  testWidgets('the move list names each move and who made it', (tester) async {
    final game = await openPage(tester);

    await tester.tap(find.byKey(const Key('moveHistory')));
    await settle(tester);
    expect(find.text('No moves yet'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    game.playForCurrentPlayer();
    await settle(tester, frames: 2);
    await tester.tap(find.byKey(const Key('moveHistory')));
    await settle(tester);

    expect(find.text('e2'), findsOneWidget);
    expect(find.text('Player 1'), findsWidgets);

    await finish(tester);
  });

  testWidgets('several computers can be chosen, and are told apart', (
    tester,
  ) async {
    await openPage(tester, mode: 'Play vs 2 or 3 AIs');
    await tester.tap(find.text('3 computer opponents'));
    await settle(tester);

    final game = _gameOf(tester);
    expect(game.gameState.playerCount, 4);
    expect(game.gameState.players.where((p) => p.isAI), hasLength(3));

    // Let the three computers reply, then read who played what.
    game.playForCurrentPlayer();
    await settle(tester, frames: 40);
    expect(game.gameState.moveHistory, hasLength(4));

    await tester.tap(find.byKey(const Key('moveHistory')));
    await settle(tester);
    for (final name in ['Player 1', 'AI 2', 'AI 3', 'AI 4']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }

    await finish(tester);
  });

  testWidgets('the winner is named in the player\'s language', (tester) async {
    final game = await openPage(
      tester,
      mode: 'ضد الكمبيوتر',
      locale: const Locale('ar'),
    );

    game.updateGameState(
      GameStateFactory.createNewGame(gameId: 'won')
        ..status = GameStatus.player2Won,
    );
    // The dialog follows the confetti.
    await settle(tester, frames: 40);

    expect(find.text('الكمبيوتر كسب!'), findsOneWidget);
    expect(find.textContaining('AI'), findsNothing);

    await finish(tester);
  });

  testWidgets('the players are shown as soon as a game is picked', (
    tester,
  ) async {
    // "Play vs AI" on a fresh launch keeps the board already loaded, so no
    // move or new game announces it; the strip under the board used to
    // stay hidden until the first move.
    await openPage(tester, mode: 'Play vs AI');
    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    await finish(tester);
  });

  /// Moves the page's clock and the test's time on together.
  Future<void> runClock(WidgetTester tester, Duration by) async {
    for (var i = 0; i < by.inMilliseconds ~/ 200; i++) {
      clockNow = clockNow.add(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Opens a two-player game on a 15-second clock and lets the first turn
  /// run out, which puts up a message.
  Future<void> runOutOfTime(WidgetTester tester) async {
    SettingsService.instance.turnLimit.value = TurnLimit.fifteenSeconds;
    addTearDown(() => SettingsService.instance.turnLimit.value = TurnLimit.off);
    await openPage(tester);
    await runClock(tester, const Duration(seconds: 16));
  }

  testWidgets('a message never moves the board', (tester) async {
    // A message used to sit in the column under the board, so the board
    // shrank and shifted while it showed, and a tap in that moment landed
    // on the wrong square.
    final board = find.byType(GameWidget<QuoridorGame>);
    SettingsService.instance.turnLimit.value = TurnLimit.fifteenSeconds;
    addTearDown(() => SettingsService.instance.turnLimit.value = TurnLimit.off);
    await openPage(tester);
    final before = tester.getRect(board);

    await runClock(tester, const Duration(seconds: 16));
    expect(find.text('Out of time — a move was played for you'), findsOne);
    expect(tester.getRect(board), before);

    await settle(tester, frames: 40);
    expect(find.text('Out of time — a move was played for you'), findsNothing);
    expect(tester.getRect(board), before);

    await finish(tester);
  });

  testWidgets('messages drop in at the top', (tester) async {
    await runOutOfTime(tester);
    final toast = tester.getRect(find.byKey(const Key('toast')));
    final board = tester.getRect(find.byType(GameWidget<QuoridorGame>));

    // Above the board, not over the players under it.
    expect(toast.top, lessThan(board.top));
    expect(toast.bottom, lessThan(board.center.dy));

    await finish(tester);
  });

  testWidgets('starting a game does not announce it', (tester) async {
    // The title already says what is being played.
    await openPage(tester);
    expect(find.byKey(const Key('toast')), findsNothing);
    await finish(tester);
  });

  testWidgets('an unfinished game can be continued after a restart', (
    tester,
  ) async {
    final saved = GameService.executeMove(
      GameStateFactory.createNewGame(gameId: 'saved', player2IsAI: false),
      const GameMove.pawnMove(Position(7, 4), 1),
    );
    SharedPreferences.setMockInitialValues({
      'savedGame.local': jsonEncode(saved.toJson()),
    });

    final game = await openPage(tester, mode: 'Continue game');

    expect(game.gameState.gameId, 'saved');
    expect(game.gameState.player1.position, const Position(7, 4));
    expect(game.gameState.currentPlayerId, 2);

    await finish(tester);
  });

  testWidgets('choosing a mode instead starts afresh', (tester) async {
    final saved = GameService.executeMove(
      GameStateFactory.createNewGame(gameId: 'saved'),
      const GameMove.pawnMove(Position(7, 4), 1),
    );
    SharedPreferences.setMockInitialValues({
      'savedGame.local': jsonEncode(saved.toJson()),
    });

    final game = await openPage(tester, mode: 'Play vs AI');

    expect(game.gameState.gameId, isNot('saved'));
    expect(game.gameState.moveHistory, isEmpty);

    await finish(tester);
  });

  testWidgets('with nothing saved there is nothing to continue', (
    tester,
  ) async {
    await openPage(tester, mode: null);
    expect(find.text('Choose Game Mode'), findsOneWidget);
    expect(find.text('Continue game', skipOffstage: false), findsNothing);
    await finish(tester);
  });

  /// Closes the mode sheet by tapping the board above it.
  Future<void> dismissSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(180, 90));
    await settle(tester, frames: 5);
  }

  testWidgets('closing the sheet leaves a way back to it', (tester) async {
    final game = await openPage(tester, mode: null);
    await dismissSheet(tester);

    expect(find.text('Choose Game Mode'), findsNothing);
    expect(find.text('Ready to play?'), findsOneWidget);
    // Nothing runs behind it: no clock, no undo, no move list.
    expect(find.byKey(const Key('undo')), findsNothing);
    expect(find.byKey(const Key('moveHistory')), findsNothing);
    expect(game.gameState.moveHistory, isEmpty);

    await tester.tap(find.byKey(const Key('startGame')));
    await settle(tester, frames: 5);
    expect(find.text('Choose Game Mode'), findsOneWidget);

    await tester.tap(find.text('Play vs AI'));
    await settle(tester);
    expect(find.text('Ready to play?'), findsNothing);
    await finish(tester);
  });

  testWidgets('closing the sheet over an unfinished game carries on with it', (
    tester,
  ) async {
    final saved = GameService.executeMove(
      GameStateFactory.createNewGame(gameId: 'saved', player2IsAI: false),
      const GameMove.pawnMove(Position(7, 4), 1),
    );
    SharedPreferences.setMockInitialValues({
      'savedGame.local': jsonEncode(saved.toJson()),
    });
    final game = await openPage(tester, mode: null);
    await dismissSheet(tester);

    expect(find.text('Ready to play?'), findsNothing);
    expect(game.gameState.gameId, 'saved');
    expect(find.byKey(const Key('undo')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('New Game in the menu opens the mode sheet, and the menu keeps '
      'only what is needed', (tester) async {
    await openPage(tester);
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, frames: 5);

    expect(find.text('Save Game'), findsNothing);
    expect(find.text('Toggle Player Mode'), findsNothing);

    await tester.tap(find.text('New Game'));
    await settle(tester, frames: 6);
    expect(find.text('Choose Game Mode'), findsOneWidget);
    expect(find.text('Play Online'), findsOneWidget);
    // A game is under way, so it can be gone back to.
    expect(find.text('Continue game'), findsNothing);
    await finish(tester);
  });

  testWidgets('the title says what is being played, and changes it', (
    tester,
  ) async {
    await openPage(tester, mode: 'Play vs AI');
    expect(find.text('vs AI · Medium'), findsOneWidget);

    await tester.tap(find.byKey(const Key('modeLabel')));
    await settle(tester, frames: 6);
    expect(find.text('Choose Game Mode'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Two Players'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Two Players'));
    await settle(tester);
    expect(find.text('2 players · this device'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the mode is named in Arabic too', (tester) async {
    await openPage(tester, mode: 'ضد الكمبيوتر', locale: const Locale('ar'));
    expect(find.textContaining('ضد الكمبيوتر ·'), findsOneWidget);
    await finish(tester);
  });
}

QuoridorGame _gameOf(WidgetTester tester) => tester
    .state<GameWidgetState<QuoridorGame>>(find.byType(GameWidget<QuoridorGame>))
    .currentGame;
