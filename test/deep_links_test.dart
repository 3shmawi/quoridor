import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/models/online_session.dart';
import 'package:quoridor/flame/pages/game_page.dart';
import 'package:quoridor/flame/services/ai_service.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/get_app/get_app.dart';
import 'package:quoridor/flame/services/online/invite/app_link_invites.dart';
import 'package:quoridor/flame/services/online/invite/invite_link.dart';
import 'package:quoridor/flame/services/online/online_game_controller.dart';
import 'package:quoridor/flame/services/settings_service.dart';
import 'package:quoridor/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_online_game_service.dart';

/// Invite links that open the installed app, and the web copy pointing
/// phones to it.

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
  String roomCode = 'ROOM11',
  OnlineGameStatus status = OnlineGameStatus.active,
  int? winner,
}) => OnlineGame(
  gameId: id,
  roomCode: roomCode,
  status: status,
  players: {
    1: OnlinePlayer(
      uid: 'uid-alice',
      displayName: 'Alice',
      lastSeen: DateTime.now().add(const Duration(days: 1)),
    ),
    2: OnlinePlayer(
      uid: 'uid-bob',
      displayName: 'Bob',
      lastSeen: DateTime.now().add(const Duration(days: 1)),
    ),
  },
  currentPlayerId: 1,
  moveCount: 4,
  board: GameStateFactory.createNewGame(gameId: id, player2IsAI: false),
  winnerPlayerId: winner,
  outcomeReason: winner == null ? null : OnlineOutcomeReason.goal,
);

