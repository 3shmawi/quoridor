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

OnlineGame table({
  int moveCount = 4,
  DrawOffer? drawOffer,
  OnlineGameStatus status = OnlineGameStatus.active,
  int playerCount = 2,
  int? winner,
  OnlineOutcomeReason? reason,
}) {
  final here = DateTime.now().add(const Duration(days: 1));
  return OnlineGame(
    gameId: 'g',
    roomCode: 'ROOM11',
    status: status,
    playerCount: playerCount,
    players: {
      1: OnlinePlayer(uid: 'uid-alice', displayName: 'Alice', lastSeen: here),
      2: OnlinePlayer(uid: 'uid-bob', displayName: 'Bob', lastSeen: here),
      if (playerCount > 2)
        3: OnlinePlayer(uid: 'uid-cy', displayName: 'Cy', lastSeen: here),
    },
    currentPlayerId: 1,
    moveCount: moveCount,
    board: GameStateFactory.createNewGame(
      gameId: 'g',
      player2IsAI: false,
      playerCount: playerCount,
    ),
    drawOffer: drawOffer,
    turnLimit: TurnLimit.thirtySeconds,
    winnerPlayerId: winner,
    outcomeReason: reason,
  );
}

void main() {
  group('what is stored', () {
    test('a draw offer survives the round trip', () {
      final data = OnlineGameCodec.encodeDrawOffer(
        seat: 2,
        atMove: 7,
        timestamp: 0,
      );
      expect(
        OnlineGameCodec.decodeDrawOffer(data['drawOffer']),
        const DrawOffer(by: 2, atMove: 7),
      );
      expect(
        OnlineGameCodec.decodeDrawOffer({
          'by': 2,
          'atMove': 7,
          'declined': true,
        }),
        const DrawOffer(by: 2, atMove: 7, declined: true),
      );
      expect(OnlineGameCodec.decodeDrawOffer('nonsense'), isNull);
    });

    test('a draw is written with no winner', () {
      final data = OnlineGameCodec.encodeEnding(
        winner: null,
        reason: OnlineOutcomeReason.draw,
        timestamp: 0,
      );
      expect(data['outcome'], {'reason': 'draw'});
    });

    test('an accepted offer is not open once the game is over', () {
      expect(
        table(
          drawOffer: const DrawOffer(by: 1, atMove: 4),
          status: OnlineGameStatus.finished,
          reason: OnlineOutcomeReason.draw,
        ).openDrawOffer,
        isNull,
      );
    });

    test('an offer stands only until the next move, or a no', () {
      const offer = DrawOffer(by: 1, atMove: 4);
      expect(table(drawOffer: offer).openDrawOffer, offer);
      expect(table(drawOffer: offer, moveCount: 5).openDrawOffer, isNull);
      expect(
        table(
          drawOffer: const DrawOffer(by: 1, atMove: 4, declined: true),
        ).openDrawOffer,
        isNull,
      );
    });
  });

  group('the controller', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;
    final gameOvers = <bool?>[];
    var offered = 0;
    var declined = 0;

    setUp(() async {
      service = FakeOnlineGameService();
      controller = OnlineGameController(service: service);
      gameOvers.clear();
      offered = 0;
      declined = 0;
      controller.onGameOver = gameOvers.add;
      controller.onDrawOffered = () => offered++;
      controller.onDrawDeclined = () => declined++;
      service.sessions['g'] = OnlineSession(game: table(), localPlayerId: 1);
      expect(await controller.resumeGame('g'), isTrue);
    });

    tearDown(() => controller.dispose());

    Future<void> receive(OnlineGame game) async {
      service.push(game);
      await Future<void>.delayed(Duration.zero);
    }

    test('resigning gives the game to the other player', () async {
      expect(controller.canResign, isTrue);
      expect(await controller.resign(), isTrue);
      expect(service.endings.single, ('g', 2, OnlineOutcomeReason.resign));
    });

    test('a draw is offered at the current move, once per move', () async {
      expect(controller.canOfferDraw, isTrue);
      expect(await controller.offerDraw(), isTrue);
      expect(service.drawOffers.single, ('g', 1, 4));

      await receive(table(drawOffer: const DrawOffer(by: 1, atMove: 4)));
      expect(controller.drawOffered, isTrue);
      expect(controller.canOfferDraw, isFalse);
      expect(await controller.offerDraw(), isFalse);

      // A move later, it has lapsed and may be offered again.
      await receive(
        table(moveCount: 5, drawOffer: const DrawOffer(by: 1, atMove: 4)),
      );
      expect(controller.drawOffered, isFalse);
      expect(controller.canOfferDraw, isTrue);
    });

    test('an offer from the other player is answered here', () async {
      await receive(table(drawOffer: const DrawOffer(by: 2, atMove: 4)));
      expect(offered, 1);
      expect(controller.drawOfferToAnswer, isNotNull);
      expect(controller.canOfferDraw, isFalse);

      expect(await controller.acceptDraw(), isTrue);
      expect(service.endings.single, ('g', null, OnlineOutcomeReason.draw));
    });

    test('an offer can be turned down', () async {
      await receive(table(drawOffer: const DrawOffer(by: 2, atMove: 4)));
      expect(await controller.declineDraw(), isTrue);
      expect(service.drawsDeclined, ['g']);
    });

    test('there is nothing to answer for an offer of one\'s own', () async {
      await receive(table(drawOffer: const DrawOffer(by: 1, atMove: 4)));
      expect(controller.drawOfferToAnswer, isNull);
      expect(await controller.acceptDraw(), isFalse);
      expect(offered, 0);
    });

    test('hears when its offer is turned down', () async {
      await receive(table(drawOffer: const DrawOffer(by: 1, atMove: 4)));
      await receive(
        table(drawOffer: const DrawOffer(by: 1, atMove: 4, declined: true)),
      );
      expect(declined, 1);
    });

    test('a draw ends the game with neither side winning', () async {
      await receive(
        table(
          status: OnlineGameStatus.finished,
          reason: OnlineOutcomeReason.draw,
        ),
      );
      expect(gameOvers, [null]);
    });

    test('there is no resigning or drawing at a table of three', () async {
      controller.dispose();
      controller = OnlineGameController(service: service);
      service.sessions['g3'] = OnlineSession(
        game: table(playerCount: 3),
        localPlayerId: 1,
      );
      expect(await controller.resumeGame('g3'), isTrue);
      expect(controller.canResign, isFalse);
      expect(controller.canOfferDraw, isFalse);
    });
  });

  group('the game screen', () {
    late FakeOnlineGameService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AIService.search = AIService.searchInline;
      AudioService.instance.debugOut = _SilentAudio();
      service = FakeOnlineGameService();
      service.sessions['g'] = OnlineSession(game: table(), localPlayerId: 1);
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
            openLobby: (_, _) async {
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
      await tester.pump(const Duration(seconds: 10));
    }

    Future<void> openActions(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('gameActions')));
      await settle(tester, frames: 4);
    }

    testWidgets('resigning asks first, then gives the game away', (
      tester,
    ) async {
      await goOnline(tester);
      await openActions(tester);
      await tester.tap(find.byKey(const Key('resign')));
      await settle(tester, frames: 4);
      expect(find.text('Bob will win.'), findsOneWidget);

      await tester.tap(find.text('Keep playing'));
      await settle(tester, frames: 4);
      expect(service.endings, isEmpty);

      await openActions(tester);
      await tester.tap(find.byKey(const Key('resign')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('confirmResign')));
      await settle(tester, frames: 4);
      expect(service.endings.single, ('g', 2, OnlineOutcomeReason.resign));

      service.push(
        table(
          status: OnlineGameStatus.finished,
          winner: 2,
          reason: OnlineOutcomeReason.resign,
        ),
      );
      await settle(tester, frames: 3);
      expect(find.text('You resigned'), findsOneWidget);
      // The game is over, so the flag goes.
      expect(find.byKey(const Key('gameActions')), findsNothing);
      await finish(tester);
    });

    testWidgets('a draw can be offered from the flag', (tester) async {
      await goOnline(tester);
      await openActions(tester);
      await tester.tap(find.byKey(const Key('offerDraw')));
      await settle(tester, frames: 4);
      expect(service.drawOffers.single, ('g', 1, 4));
      expect(find.text('Draw offered to Bob'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a draw offered to this player can be accepted', (
      tester,
    ) async {
      await goOnline(tester);
      service.push(table(drawOffer: const DrawOffer(by: 2, atMove: 4)));
      await settle(tester, frames: 3);
      expect(find.text('Bob offers a draw'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);

      await tester.tap(find.byKey(const Key('acceptDraw')));
      await settle(tester, frames: 3);
      expect(service.endings.single, ('g', null, OnlineOutcomeReason.draw));

      // The finished game still carries the offer that was accepted.
      service.push(
        table(
          status: OnlineGameStatus.finished,
          reason: OnlineOutcomeReason.draw,
          drawOffer: const DrawOffer(by: 2, atMove: 4),
        ),
      );
      await settle(tester, frames: 3);
      expect(find.text("It's a draw 🤝"), findsOneWidget);
      // The offer is answered: it no longer asks, and nobody's clock runs.
      expect(find.text('Bob offers a draw'), findsNothing);
      expect(find.byKey(const Key('acceptDraw')), findsNothing);
      expect(find.text('Game over'), findsOneWidget);
      expect(find.byIcon(Icons.timer_outlined), findsNothing);
      await finish(tester);
    });

    testWidgets('a draw offered to this player can be declined', (
      tester,
    ) async {
      await goOnline(tester);
      service.push(table(drawOffer: const DrawOffer(by: 2, atMove: 4)));
      await settle(tester, frames: 3);
      await tester.tap(find.byKey(const Key('declineDraw')));
      await settle(tester, frames: 3);
      expect(service.drawsDeclined, ['g']);
      await finish(tester);
    });

    testWidgets('the other player resigning is a win, said so', (tester) async {
      await goOnline(tester);
      service.push(
        table(
          status: OnlineGameStatus.finished,
          winner: 1,
          reason: OnlineOutcomeReason.resign,
        ),
      );
      await settle(tester, frames: 3);
      expect(find.text('Bob resigned. You win!'), findsOneWidget);
      await finish(tester);
    });
  });
}
