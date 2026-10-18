import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/online/invite/invite_link.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/settings_service.dart';
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

OnlineGame table(
  String id, {
  required DateTime bobLastSeen,
  OnlineGameStatus status = OnlineGameStatus.active,
  int playerCount = 2,
  bool withBob = true,
  int? winner,
  OnlineOutcomeReason? reason,
}) => OnlineGame(
  gameId: id,
  roomCode: 'ROOM11',
  status: status,
  playerCount: playerCount,
  players: {
    1: OnlinePlayer(
      uid: 'uid-alice',
      displayName: 'Alice',
      lastSeen: DateTime.now().add(const Duration(days: 1)),
    ),
    if (withBob)
      2: OnlinePlayer(
        uid: 'uid-bob',
        displayName: 'Bob',
        lastSeen: bobLastSeen,
      ),
  },
  currentPlayerId: 1,
  moveCount: 4,
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
  winnerPlayerId: winner,
  outcomeReason: reason,
);

void main() {
  group('invite links', () {
    test('point at the site they were made on, with the code', () {
      final link = InviteLink.forCode(
        'ABC123',
        page: Uri.parse('https://3shmawi.github.io/quoridor/?x=1#/'),
      );
      expect('$link', 'https://3shmawi.github.io/quoridor/?join=ABC123');
    });

    test('from an installed app, point at the web build', () {
      expect(
        '${InviteLink.forCode('ABC123')}',
        'https://quoridor-mohager.pages.dev/?join=ABC123',
      );
    });

    test('are read back, forgiving how the code was typed', () {
      expect(
        InviteLink.codeIn(Uri.parse('https://x.dev/?join=abc123')),
        'ABC123',
      );
      expect(InviteLink.codeIn(Uri.parse('https://x.dev/?join=nope')), isNull);
      expect(InviteLink.codeIn(Uri.parse('https://x.dev/')), isNull);
    });
  });

  group('the controller', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;
    late DateTime now;

    setUp(() {
      service = FakeOnlineGameService();
      now = DateTime(2026, 1, 1, 12);
      controller = OnlineGameController(service: service, now: () => now);
    });

    tearDown(() => controller.dispose());

    Future<void> sitAt(OnlineGame game) async {
      service.sessions[game.gameId] = OnlineSession(
        game: game,
        localPlayerId: 1,
      );
      expect(await controller.resumeGame(game.gameId), isTrue);
    }

    test('nothing to claim while the other player is here', () async {
      await sitAt(table('g', bobLastSeen: now));
      expect(controller.claimWinIn, isNull);
      expect(controller.canClaimWin, isFalse);
    });

    test(
      'counts down once they go quiet, then the win can be claimed',
      () async {
        final seen = now;
        await sitAt(table('g', bobLastSeen: seen));
        now = seen.add(const Duration(seconds: 40));
        expect(
          controller.claimWinIn,
          OnlineGameController.claimAfter - const Duration(seconds: 40),
        );
        expect(await controller.claimWin(), isFalse);
        expect(service.endings, isEmpty);

        now = seen.add(OnlineGameController.claimAfter);
        expect(controller.canClaimWin, isTrue);
        expect(await controller.claimWin(), isTrue);
        expect(service.endings.single, ('g', 1, OnlineOutcomeReason.timeout));
      },
    );

    test('a refused claim says so', () async {
      await sitAt(table('g', bobLastSeen: now));
      now = now.add(const Duration(minutes: 5));
      service.endingFails = true;
      expect(await controller.claimWin(), isFalse);
      expect(controller.failure, isNotNull);
    });

    test('there is no claiming in a game of three or four', () async {
      await sitAt(table('g', bobLastSeen: now, playerCount: 3));
      now = now.add(const Duration(minutes: 5));
      expect(controller.claimWinIn, isNull);
    });

    test('leaving a two-player game under way resigns it', () async {
      await sitAt(table('g', bobLastSeen: now));
      expect(controller.leavingResigns, isTrue);
      await controller.leave(abandon: true);
      expect(service.endings.single, ('g', 2, OnlineOutcomeReason.resign));
      expect(service.abandoned, isEmpty);
    });

    test('leaving before anyone joins only abandons the game', () async {
      await sitAt(
        table(
          'g',
          bobLastSeen: now,
          withBob: false,
          status: OnlineGameStatus.waiting,
        ),
      );
      expect(controller.leavingResigns, isFalse);
      await controller.leave(abandon: true);
      expect(service.endings, isEmpty);
      expect(service.abandoned, ['g']);
    });
  });

  group('the game screen', () {
    late FakeOnlineGameService service;
    final lobbyCodes = <String?>[];
    String? copied;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AIService.search = AIService.searchInline;
      AudioService.instance.debugOut = _SilentAudio();
      service = FakeOnlineGameService();
      lobbyCodes.clear();
      copied = null;
    });

    Future<void> settle(WidgetTester tester, {int frames = 10}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(
      WidgetTester tester,
      OnlineGame game, {
      String? inviteCode,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      service.sessions[game.gameId] = OnlineSession(
        game: game,
        localPlayerId: 1,
      );
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
            inviteCode: inviteCode,
            openLobby: (_, joinCode) async {
              lobbyCodes.add(joinCode);
              final controller = OnlineGameController(service: service);
              await controller.resumeGame(game.gameId);
              return controller;
            },
          ),
        ),
      );
      await settle(tester);
      if (inviteCode == null) {
        await tester.tap(find.text('Play Online'));
        await settle(tester);
      }
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('opened from an invite, it goes straight to joining', (
      tester,
    ) async {
      await open(
        tester,
        table('g', bobLastSeen: DateTime.now()),
        inviteCode: 'ABC123',
      );
      expect(lobbyCodes, ['ABC123']);
      expect(find.text('Choose Game Mode'), findsNothing);
      expect(find.byKey(const Key('chatButton')), findsOneWidget);
      await finish(tester);
    });

    testWidgets('while waiting, Invite copies a link to the game', (
      tester,
    ) async {
      await open(
        tester,
        table(
          'g',
          bobLastSeen: DateTime.now(),
          withBob: false,
          status: OnlineGameStatus.waiting,
        ),
      );
      await tester.tap(find.byKey(const Key('invite')));
      await settle(tester, frames: 3);
      expect(copied, contains('?join=ROOM11'));
      expect(copied, contains('ROOM11'));
      expect(find.text('Invite link copied. Send it to a friend!'), findsOne);
      await finish(tester);
    });

    testWidgets('the win can be claimed from a player long gone', (
      tester,
    ) async {
      await open(
        tester,
        table(
          'g',
          bobLastSeen: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      );
      await settle(tester, frames: 12);
      await tester.tap(find.byKey(const Key('claimWin')));
      await settle(tester, frames: 3);
      expect(service.endings.single, ('g', 1, OnlineOutcomeReason.timeout));

      // The server ends the game: a win, said as such.
      service.push(
        table(
          'g',
          bobLastSeen: DateTime.now().subtract(const Duration(minutes: 2)),
          status: OnlineGameStatus.finished,
          winner: 1,
          reason: OnlineOutcomeReason.timeout,
        ),
      );
      await settle(tester, frames: 3);
      expect(find.text('Bob left the game. You win!'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('before the minute is up, the button counts down', (
      tester,
    ) async {
      await open(
        tester,
        table(
          'g',
          bobLastSeen: DateTime.now().subtract(const Duration(seconds: 40)),
        ),
      );
      await settle(tester, frames: 12);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('claimWin')),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Win in'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('leaving asks first, since it gives the game away', (
      tester,
    ) async {
      await open(tester, table('g', bobLastSeen: DateTime.now()));
      Future<void> leave() async {
        await tester.tap(find.byIcon(Icons.menu));
        await settle(tester, frames: 5);
        await tester.tap(find.text('Leave Online Game'));
        await settle(tester, frames: 5);
      }

      await leave();
      expect(find.text('Leaving now gives the win to Bob.'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await settle(tester, frames: 5);
      expect(service.endings, isEmpty);
      expect(find.byKey(const Key('chatButton')), findsOneWidget);

      await leave();
      await tester.tap(find.byKey(const Key('confirmLeave')));
      await settle(tester);
      expect(service.endings.single, ('g', 2, OnlineOutcomeReason.resign));
      expect(find.text('Choose Game Mode'), findsOneWidget);
      await finish(tester);
    });
  });
}
