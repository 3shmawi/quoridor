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
}) => UpdateChecker(
  source: Uri.parse('https://example.com/latest.json'),
  route: route,
  fetch: fetch ?? (_) async => '{}',
  running: running,
);

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
      for (final name in ['deploy-pages.yml', 'release.yml']) {
        final workflow = File('.github/workflows/$name').readAsStringSync();
        expect(workflow, contains('tool/write_latest_json.py'), reason: name);
        expect(workflow, contains('APP_BUILD_NUMBER'), reason: name);
      }
    });
  });
}