void main() {
  group('the platforms agree on where links open the app', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final pages = File('.github/workflows/pages.yml').readAsStringSync();

    test('invites lead to the first of the sites', () {
      expect(InviteLink.webHome.host, InviteLink.hosts.first);
      expect(InviteLink.webHome.scheme, 'https');
    });

    test('Android opens invite links on every site, and only the root', () {
      final filter = RegExp(
        r'<intent-filter android:autoVerify="true">(.*?)</intent-filter>',
        dotAll: true,
      ).firstMatch(manifest)!.group(1)!;
      final hosts = RegExp(
        r'android:host="([^"]+)"',
      ).allMatches(filter).map((m) => m.group(1));
      expect(hosts, InviteLink.hosts);
      expect(filter, contains('android:scheme="https"'));
      expect(filter, contains('android.intent.action.VIEW'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
      // The privacy page and /get/ must stay in the browser, or the app's
      // own Privacy policy link would open the app again.
      expect(filter, contains('android:path="/"'));
      expect(filter, isNot(contains('pathPrefix')));
      expect(
        manifest,
        contains(
          '<meta-data android:name="flutter_deeplinking_enabled" '
          'android:value="false"/>',
        ),
      );
    });

    test('iOS opens invite links on every site', () {
      final domains = RegExp(
        r'<string>applinks:([^<]+)</string>',
      ).allMatches(entitlements).map((m) => m.group(1));
      expect(domains, InviteLink.hosts);
      // Every build of the app target signs with them.
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
            .allMatches(project)
            .length,
        3,
      );
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(
        RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
        ).hasMatch(plist),
        isTrue,
      );
    });

    test('the site is deployed to every one of those addresses', () {
      final projects = RegExp(
        r'PROJECTS: (.+)',
      ).firstMatch(pages)!.group(1)!.trim().split(' ');
      expect(projects.map((p) => '$p.pages.dev'), InviteLink.hosts);
    });

    test('the site vouches for the Android app', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final appId = RegExp(
        r'applicationId\s*=\s*"([^"]+)"',
      ).firstMatch(gradle)!.group(1)!;
      final links =
          jsonDecode(File('web/.well-known/assetlinks.json').readAsStringSync())
              as List;
      final target = (links.single as Map)['target'] as Map;
      expect(target['package_name'], appId);
      final prints = (target['sha256_cert_fingerprints'] as List)
          .cast<String>();
      expect(prints, isNotEmpty);
      for (final print in prints) {
        expect(print, matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')));
      }
      // Google Play re-signs the store build with its app signing key, so
      // Android verifies the links against that certificate, not the upload
      // key (which still signs the APKs on GitHub Releases).
      expect(
        prints,
        contains(
          '98:28:6E:8B:65:D1:69:F0:15:F9:BC:60:58:5D:FC:0D:'
          'B4:ED:7D:2C:EF:71:C4:E8:79:35:D2:CD:4E:A0:33:79',
        ),
      );
    });

    test('the site vouches for the iOS app, for invite links only', () {
      final bundleId = RegExp(
        r'PRODUCT_BUNDLE_IDENTIFIER = ([^;.]+\.[^;.]+\.[^;.]+);',
      ).firstMatch(project)!.group(1)!;
      final aasa =
          jsonDecode(
                File(
                  'web/.well-known/apple-app-site-association',
                ).readAsStringSync(),
              )
              as Map;
      final details =
          ((aasa['applinks'] as Map)['details'] as List).single as Map;
      final ids = (details['appIDs'] as List).cast<String>();
      expect(ids, contains('9RA43G2P63.$bundleId'));
      for (final id in ids) {
        expect(
          id,
          matches(RegExp(r'^[A-Z0-9]{10}\.' + RegExp.escape(bundleId))),
        );
      }
      final component = (details['components'] as List).single as Map;
      expect(component['/'], '/');
      expect((component['?'] as Map)[InviteLink.parameter], '?*');
    });

    test('both files are served as JSON', () {
      final headers = File('web/_headers').readAsStringSync();
      for (final path in [
        '/.well-known/apple-app-site-association',
        '/.well-known/assetlinks.json',
      ]) {
        expect(
          RegExp(
            '${RegExp.escape(path)}\\s*\\n\\s*Content-Type: application/json',
          ).hasMatch(headers),
          isTrue,
          reason: path,
        );
      }
    });

    test('Safari offers the App Store app', () {
      final index = File('web/index.html').readAsStringSync();
      expect(
        index,
        contains('<meta name="apple-itunes-app" content="app-id=6752514464">'),
      );
      expect(GetApp.appStore.toString(), endsWith('id6752514464'));
    });
  });

  group('links handed to the app', () {
    Uri invite(String code) => InviteLink.forCode(code);

    test('the link it opened with is joined once, not twice', () async {
      final links = StreamController<Uri>();
      final invites = await AppLinkInvites.from(
        initial: () async => invite('ABC123'),
        links: links.stream,
      );
      expect(invites.first, 'ABC123');

      final later = <String>[];
      invites.later.listen(later.add);
      // The stream repeats the opening link first.
      links
        ..add(invite('ABC123'))
        ..add(invite('XYZ789'))
        ..add(invite('ABC123'));
      await Future<void>.delayed(Duration.zero);
      expect(later, ['XYZ789', 'ABC123']);
    });

    test('opened normally, every later link counts', () async {
      final links = StreamController<Uri>();
      final invites = await AppLinkInvites.from(
        initial: () async => null,
        links: links.stream,
      );
      expect(invites.first, isNull);
      final later = <String>[];
      invites.later.listen(later.add);
      links.add(invite('ABC123'));
      await Future<void>.delayed(Duration.zero);
      expect(later, ['ABC123']);
    });

    test(
      'links without a room code, or on the old site, are handled',
      () async {
        final links = StreamController<Uri>();
        final invites = await AppLinkInvites.from(
          initial: () async => throw Exception('no channel'),
          links: links.stream,
        );
        expect(invites.first, isNull);
        final later = <String>[];
        invites.later.listen(later.add);
        links
          ..add(Uri.parse('https://playquoridor.pages.dev/'))
          ..add(Uri.parse('https://playquoridor.pages.dev/?join=nope'))
          ..add(Uri.parse('https://quoridor-mohager.pages.dev/?join=ABC123'));
        await Future<void>.delayed(Duration.zero);
        expect(later, ['ABC123']);
      },
    );
  });

  group('getting the app from a browser', () {
    test('each device goes to its own store', () {
      expect(GetApp.linkFor(WebDevice.ios), GetApp.appStore);
      expect(GetApp.linkFor(WebDevice.iosSafari), GetApp.appStore);
      expect(GetApp.linkFor(WebDevice.android), GetApp.googlePlay);
      expect(
        GetApp.linkFor(WebDevice.desktop).toString(),
        'https://playquoridor.pages.dev/get/',
      );
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        GetApp.googlePlay.queryParameters['id'],
        RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)!.group(1),
      );
    });

    test('the browser is told apart by its user agent', () {
      const iphoneSafari =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
          'Mobile/15E148 Safari/604.1';
      const iphoneChrome =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0 '
          'Mobile/15E148 Safari/604.1';
      const iphoneTikTok =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
          'musical_ly_37.0 TikTok';
      const ipadDesktop =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
      const android =
          'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
      const mac = ipadDesktop;
      const windows =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/130.0 Safari/537.36';

      expect(webDeviceFor(iphoneSafari), WebDevice.iosSafari);
      expect(webDeviceFor(iphoneChrome), WebDevice.ios);
      expect(webDeviceFor(iphoneTikTok), WebDevice.ios);
      expect(webDeviceFor(ipadDesktop, touchPoints: 5), WebDevice.iosSafari);
      expect(webDeviceFor(android), WebDevice.android);
      expect(webDeviceFor(mac), WebDevice.desktop);
      expect(webDeviceFor(windows), WebDevice.desktop);
    });

    test('the bar shows on phones, except where Safari has its own', () {
      expect(GetApp.offersBanner(WebDevice.android), isTrue);
      expect(GetApp.offersBanner(WebDevice.ios), isTrue);
      expect(GetApp.offersBanner(WebDevice.iosSafari), isFalse);
      expect(GetApp.offersBanner(WebDevice.desktop), isFalse);
      expect(GetApp.offersBanner(null), isFalse);
    });
  });

  group('the page', () {
    late FakeOnlineGameService service;
    late List<String?> lobbyCodes;
    late List<Uri> opened;
    late StreamController<String> links;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SettingsService.instance.appBannerClosed.value = false;
      AIService.search = AIService.searchInline;
      AudioService.instance.debugOut = _SilentAudio();
      service = FakeOnlineGameService();
      lobbyCodes = [];
      opened = [];
      links = StreamController<String>.broadcast();
    });

    Future<void> settle(WidgetTester tester, {int frames = 10}) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(
      WidgetTester tester, {
      OnlineGame? game,
      WebDevice? device,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (game != null) {
        service.sessions[game.gameId] = OnlineSession(
          game: game,
          localPlayerId: 1,
        );
      }
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
            inviteLinks: links.stream,
            webDevice: device,
            openLink: (link) async => opened.add(link),
            openLobby: (_, joinCode) async {
              lobbyCodes.add(joinCode);
              if (game == null) return null;
              final controller = OnlineGameController(service: service);
              await controller.resumeGame(game.gameId);
              return controller;
            },
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    }

    testWidgets('a link opened while the app is running joins its game', (
      tester,
    ) async {
      await open(tester, game: table('g'));
      // The mode sheet is up, as on any start.
      expect(find.text('Choose Game Mode'), findsOneWidget);

      links.add('ROOM11');
      await settle(tester);

      expect(lobbyCodes, ['ROOM11']);
      expect(find.text('Choose Game Mode'), findsNothing);
      expect(find.byKey(const Key('chatButton')), findsOneWidget);

      // Opening the same invite again changes nothing.
      links.add('ROOM11');
      await settle(tester, frames: 3);
      expect(lobbyCodes, ['ROOM11']);
      await finish(tester);
    });

    testWidgets('a link to another game waits for this one to be left', (
      tester,
    ) async {
      await open(tester, game: table('g'));
      links.add('ROOM11');
      await settle(tester);

      links.add('OTHER1');
      await settle(tester, frames: 3);
      expect(lobbyCodes, ['ROOM11']);
      expect(find.text('Leave the online game first'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a link after an online game ends joins the new one', (
      tester,
    ) async {
      await open(tester, game: table('g'));
      links.add('ROOM11');
      await settle(tester);
      service.push(table('g', status: OnlineGameStatus.finished, winner: 2));
      await settle(tester, frames: 3);

      links.add('OTHER1');
      await settle(tester, frames: 3);
      expect(lobbyCodes, ['ROOM11', 'OTHER1']);
      await finish(tester);
    });

    testWidgets('a phone browser offers the app above the board', (
      tester,
    ) async {
      // Loading the settings is what starts saving them.
      await SettingsService.instance.load();
      await open(tester, device: WebDevice.android);
      // Off the mode sheet, onto the board.
      await tester.tapAt(const Offset(180, 90));
      await settle(tester, frames: 5);

      expect(find.byKey(const Key('appBanner')), findsOneWidget);
      expect(find.text('Quoridor plays best in the app'), findsOneWidget);
      await tester.tap(find.byKey(const Key('appBannerGet')));
      await settle(tester, frames: 2);
      expect(opened, [GetApp.googlePlay]);

      // Closed once, it stays closed.
      await tester.tap(find.byKey(const Key('appBannerClose')));
      await settle(tester, frames: 2);
      expect(find.byKey(const Key('appBanner')), findsNothing);
      expect(SettingsService.instance.appBannerClosed.value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings.appBannerClosed'), isTrue);
      await finish(tester);
    });

    for (final device in [null, WebDevice.iosSafari, WebDevice.desktop]) {
      testWidgets('no bar ${device == null ? 'in the app' : 'on $device'}', (
        tester,
      ) async {
        await open(tester, device: device);
        expect(find.byKey(const Key('appBanner')), findsNothing);
        await finish(tester);
      });
    }

    testWidgets('after an online game in a browser, the app is offered', (
      tester,
    ) async {
      await open(tester, game: table('g'), device: WebDevice.ios);
      links.add('ROOM11');
      await settle(tester);
      expect(find.byKey(const Key('getAppAfterGame')), findsNothing);

      service.push(table('g', status: OnlineGameStatus.finished, winner: 2));
      await settle(tester, frames: 3);
      await tester.tap(find.byKey(const Key('getAppAfterGame')));
      await settle(tester, frames: 2);
      expect(opened, [GetApp.appStore]);
      await finish(tester);
    });

    testWidgets('the installed app offers nothing after a game', (
      tester,
    ) async {
      await open(tester, game: table('g'));
      links.add('ROOM11');
      await settle(tester);
      service.push(table('g', status: OnlineGameStatus.finished, winner: 2));
      await settle(tester, frames: 3);
      expect(find.byKey(const Key('getAppAfterGame')), findsNothing);
      await finish(tester);
    });

    testWidgets('after a game on one device in a browser too', (tester) async {
      await open(tester, device: WebDevice.desktop);
      await tester.scrollUntilVisible(
        find.text('Two Players'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await settle(tester, frames: 3);
      await tester.tap(find.text('Two Players'));
      await settle(tester);
      final game = tester
          .state<GameWidgetState<QuoridorGame>>(
            find.byType(GameWidget<QuoridorGame>),
          )
          .currentGame;
      game.updateGameState(
        GameStateFactory.createNewGame(gameId: 'won')
          ..status = GameStatus.player1Won,
      );
      await settle(tester, frames: 40);

      await tester.tap(find.byKey(const Key('getAppAfterGame')));
      await settle(tester, frames: 2);
      expect(opened.single.toString(), 'https://playquoridor.pages.dev/get/');
      await finish(tester);
    });
  });
}
