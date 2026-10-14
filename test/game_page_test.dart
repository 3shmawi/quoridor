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

void main() {
  setUp(() {
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
        home: const GamePage(),
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

  testWidgets('switching seat 2 is only in the menu for two players', (
    tester,
  ) async {
    await openPage(tester, mode: 'Four Players');
    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester);
    expect(find.text('Toggle Player Mode'), findsNothing);

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
}

QuoridorGame _gameOf(WidgetTester tester) => tester
    .state<GameWidgetState<QuoridorGame>>(find.byType(GameWidget<QuoridorGame>))
    .currentGame;
