import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/services/update/app_version.dart';
import 'package:quoridor/flame/services/update/update_checker.dart';
import 'package:quoridor/flame/services/update/version_compare.dart';
import 'package:quoridor/flame/widgets/update_overlay.dart';

const running = AppVersion(version: '1.4.0', buildNumber: 100, commit: 'aaa');

UpdateChecker checker({
  UpdateRoute route = UpdateRoute.download,
  Fetch? fetch,
  StoreLookup? store,
}) => UpdateChecker(
  source: Uri.parse('https://example.com/latest.json'),
  route: route,
  fetch: fetch ?? (_) async => '{}',
  store: store,
  running: running,
);

UpdateChecker storeChecker(StoreLookup store) =>
    checker(route: UpdateRoute.store, store: store);

Map<String, Object?> published({
  String version = '1.4.0',
  int buildNumber = 100,
  String build = 'aaa',
  String? minVersion,
}) => {
  'version': version,
  'buildNumber': buildNumber,
  'build': build,
  'minVersion': ?minVersion,
  'notes': {'en': 'Faster', 'ar': 'أسرع'},
};

void main() {
  group('version comparison', () {
    test('is numeric, not alphabetical', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.9.9', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0.0', '2.0.0'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
    });

    test('a broken version decides nothing', () {
      expect(compareVersions('1.x.0', '1.0.0'), isNull);
      expect(compareVersions('', '1.0.0'), isNull);
    });
  });

  group('newer, same and older', () {
    test('a higher version is an update', () {
      expect(checker().evaluate(published(version: '1.5.0')), isNotNull);
    });

    test('the same version and build is not', () {
      expect(checker().evaluate(published()), isNull);
    });

    test('the same version with a higher build number is', () {
      expect(checker().evaluate(published(buildNumber: 101)), isNotNull);
    });

    test('an older version is not', () {
      expect(checker().evaluate(published(version: '1.3.9')), isNull);
    });
  });

  group('a rebuild of the same version', () {
    test('counts on the web', () {
      final web = checker(route: UpdateRoute.reload);
      expect(web.evaluate(published(build: 'bbb')), isNotNull);
    });

    test('does not count for installed builds', () {
      expect(checker().evaluate(published(build: 'bbb')), isNull);
    });
  });

  group('forced or optional', () {
    test('forced when running below minVersion', () {
      final info = checker().evaluate(
        published(version: '1.6.0', minVersion: '1.5.0'),
      );
      expect(info!.forced, isTrue);
    });

    test('optional when running exactly minVersion', () {
      final info = checker().evaluate(
        published(version: '1.6.0', minVersion: '1.4.0'),
      );
      expect(info!.forced, isFalse);
    });

    test('a missing or empty minVersion forces nothing', () {
      expect(checker().evaluate(published(version: '1.6.0'))!.forced, isFalse);
      expect(
        checker().evaluate(published(version: '1.6.0', minVersion: ''))!.forced,
        isFalse,
      );
    });

    test('a broken minVersion forces nothing', () {
      final info = checker().evaluate(
        published(version: '1.6.0', minVersion: 'soon'),
      );
      expect(info!.forced, isFalse);
    });
  });

  group('failures are silent', () {
    test('a network error is no update', () async {
      final c = checker(fetch: (_) async => throw const SocketException('x'));
      expect(await c.check(), isNull);
    });

    test('bad JSON is no update', () async {
      expect(await checker(fetch: (_) async => '<html>').check(), isNull);
    });

    test('a missing field is no update', () async {
      final c = checker(fetch: (_) async => jsonEncode({'version': '9.0.0'}));
      expect(await c.check(), isNull);
    });

    test('a working fetch is read, with a cache-busting query', () async {
      Uri? asked;
      final c = checker(
        fetch: (url) async {
          asked = url;
          return jsonEncode(published(version: '2.0.0'));
        },
      );
      expect((await c.check())?.version, '2.0.0');
      expect(asked!.queryParameters, contains('t'));
    });
  });

  group('store builds ask their store', () {
    test('the App Store offering a newer version is an update', () async {
      final info = await storeChecker(
        () async => const StoreRelease(version: '1.5.0'),
      ).decide(published(version: '1.5.0'));
      expect(info?.version, '1.5.0');
      expect(info?.route, UpdateRoute.store);
      expect(info?.notesFor('ar'), 'أسرع');
    });

    test('a release the store is not offering yet is not', () async {
      final info = await storeChecker(
        () async => const StoreRelease(version: '1.4.0'),
      ).decide(published(version: '1.5.0'));
      expect(info, isNull);
    });

    test('a store with nothing newer is not, whatever GitHub says', () async {
      final info = await storeChecker(
        () async => null,
      ).decide(published(version: '9.0.0'));
      expect(info, isNull);
    });

    test('Google Play names only the build; latest.json names it', () async {
      final info = await storeChecker(
        () async => const StoreRelease(buildNumber: 120),
      ).decide(published(version: '1.5.0', buildNumber: 120));
      expect(info?.version, '1.5.0');
      expect(info?.buildNumber, 120);
      expect(info?.notesFor('en'), 'Faster');
    });

    test(
      'a Play build latest.json does not describe has no name or notes',
      () async {
        final info = await storeChecker(
          () async => const StoreRelease(buildNumber: 130),
        ).decide(published(version: '1.5.0', buildNumber: 120));
        expect(info?.version, '');
        expect(info?.notes, isEmpty);
        expect(info?.route, UpdateRoute.store);
      },
    );

    test('Google Play offering this very build is not an update', () async {
      final info = await storeChecker(
        () async => StoreRelease(buildNumber: running.buildNumber),
      ).decide(published());
      expect(info, isNull);
    });

    test('latest.json still forces an update the store offers', () async {
      final info = await storeChecker(
        () async => const StoreRelease(version: '1.5.0'),
      ).decide(published(version: '1.5.0', minVersion: '1.5.0'));
      expect(info?.forced, isTrue);
    });

    test('the store is enough when GitHub cannot be reached', () async {
      final info = await storeChecker(
        () async => const StoreRelease(version: '1.5.0'),
      ).decide(null);
      expect(info?.version, '1.5.0');
      expect(info?.forced, isFalse);
    });

    test('a copy not installed from the store updates from GitHub', () async {
      final info = await storeChecker(
        () async => throw const NotFromStore(),
      ).decide(published(version: '1.5.0'));
      expect(info?.version, '1.5.0');
      expect(info?.route, UpdateRoute.download);
    });

    test('a store that cannot be asked is no update', () async {
      final info = await storeChecker(
        () async => throw StateError('offline'),
      ).decide(published(version: '1.5.0'));
      expect(info, isNull);
    });

    test("Apple's lookup answer is read", () {
      expect(
        parseAppStoreLookup(
          '{"resultCount":1,"results":[{"version":"1.5.0","bundleId":"x"}]}',
        )?.version,
        '1.5.0',
      );
      expect(parseAppStoreLookup('{"resultCount":0,"results":[]}'), isNull);
      expect(parseAppStoreLookup('<html>'), isNull);
      expect(parseAppStoreLookup('{"results":[{"version":"soon"}]}'), isNull);
    });
  });

  group('the card', () {
    Future<void> pump(WidgetTester tester, UpdateInfo info) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UpdateCard(
                info: info,
                onUpdate: () {},
                onLater: info.forced ? null : () {},
              ),
            ),
          ),
        );

    UpdateInfo info({required bool forced}) => UpdateInfo(
      version: '2.0.0',
      buildNumber: 1,
      notes: const {'en': 'Faster'},
      forced: forced,
      route: UpdateRoute.download,
    );

    testWidgets('an optional update can be put off', (tester) async {
      await pump(tester, info(forced: false));
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Faster'), findsOneWidget);
    });

    testWidgets('a forced update has no "Later"', (tester) async {
      await pump(tester, info(forced: true));
      expect(find.text('Later'), findsNothing);
      expect(find.textContaining('no longer works'), findsOneWidget);
    });

    testWidgets('a GitHub build downloads; a store build updates', (
      tester,
    ) async {
      await pump(tester, info(forced: false));
      expect(find.text('Download'), findsOneWidget);
      await pump(
        tester,
        const UpdateInfo(
          version: '',
          buildNumber: 130,
          notes: {},
          forced: false,
          route: UpdateRoute.store,
        ),
      );
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
      // Google Play did not name the version.
      expect(find.text('A new version is available'), findsOneWidget);
    });
  });

  group('release plumbing', () {
    test('the version the app reports matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*([^\s+]+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(AppVersion.current.version, version);
    });

    test('every release workflow writes latest.json with the same script', () {
      for (final name in ['pages.yml', 'release.yml']) {
        final workflow = File('.github/workflows/$name').readAsStringSync();
        expect(workflow, contains('tool/write_latest_json.py'), reason: name);
        expect(workflow, contains('BUILD_NUMBER='), reason: name);
      }
    });
  });
}
