import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_chat.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/legal.dart';
import 'package:quoridor/flame/services/online/chat_filter.dart';
import 'package:quoridor/flame/services/online/online_game_codec.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/settings_service.dart';
import 'package:quoridor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_online_game_service.dart';

/// Report, block and the word filter: what Apple's guideline 1.2 asks of an
/// app where players type to each other.

OnlineGame liveGame(String id) => OnlineGame(
  gameId: id,
  roomCode: 'ROOM11',
  status: OnlineGameStatus.active,
  players: {
    1: OnlinePlayer(
      uid: 'uid-alice',
      displayName: 'Alice',
      lastSeen: DateTime.now(),
    ),
    2: OnlinePlayer(uid: 'uid-bob', displayName: 'Bob', lastSeen: DateTime.now()),
  },
  currentPlayerId: 1,
  moveCount: 0,
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
);

ChatMessage said(int seat, String id, String text) => ChatMessage(
  id: id,
  seat: seat,
  text: text,
  sentAt: DateTime(2026, 1, 1, 12),
);

/// Lets a stream deliver what was pushed.
Future<void> flush() => Future<void>.delayed(Duration.zero);

class _SilentAudio implements AudioOut {
  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) {}

  @override
  void stopAll() {}
}

void main() {
  group('the word filter', () {
    test('masks offensive words letter for letter, in both languages', () {
      expect(ChatFilter.clean('you shit'), 'you ****');
      expect(ChatFilter.clean('what the FUCK!'), 'what the ****!');
      expect(ChatFilter.clean('يا متناك'), 'يا *****');
      expect(ChatFilter.clean('كس امك'), '** امك');
    });

    test('sees through the usual disguises', () {
      // Stretched letters, digits for letters, words inside words.
      expect(ChatFilter.clean('fuuuuck'), '*******');
      expect(ChatFilter.clean('sh1t'), '****');
      expect(ChatFilter.clean('bullshit move'), '******** move');
      // Arabic marks, the tatweel stretch, and "and"/"the" glued on.
      expect(ChatFilter.clean('شَرْمُوطة'), '*********');
      expect(ChatFilter.clean('عـــرص'), '******');
      expect(ChatFilter.clean('والعرص'), '******');
    });

    test('leaves ordinary words alone', () {
      for (final line in [
        'Nice move!',
        'class assassin passed the Scunthorpe test',
        'مقصدش دي وربنا',
        'الكسبان أنا النهارده',
        'Good game, thanks 😂',
      ]) {
        expect(ChatFilter.clean(line), line);
      }
    });
  });

  group('the controller', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;
    late ValueNotifier<Set<String>> blocked;
    final arrivals = <ChatMessage>[];
    StreamSubscription<ChatMessage>? listening;
    var now = DateTime(2026, 1, 1, 12);

    setUp(() async {
      service = FakeOnlineGameService();
      blocked = ValueNotifier<Set<String>>({});
      now = DateTime(2026, 1, 1, 12);
      controller = OnlineGameController(
        service: service,
        now: () => now,
        blocked: blocked,
      );
      arrivals.clear();
      listening = controller.chatArrivals.listen(arrivals.add);
      service.sessions['g'] = OnlineSession(
        game: liveGame('g'),
        localPlayerId: 1,
      );
      expect(await controller.resumeGame('g'), isTrue);
      service.pushChat('g', []);
      await flush();
    });

    tearDown(() async {
      await listening?.cancel();
      controller.dispose();
    });

    test('typed words go out with offensive ones masked', () async {
      expect(await controller.sendText('  you   shit  '), isTrue);
      expect(service.chatSent.single.text, 'you ****');
    });

    test('a blocked player is gone from the chat and makes no noise', () async {
      service.pushChat('g', [said(2, 'b1', 'hi')]);
      await flush();
      expect(controller.chat.map((m) => m.id), ['b1']);

      controller.blockSeat(2);
      expect(blocked.value, {'uid-bob'});
      expect(controller.isSeatBlocked(2), isTrue);
      expect(controller.blockedSeats, [2]);
      expect(controller.chat, isEmpty);

      arrivals.clear();
      final unread = controller.unreadChat;
      service.pushChat('g', [said(2, 'b1', 'hi'), said(2, 'b2', 'still here')]);
      await flush();
      expect(arrivals, isEmpty);
      expect(controller.unreadChat, unread);

      controller.unblockSeat(2);
      expect(blocked.value, isEmpty);
      expect(controller.chat.map((m) => m.id), ['b1', 'b2']);
    });

    test('a block holds for that account in later games too', () async {
      blocked.value = {'uid-bob'};
      expect(controller.isSeatBlocked(2), isTrue);
      // Nobody can block themselves.
      controller.blockSeat(1);
      expect(blocked.value, {'uid-bob'});
      expect(controller.isSeatBlocked(1), isFalse);
    });

    test('a report names the message and its sender, once', () async {
      final message = said(2, 'b1', 'you are bad');
      service.pushChat('g', [message]);
      await flush();

      expect(controller.canReport(message), isTrue);
      expect(await controller.reportMessage(message), isTrue);
      expect(service.reported.single.gameId, 'g');
      expect(service.reported.single.message.id, 'b1');
      expect(service.reported.single.reportedUid, 'uid-bob');
      expect(controller.isReported(message), isTrue);
      expect(controller.canReport(message), isFalse);
      // Not blocked unless asked.
      expect(controller.isSeatBlocked(2), isFalse);

      expect(await controller.reportMessage(message), isTrue);
      expect(service.reported, hasLength(1));
    });

    test('reporting can block the sender in the same step', () async {
      final message = said(2, 'b1', 'you are bad');
      service.pushChat('g', [message]);
      await flush();

      expect(await controller.reportMessage(message, block: true), isTrue);
      expect(controller.isSeatBlocked(2), isTrue);
    });

    test('a report that fails is not marked, but the block still holds', () async {
      final message = said(2, 'b1', 'you are bad');
      service.pushChat('g', [message]);
      await flush();
      service.reportFails = true;

      expect(await controller.reportMessage(message, block: true), isFalse);
      expect(controller.isReported(message), isFalse);
      expect(controller.isSeatBlocked(2), isTrue);
    });

    test('a player cannot report their own message', () async {
      await controller.sendText('hello');
      final mine = controller.chat.single;
      expect(controller.canReport(mine), isFalse);
      expect(await controller.reportMessage(mine), isFalse);
      expect(service.reported, isEmpty);
    });
  });

  group('what a report stores', () {
    test('a copy of the message, matching what the Security Rules allow', () {
      final data = OnlineGameCodec.encodeReport(
        gameId: 'g',
        message: said(2, 'b1', 'you are bad'),
        reporterUid: 'uid-alice',
        reporterSeat: 1,
        reportedUid: 'uid-bob',
        reportedAt: 0,
      );
      expect(data, {
        'gameId': 'g',
        'messageId': 'b1',
        'reporterUid': 'uid-alice',
        'reporterSeat': 1,
        'reportedUid': 'uid-bob',
        'reportedSeat': 2,
        'code': 'text',
        'text': 'you are bad',
        'reportedAt': 0,
      });

      // Every field written is one the rules accept.
      final rules = File('firestore.rules').readAsStringSync();
      final allowed = RegExp(
        r"report\(\)\.keys\(\)\.hasOnly\(\[([^\]]*)\]",
      ).firstMatch(rules);
      expect(allowed, isNotNull, reason: 'the reports rule was not found');
      final names = RegExp(
        r"'(\w+)'",
      ).allMatches(allowed!.group(1)!).map((m) => m.group(1)).toSet();
      expect(names, data.keys.toSet());
    });
  });

  group('blocked players are remembered', () {
    test('across restarts', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.settings.blockedPlayers': ['uid-bob'],
      });
      final settings = SettingsService.instance;
      await settings.load();
      expect(settings.blockedPlayers.value, {'uid-bob'});

      settings.blockedPlayers.value = {'uid-bob', 'uid-carol'};
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('settings.blockedPlayers'), [
        'uid-bob',
        'uid-carol',
      ]);
      settings.blockedPlayers.value = {};
    });
  });

  group('the chat sheet', () {
    late FakeOnlineGameService service;
    late ValueNotifier<Set<String>> blocked;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AIService.search = AIService.searchInline;
      AudioService.instance.debugOut = _SilentAudio();
      service = FakeOnlineGameService();
      blocked = ValueNotifier<Set<String>>({});
      service.sessions['g'] = OnlineSession(
        game: liveGame('g'),
        localPlayerId: 1,
      );
    });

    Future<void> settle(WidgetTester tester, {int frames = 10}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Online, with Bob's [messages] already said, and the chat open.
    Future<void> openChat(
      WidgetTester tester,
      List<ChatMessage> messages,
    ) async {
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
              final controller = OnlineGameController(
                service: service,
                blocked: blocked,
              );
              await controller.resumeGame('g');
              return controller;
            },
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Play Online'));
      await settle(tester);
      service.pushChat('g', messages);
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const Key('chatButton')));
      await settle(tester, frames: 6);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('tapping a message reports it, and can block the sender', (
      tester,
    ) async {
      await openChat(tester, [said(2, 'b1', 'you are bad')]);
      expect(
        find.text('Tap a message to report it or block its sender'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('chatMessage_b1')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatReport')));
      await settle(tester, frames: 4);

      expect(find.text('Report this message?'), findsOneWidget);
      // Blocking comes ticked; leave it so.
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('chatAlsoBlock')))
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('confirmReport')));
      await settle(tester, frames: 4);

      expect(service.reported.single.message.id, 'b1');
      expect(service.reported.single.reportedUid, 'uid-bob');
      expect(blocked.value, {'uid-bob'});
      // Bob's message is gone, with a way back.
      expect(find.byKey(const Key('chatMessage_b1')), findsNothing);
      expect(find.text('You blocked Bob'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chatUnblock_2')));
      await settle(tester, frames: 4);
      expect(blocked.value, isEmpty);
      expect(find.byKey(const Key('chatMessage_b1')), findsOneWidget);
      expect(find.text('Reported'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a report can go without blocking anyone', (tester) async {
      await openChat(tester, [said(2, 'b1', 'you are bad')]);
      await tester.tap(find.byKey(const Key('chatMessage_b1')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatReport')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatAlsoBlock')));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const Key('confirmReport')));
      await settle(tester, frames: 4);

      expect(service.reported, hasLength(1));
      expect(blocked.value, isEmpty);
      expect(find.text('Reported'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a report that fails says so', (tester) async {
      service.reportFails = true;
      await openChat(tester, [said(2, 'b1', 'you are bad')]);
      await tester.tap(find.byKey(const Key('chatMessage_b1')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatReport')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatAlsoBlock')));
      await settle(tester, frames: 2);
      await tester.tap(find.byKey(const Key('confirmReport')));
      await settle(tester, frames: 4);

      expect(find.text("Couldn't send the report. Try again."), findsOneWidget);
      expect(find.text('Reported'), findsNothing);
      await finish(tester);
    });

    testWidgets('blocking from the menu needs no report', (tester) async {
      await openChat(tester, [said(2, 'b1', 'hello')]);
      await tester.tap(find.byKey(const Key('chatMessage_b1')));
      await settle(tester, frames: 4);
      await tester.tap(find.byKey(const Key('chatBlock')));
      await settle(tester, frames: 4);

      expect(blocked.value, {'uid-bob'});
      expect(service.reported, isEmpty);
      expect(find.text('You blocked Bob'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('offensive words are masked on screen, whoever sent them', (
      tester,
    ) async {
      await openChat(tester, [said(2, 'b1', 'you shit')]);
      expect(find.text('you ****'), findsWidgets);
      expect(find.text('you shit'), findsNothing);
      await finish(tester);
    });

    testWidgets('own messages offer nothing to report', (tester) async {
      await openChat(tester, [said(1, 'a1', 'hello')]);
      expect(find.byKey(const Key('chatMessage_a1')), findsNothing);
      expect(find.byKey(const Key('chatHint')), findsNothing);
      await finish(tester);
    });
  });

  group('the privacy policy', () {
    final page = File('web/privacy/index.html').readAsStringSync();

    test('is on the site the app links to', () {
      expect(
        Legal.privacyPolicy.toString(),
        'https://quoridor-mohager.pages.dev/privacy/',
      );
    });

    test('reaches the site icons from either address', () {
      // GitHub Pages serves the site under /quoridor/, Cloudflare at the root.
      expect(page, isNot(contains('href="/')));
      expect(page, isNot(contains('src="/')));
    });

    test('covers what the online game stores, in both languages', () {
      for (final words in [
        'account ID',
        'Chat messages',
        'Reports',
        'Camera',
        'deleted',
        'سياسة الخصوصية',
        'البلاغات',
        'الكاميرا',
      ]) {
        expect(page, contains(words));
      }
    });
  });
}
