import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/online/online_game_codec.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/settings_service.dart';
import 'package:quoridor/flame/services/turn_clock.dart';
import 'package:quoridor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_online_game_service.dart';

class _SilentAudio implements AudioOut {
  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) {}

  @override
  void stopAll() {}
}

const alice = OnlinePlayer(uid: 'uid-alice', displayName: 'Alice');
const bob = OnlinePlayer(uid: 'uid-bob', displayName: 'Bob');

OnlineGame game(
  String id, {
  TurnLimit turnLimit = TurnLimit.off,
  OnlineGameStatus status = OnlineGameStatus.active,
  Map<int, OnlinePlayer>? players,
}) => OnlineGame(
  gameId: id,
  roomCode: 'ROOM11',
  status: status,
  players:
      players ??
      {
        1: OnlinePlayer(
          uid: alice.uid,
          displayName: 'Alice',
          lastSeen: DateTime.now(),
        ),
        2: OnlinePlayer(
          uid: bob.uid,
          displayName: 'Bob',
          lastSeen: DateTime.now(),
        ),
      },
  currentPlayerId: 1,
  moveCount: 0,
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
  winnerPlayerId: status == OnlineGameStatus.finished ? 1 : null,
  turnLimit: turnLimit,
);

void main() {
  group('what is stored', () {
    test('the host\'s limit is written with the game and read back', () {
      final data = OnlineGameCodec.encodeNewGame(
        roomCode: 'ROOM11',
        creator: alice,
        board: GameStateFactory.createNewGame(gameId: 'g'),
        timestamp: 0,
        turnLimit: TurnLimit.thirtySeconds,
      );
      expect(data['turnSeconds'], 30);
      expect(
        OnlineGameCodec.decodeGame('g', data).turnLimit,
        TurnLimit.thirtySeconds,
      );
    });

    test('a game from before limits, or with one unknown here, has none', () {
      final data = OnlineGameCodec.encodeNewGame(
        roomCode: 'ROOM11',
        creator: alice,
        board: GameStateFactory.createNewGame(gameId: 'g'),
        timestamp: 0,
      )..remove('turnSeconds');
      expect(OnlineGameCodec.decodeGame('g', data).turnLimit, TurnLimit.off);
      data['turnSeconds'] = 45;
      expect(OnlineGameCodec.decodeGame('g', data).turnLimit, TurnLimit.off);
    });

    test('every limit is found again from its seconds', () {
      for (final limit in TurnLimit.values) {
        expect(TurnLimit.fromSeconds(limit.seconds), limit);
      }
      expect(TurnLimit.fromSeconds(null), TurnLimit.off);
    });
  });

  group('the controller', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;

    setUp(() {
      service = FakeOnlineGameService();
      controller = OnlineGameController(service: service);
    });

    tearDown(() => controller.dispose());

    test('creates the game with the limit the host picked', () async {
      service.nextCreated = OnlineSession(
        game: game(
          'g',
          status: OnlineGameStatus.waiting,
          players: const {1: alice},
          turnLimit: TurnLimit.fifteenSeconds,
        ),
        localPlayerId: 1,
      );
      expect(
        await controller.createGame(turnLimit: TurnLimit.fifteenSeconds),
        isTrue,
      );
      expect(service.createdTurnLimits.single, TurnLimit.fifteenSeconds);
      expect(controller.turnLimit, TurnLimit.fifteenSeconds);
    });

    test('a rematch keeps the table\'s limit', () async {
      service.sessions['old'] = OnlineSession(
        game: game(
          'old',
          status: OnlineGameStatus.finished,
          turnLimit: TurnLimit.sixtySeconds,
        ),
        localPlayerId: 2,
      );
      expect(await controller.resumeGame('old'), isTrue);
      service.nextCreated = OnlineSession(
        game: game(
          'new',
          status: OnlineGameStatus.waiting,
          players: const {1: bob},
          turnLimit: TurnLimit.sixtySeconds,
        ),
        localPlayerId: 1,
      );
      expect(await controller.requestRematch(), isTrue);
      expect(service.createdTurnLimits.single, TurnLimit.sixtySeconds);
    });
  });

  group('the game screen', () {
    late FakeOnlineGameService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AIService.search = AIService.searchInline;
      AudioService.instance.debugOut = _SilentAudio();
      SettingsService.instance.turnLimit.value = TurnLimit.off;
      service = FakeOnlineGameService();
      service.sessions['g'] = OnlineSession(
        game: game('g', turnLimit: TurnLimit.fifteenSeconds),
        localPlayerId: 1,
      );
    });

    Future<void> settle(WidgetTester tester, {int frames = 10}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> goOnline(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          locale: const Locale('en'),
          supportedLocales: SettingsService.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: GamePage(
            openLobby: (_) async {
              final controller = OnlineGameController(service: service);
              await controller.resumeGame('g');
              return controller;
            },
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Play Online'));
      await settle(tester);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 20));
    }

    testWidgets('everyone plays to the host\'s clock, not their own', (
      tester,
    ) async {
      await goOnline(tester);

      // This device's own setting is no limit, yet the turn is timed.
      expect(find.text('Online · 15 s a turn'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('10'), findsWidgets);
      await finish(tester);
    });

    testWidgets('the menu shows the host\'s limit and will not change it', (
      tester,
    ) async {
      await goOnline(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester, frames: 5);

      expect(find.text('Set by the host for this online game'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('60 seconds'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('60 seconds'));
      await settle(tester, frames: 3);
      expect(SettingsService.instance.turnLimit.value, TurnLimit.off);
      await finish(tester);
    });

    testWidgets('leaving goes back to this device\'s own setting', (
      tester,
    ) async {
      await goOnline(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester, frames: 5);
      await tester.tap(find.text('Leave Online Game'));
      await settle(tester);
      // Straight to the mode sheet; pick a local game.
      await tester.tap(find.text('Play vs AI'));
      await settle(tester);

      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      await finish(tester);
    });
  });
}
