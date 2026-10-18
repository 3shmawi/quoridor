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
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/settings_service.dart';
import 'package:quoridor/flame/widgets/online_chat.dart';
import 'package:quoridor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_online_game_service.dart';

class _RecordingAudio implements AudioOut {
  final played = <Sfx>[];

  @override
  Future<void> preload() async {}

  @override
  void play(Sfx sfx, {double volume = 1}) => played.add(sfx);

  @override
  void stopAll() {}
}

void main() {
  late _RecordingAudio audio;
  late FakeOnlineGameService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AIService.search = AIService.searchInline;
    audio = _RecordingAudio();
    AudioService.instance.debugOut = audio;
    service = FakeOnlineGameService();
    service.sessions['g'] = OnlineSession(
      game: OnlineGame(
        gameId: 'g',
        roomCode: 'ROOM11',
        status: OnlineGameStatus.active,
        players: {
          1: OnlinePlayer(
            uid: 'uid-alice',
            displayName: 'Alice',
            lastSeen: DateTime.now(),
          ),
          2: OnlinePlayer(
            uid: 'uid-bob',
            displayName: 'Bob',
            lastSeen: DateTime.now(),
          ),
        },
        currentPlayerId: 1,
        moveCount: 0,
        board: GameStateFactory.createNewGame(gameId: 'g', player2IsAI: false),
      ),
      localPlayerId: 1,
    );
  });

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openPage(WidgetTester tester) async {
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
  }

  Future<void> goOnline(WidgetTester tester) async {
    await openPage(tester);
    await tester.tap(find.text('Play Online'));
    await settle(tester);
    // The chat's first list: nothing said yet.
    service.pushChat('g', []);
    await settle(tester, frames: 2);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('online play is the first choice, and stands out', (
    tester,
  ) async {
    await openPage(tester);

    final online = tester.getTopLeft(find.text('Play Online')).dy;
    for (final other in ['Play vs AI']) {
      expect(online, lessThan(tester.getTopLeft(find.text(other)).dy));
    }
    final card = tester.widget<Card>(find.byKey(const Key('mode_online')));
    expect(card.elevation, greaterThan(0));
    await finish(tester);
  });

  testWidgets('a face picked in the chat goes out and pops up on the board', (
    tester,
  ) async {
    await goOnline(tester);

    expect(find.byKey(const Key('chatButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chatButton')));
    await settle(tester, frames: 6);

    expect(find.text('Nothing yet. Send a face to break the ice!'), findsOne);
    await tester.tap(find.byKey(const Key('chat_scared')));
    await settle(tester, frames: 6);

    expect(service.chatSent.single.item, QuickChat.scared);
    expect(service.chatSent.single.seat, 1);
    // The sheet closes, so the bubble is seen.
    expect(find.byType(ChatSheet), findsNothing);
    expect(find.byType(ChatBubble), findsOneWidget);
    // This device's own message makes no sound.
    expect(audio.played, isNot(contains(Sfx.chat)));

    await finish(tester);
  });

  testWidgets('a message from the other player pops up, sounds and waits '
      'unread until the chat is opened', (tester) async {
    await goOnline(tester);

    service.pushChat('g', [
      ChatMessage(
        id: 'b1',
        seat: 2,
        item: QuickChat.niceMove,
        sentAt: DateTime.now(),
      ),
    ]);
    await settle(tester, frames: 7);

    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text('Nice move!'), findsOneWidget);
    expect(find.text('Bob'), findsWidgets);
    expect(audio.played, contains(Sfx.chat));
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('chatUnread')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '1',
    );

    await tester.tap(find.byKey(const Key('chatButton')));
    await settle(tester, frames: 6);
    expect(find.byKey(const Key('chatHistory')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chatHistory')),
        matching: find.text('Nice move!'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<ChatButton>(find.byType(ChatButton)).unread, 0);

    await finish(tester);
  });

  testWidgets('leaving the online game takes the chat away', (tester) async {
    await goOnline(tester);
    expect(find.byKey(const Key('chatButton')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await settle(tester, frames: 5);
    await tester.tap(find.text('Leave Online Game'));
    await settle(tester, frames: 5);
    // Leaving a two-player game under way asks first.
    await tester.tap(find.byKey(const Key('confirmLeave')));
    await settle(tester);

    expect(find.byKey(const Key('chatButton')), findsNothing);
    expect(find.byType(ChatBubbleLayer), findsNothing);
    // Straight on to picking the next game.
    expect(find.text('Choose Game Mode'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('typed words are sent from the chat, which stays open', (
    tester,
  ) async {
    await goOnline(tester);
    await tester.tap(find.byKey(const Key('chatButton')));
    await settle(tester, frames: 6);

    // Nothing to send yet.
    expect(
      tester.widget<IconButton>(find.byKey(const Key('chatSend'))).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('chatText')), 'مقصدش دي وربنا');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatSend')));
    await settle(tester, frames: 6);

    expect(service.chatSent.single.text, 'مقصدش دي وربنا');
    expect(find.byType(ChatSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('chatHistory')),
        matching: find.text('مقصدش دي وربنا'),
      ),
      findsOneWidget,
    );
    // The box is empty again, ready for the next one.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('chatText')))
          .controller!
          .text,
      isEmpty,
    );
    await finish(tester);
  });

  testWidgets('a muted chat stays quiet', (tester) async {
    await goOnline(tester);
    await tester.tap(find.byKey(const Key('chatButton')));
    await settle(tester, frames: 6);
    await tester.tap(find.byKey(const Key('chatMute')));
    await settle(tester, frames: 2);
    // Close the sheet.
    await tester.tapAt(const Offset(200, 40));
    await settle(tester, frames: 6);

    service.pushChat('g', [
      ChatMessage(id: 'b1', seat: 2, text: 'hello?', sentAt: DateTime.now()),
    ]);
    await settle(tester, frames: 7);

    expect(find.byType(ChatBubble), findsNothing);
    expect(audio.played, isNot(contains(Sfx.chat)));
    expect(tester.widget<ChatButton>(find.byType(ChatButton)).unread, 0);
    await finish(tester);
  });
}
