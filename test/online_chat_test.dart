import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_chat.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/services/app_strings.dart';
import 'package:quoridor/flame/services/online/online_game_codec.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/widgets/online_chat.dart';

import 'fakes/fake_online_game_service.dart';

OnlineGame liveGame(String id, {OnlineGameStatus? status}) => OnlineGame(
  gameId: id,
  roomCode: 'ROOM11',
  status: status ?? OnlineGameStatus.active,
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
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
);

ChatMessage from(int seat, String id, QuickChat item, {DateTime? at}) =>
    ChatMessage(
      id: id,
      seat: seat,
      item: item,
      sentAt: at ?? DateTime(2026, 1, 1, 12),
    );

void main() {
  group('what is stored', () {
    test('a message survives the round trip', () {
      final message = from(2, 'm1', QuickChat.scared);
      final data = OnlineGameCodec.encodeChat(
        message: message,
        uid: 'uid-bob',
        sentAt: message.sentAt!.millisecondsSinceEpoch,
      );
      expect(data, {
        'seat': 2,
        'uid': 'uid-bob',
        'code': 'scared',
        'sentAt': message.sentAt!.millisecondsSinceEpoch,
      });
      expect(OnlineGameCodec.decodeChat('m1', data), message);
    });

    test('a reaction this build does not know is skipped, not shown', () {
      expect(
        OnlineGameCodec.decodeChat('m1', {'seat': 1, 'code': 'newFace'}),
        isNull,
      );
      expect(OnlineGameCodec.decodeChat('m1', {'code': 'laugh'}), isNull);
    });

    test('the Security Rules accept exactly the reactions the app offers', () {
      // A reaction missing from the rules would be refused on send; one
      // missing from the app would be sendable by a modified client only.
      final rules = File('firestore.rules').readAsStringSync();
      final list = RegExp(
        r'function isQuickChat\(code\) \{\s*return code in \[([^\]]*)\]',
      ).firstMatch(rules);
      expect(list, isNotNull, reason: 'isQuickChat not found in the rules');
      final names = RegExp(
        r"'(\w+)'",
      ).allMatches(list!.group(1)!).map((m) => m.group(1)).toList();
      expect(names, QuickChat.values.map((item) => item.name).toList());
    });

    test('every reaction says something in both languages', () {
      for (final item in QuickChat.values) {
        expect(AppStrings.debugEnglishKeys, contains('chat_${item.name}'));
        expect(AppStrings.debugArabicKeys, contains('chat_${item.name}'));
      }
    });

    test('there are faces and lines to pick from', () {
      expect(
        QuickChat.faces,
        containsAll([
          QuickChat.laugh,
          QuickChat.thinking,
          QuickChat.angry,
          QuickChat.scared,
        ]),
      );
      expect(QuickChat.lines, isNotEmpty);
      expect(
        QuickChat.faces.toSet().intersection(QuickChat.lines.toSet()),
        isEmpty,
      );
    });
  });

  group('the controller', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;
    late DateTime now;
    final arrivals = <ChatMessage>[];
    StreamSubscription<ChatMessage>? listening;

    setUp(() async {
      service = FakeOnlineGameService();
      now = DateTime(2026, 1, 1, 12);
      controller = OnlineGameController(service: service, now: () => now);
      arrivals.clear();
      listening = controller.chatArrivals.listen(arrivals.add);
      service.sessions['g'] = OnlineSession(
        game: liveGame('g'),
        localPlayerId: 1,
      );
      expect(await controller.resumeGame('g'), isTrue);
    });

    tearDown(() async {
      await listening?.cancel();
      controller.dispose();
    });

    /// Lets the stream deliver what was pushed.
    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('a message sent shows at once, as this seat, and goes out', () async {
      final sent = controller.sendChat(QuickChat.laugh);
      await flush();

      expect(controller.chat.single.item, QuickChat.laugh);
      expect(controller.chat.single.seat, 1);
      // It pops up on this device's own board straight away.
      expect(arrivals.single.item, QuickChat.laugh);
      expect(await sent, isTrue);
      expect(service.chatSent.single.id, controller.chat.single.id);
      expect(controller.unreadChat, 0);
    });

    test('a second message has to wait for the cooldown', () async {
      expect(await controller.sendChat(QuickChat.laugh), isTrue);
      expect(controller.canChat, isFalse);
      expect(await controller.sendChat(QuickChat.angry), isFalse);

      now = now.add(OnlineGameController.chatCooldown);
      expect(controller.canChat, isTrue);
      expect(await controller.sendChat(QuickChat.angry), isTrue);
      expect(service.chatSent.map((m) => m.item), [
        QuickChat.laugh,
        QuickChat.angry,
      ]);
    });

    test('the conversation so far neither pops up nor counts as new', () async {
      service.pushChat('g', [
        from(2, 'old1', QuickChat.hello),
        from(1, 'old2', QuickChat.goodLuck),
      ]);
      await flush();

      expect(controller.chat.map((m) => m.id), ['old1', 'old2']);
      expect(arrivals, isEmpty);
      expect(controller.unreadChat, 0);
    });

    test('a message from the other player pops up and counts as new', () async {
      service.pushChat('g', []);
      await flush();
      service.pushChat('g', [from(2, 'b1', QuickChat.angry)]);
      await flush();

      expect(arrivals.single.id, 'b1');
      expect(controller.unreadChat, 1);

      service.pushChat('g', [
        from(2, 'b1', QuickChat.angry),
        from(2, 'b2', QuickChat.scared),
      ]);
      await flush();
      expect(arrivals.map((m) => m.id), ['b1', 'b2']);
      expect(controller.unreadChat, 2);

      controller.markChatRead();
      expect(controller.unreadChat, 0);
    });

    test('the server echoing this device\'s message adds nothing', () async {
      service.pushChat('g', []);
      await flush();
      await controller.sendChat(QuickChat.cool);
      final mine = controller.chat.single;
      arrivals.clear();

      // Still undated by the server, then dated.
      service.pushChat('g', [
        ChatMessage(id: mine.id, seat: 1, item: QuickChat.cool),
      ]);
      await flush();
      expect(controller.chat.single.sentAt, mine.sentAt);

      service.pushChat('g', [from(1, mine.id, QuickChat.cool)]);
      await flush();
      expect(controller.chat, hasLength(1));
      expect(arrivals, isEmpty);
      expect(controller.unreadChat, 0);
    });

    test('messages are kept in the order they were sent', () async {
      service.pushChat('g', [
        from(2, 'late', QuickChat.oops, at: DateTime(2026, 1, 1, 12, 5)),
        from(2, 'early', QuickChat.hello, at: DateTime(2026, 1, 1, 12, 1)),
      ]);
      await flush();
      expect(controller.chat.map((m) => m.id), ['early', 'late']);
    });

    test('a message that could not be sent is taken back off', () async {
      service.chatFails = true;
      expect(await controller.sendChat(QuickChat.love), isFalse);
      expect(controller.chat, isEmpty);
    });

    test('nobody outside the game can chat', () async {
      service.sessions['watch'] = OnlineSession(
        game: liveGame('watch'),
        localPlayerId: null,
      );
      expect(await controller.resumeGame('watch'), isTrue);
      expect(controller.canChat, isFalse);
      expect(await controller.sendChat(QuickChat.laugh), isFalse);
    });
  });

  group('bubbles', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 400, child: child)),
    );

    testWidgets('a message pops up in its corner, then floats away', (
      tester,
    ) async {
      final arrivals = StreamController<ChatMessage>.broadcast();
      addTearDown(arrivals.close);
      await tester.pumpWidget(
        host(
          ChatBubbleLayer(
            arrivals: arrivals.stream,
            localSeat: 1,
            nameOf: (seat) => seat == 1 ? 'You' : 'Bob',
            colorOf: (_) => Colors.blue,
          ),
        ),
      );

      arrivals.add(from(2, 'theirs', QuickChat.angry));
      arrivals.add(from(1, 'mine', QuickChat.niceMove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      final theirs = find.byKey(const ValueKey('theirs'));
      final mine = find.byKey(const ValueKey('mine'));
      expect(theirs, findsOneWidget);
      expect(mine, findsOneWidget);
      // The other player's comes in from the top, by their side of the
      // board; this device's own from the bottom.
      expect(tester.getCenter(theirs).dy, lessThan(tester.getCenter(mine).dy));
      expect(find.text('Bob'), findsOneWidget);
      // A line shows its words; a face only its emoji.
      expect(find.text('Nice move!'), findsOneWidget);
      expect(find.text('Grr!'), findsNothing);

      await tester.pump(ChatBubbleLayer.lineLife);
      await tester.pump(const Duration(seconds: 1));
      expect(theirs, findsNothing);
      expect(mine, findsNothing);
    });

    testWidgets('a corner holds only the latest few', (tester) async {
      final arrivals = StreamController<ChatMessage>.broadcast();
      addTearDown(arrivals.close);
      await tester.pumpWidget(
        host(
          ChatBubbleLayer(
            arrivals: arrivals.stream,
            localSeat: 1,
            nameOf: (_) => 'Bob',
            colorOf: (_) => Colors.red,
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        arrivals.add(from(2, 'm$i', QuickChat.laugh));
      }
      await tester.pump();
      expect(find.byType(ChatBubble), findsNWidgets(ChatBubbleLayer.perCorner));
      expect(find.byKey(const ValueKey('m0')), findsNothing);
      expect(find.byKey(const ValueKey('m4')), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('faces stay still when the platform asks for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ChatGlyph(QuickChat.angry),
          ),
        ),
      );
      // No frame is scheduled by a still face.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('typed messages', () {
    test('are tidied to one short line', () {
      expect(ChatMessage.tidy('  hi \n\n  there  '), 'hi there');
      expect(ChatMessage.tidy('   '), isEmpty);
      final long = ChatMessage.tidy('a' * 200);
      expect(long.length, ChatMessage.maxText);
      // An emoji is one character, not cut in half.
      final emoji = ChatMessage.tidy('😅' * 100);
      expect(emoji.runes.length, ChatMessage.maxText);
      expect(emoji, '😅' * ChatMessage.maxText);
    });

    test('survive the round trip, as words rather than a reaction', () {
      final message = ChatMessage(
        id: 't1',
        seat: 1,
        text: 'مقصدش دي وربنا',
        sentAt: DateTime(2026, 1, 1, 12),
      );
      final data = OnlineGameCodec.encodeChat(
        message: message,
        uid: 'uid-alice',
        sentAt: message.sentAt!.millisecondsSinceEpoch,
      );
      expect(data['code'], 'text');
      expect(data['text'], 'مقصدش دي وربنا');
      expect(OnlineGameCodec.decodeChat('t1', data), message);

      // A reaction carries no words.
      expect(
        OnlineGameCodec.encodeChat(
          message: from(1, 'r1', QuickChat.laugh),
          uid: 'u',
          sentAt: 0,
        ).containsKey('text'),
        isFalse,
      );
    });

    test('with nothing in them are skipped', () {
      expect(
        OnlineGameCodec.decodeChat('t', {'seat': 1, 'code': 'text'}),
        isNull,
      );
      expect(
        OnlineGameCodec.decodeChat('t', {
          'seat': 1,
          'code': 'text',
          'text': '   ',
        }),
        isNull,
      );
    });

    test('the two new quick lines say what was asked', () {
      const arabic = AppStrings(Locale('ar'));
      expect(arabic.chatLabel(QuickChat.didntMeanIt), 'مقصدش دي وربنا!');
      expect(arabic.chatLabel(QuickChat.misplayed), 'اتلعبت غلط');
      expect(QuickChat.lines, contains(QuickChat.didntMeanIt));
      expect(QuickChat.lines, contains(QuickChat.misplayed));
    });
  });

  group('typing and muting', () {
    late FakeOnlineGameService service;
    late OnlineGameController controller;
    late DateTime now;
    final arrivals = <ChatMessage>[];
    StreamSubscription<ChatMessage>? listening;

    setUp(() async {
      service = FakeOnlineGameService();
      now = DateTime(2026, 1, 1, 12);
      controller = OnlineGameController(service: service, now: () => now);
      arrivals.clear();
      listening = controller.chatArrivals.listen(arrivals.add);
      service.sessions['g'] = OnlineSession(
        game: liveGame('g'),
        localPlayerId: 1,
      );
      expect(await controller.resumeGame('g'), isTrue);
      service.pushChat('g', []);
      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      await listening?.cancel();
      controller.dispose();
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('typed words go out tidied, and show at once', () async {
      expect(await controller.sendText('  اتلعبت   غلط\n'), isTrue);
      await flush();
      expect(service.chatSent.single.text, 'اتلعبت غلط');
      expect(service.chatSent.single.item, isNull);
      expect(controller.chat.single.text, 'اتلعبت غلط');
      expect(arrivals.single.text, 'اتلعبت غلط');
    });

    test('nothing typed sends nothing', () async {
      expect(await controller.sendText('   '), isFalse);
      expect(service.chatSent, isEmpty);
      expect(controller.chat, isEmpty);
    });

    test('typing shares the cooldown with reactions', () async {
      expect(await controller.sendChat(QuickChat.laugh), isTrue);
      expect(await controller.sendText('too soon'), isFalse);
      now = now.add(OnlineGameController.chatCooldown);
      expect(await controller.sendText('now'), isTrue);
    });

    test('muted, the others are still listed but stay quiet', () async {
      service.pushChat('g', [from(2, 'b1', QuickChat.laugh)]);
      await flush();
      expect(controller.unreadChat, 1);

      controller.chatMuted = true;
      expect(controller.unreadChat, 0);
      arrivals.clear();

      service.pushChat('g', [
        from(2, 'b1', QuickChat.laugh),
        ChatMessage(id: 'b2', seat: 2, text: 'hello?', sentAt: now),
      ]);
      await flush();
      expect(controller.chat.map((m) => m.id), ['b1', 'b2']);
      expect(arrivals, isEmpty);
      expect(controller.unreadChat, 0);

      // This device's own messages still pop up.
      await controller.sendChat(QuickChat.cool);
      expect(arrivals.single.item, QuickChat.cool);

      controller.chatMuted = false;
      service.pushChat('g', [
        ...controller.chat,
        from(2, 'b3', QuickChat.angry, at: now.add(const Duration(minutes: 1))),
      ]);
      await flush();
      expect(arrivals.last.id, 'b3');
      expect(controller.unreadChat, 1);
    });
  });

  testWidgets('typed words pop up in a bubble and stay a little longer', (
    tester,
  ) async {
    final arrivals = StreamController<ChatMessage>.broadcast();
    addTearDown(arrivals.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubbleLayer(
            arrivals: arrivals.stream,
            localSeat: 1,
            nameOf: (_) => 'Bob',
            colorOf: (_) => Colors.teal,
          ),
        ),
      ),
    );
    arrivals.add(
      ChatMessage(id: 't', seat: 2, text: 'not the wall again', sentAt: null),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('not the wall again'), findsOneWidget);

    await tester.pump(ChatBubbleLayer.lineLife);
    expect(find.text('not the wall again'), findsOneWidget);
    await tester.pump(ChatBubbleLayer.textLife);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('not the wall again'), findsNothing);
  });
}
