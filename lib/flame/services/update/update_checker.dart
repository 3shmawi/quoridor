import 'dart:async';
import 'dart:convert';

import 'app_version.dart';
import 'version_compare.dart';

/// How an update is taken.
enum UpdateRoute {
  /// Web: reloading the page fetches the new build.
  reload,

  /// Installed builds: open the release page to download it.
  download,
}

/// A release newer than the running build.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.notes,
    required this.forced,
    required this.route,
  });

  final String version;
  final int buildNumber;

  /// Release notes by language code ("en", "ar").
  final Map<String, String> notes;

  /// True when this build is older than the published minimum and must not
  /// be used any more.
  final bool forced;

  final UpdateRoute route;

  String notesFor(String languageCode) =>
      notes[languageCode] ?? notes['en'] ?? '';
}

/// Fetches the body at a URL, or throws.
typedef Fetch = Future<String> Function(Uri url);

/// Reads the published `latest.json` and says whether this build is behind.
///
/// Any failure -- offline, a 404, bad JSON, a missing field -- is "no
/// update" and says nothing. An update check must never be the reason the
/// game does not start.
class UpdateChecker {
  UpdateChecker({
    required this.source,
    required this.route,
    required this.fetch,
    this.running = AppVersion.current,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri source;
  final UpdateRoute route;
  final Fetch fetch;
  final AppVersion running;
  final Duration timeout;

  Future<UpdateInfo?> check() async => evaluate(await fetchLatest());

  /// The published `latest.json`, decoded, or null on any failure.
  Future<Object?> fetchLatest() async {
    try {
      // A query that changes every time, so no cache between here and the
      // server hands back yesterday's file.
      final url = source.replace(
        queryParameters: {
          ...source.queryParameters,
          't': '${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      final body = await fetch(url).timeout(timeout);
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  /// Decides from an already-decoded `latest.json`. Public for tests.
  UpdateInfo? evaluate(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final buildNumber = json['buildNumber'];
    if (version is! String || buildNumber is! int) return null;

    final order = compareVersions(version, running.version);
    if (order == null) return null;

    final newer =
        order > 0 ||
        (order == 0 && buildNumber > running.buildNumber) ||
        (order == 0 && route == UpdateRoute.reload && _isRebuild(json));
    if (!newer) return null;

    final minVersion = json['minVersion'];
    final forced =
        minVersion is String &&
        minVersion.isNotEmpty &&
        (compareVersions(running.version, minVersion) ?? 0) < 0;

    final notes = <String, String>{};
    final rawNotes = json['notes'];
    if (rawNotes is Map) {
      rawNotes.forEach((key, value) {
        if (key is String && value is String) notes[key] = value;
      });
    }

    return UpdateInfo(
      version: version,
      buildNumber: buildNumber,
      notes: notes,
      forced: forced,
      route: route,
    );
  }

  /// Web only: the same version rebuilt from a different commit. A local
  /// build knows no commit and never counts as stale.
  bool _isRebuild(Map json) {
    final build = json['build'];
    return build is String &&
        build.isNotEmpty &&
        running.commit.isNotEmpty &&
        build != running.commit;
  }
}
