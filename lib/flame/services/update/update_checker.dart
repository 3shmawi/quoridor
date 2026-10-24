import 'dart:async';
import 'dart:convert';

import 'app_version.dart';
import 'version_compare.dart';

/// How an update is taken.
enum UpdateRoute {
  /// Web: reloading the page fetches the new build.
  reload,

  /// Builds from GitHub Releases: open the release page to download it.
  download,

  /// Store builds: open the app's store page. The store, not latest.json,
  /// decides whether there is an update, so nobody is sent for a build the
  /// store is not offering yet.
  store,
}

/// The newest build a store offers, as far as it says. The App Store names
/// the version; Google Play gives only the version code (our build number).
class StoreRelease {
  const StoreRelease({this.version, this.buildNumber});

  final String? version;
  final int? buildNumber;
}

/// Asks the store for its newest build: null when it has nothing newer or
/// cannot be asked. Throws [NotFromStore] when this copy was not installed
/// from the store, so it updates the way it came, from GitHub Releases.
typedef StoreLookup = Future<StoreRelease?> Function();

class NotFromStore implements Exception {
  const NotFromStore();
}

/// The App Store's lookup answer for this app, read as a release; null when
/// it does not list the app or the body is not what Apple sends.
StoreRelease? parseAppStoreLookup(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final results = json['results'];
    if (results is! List || results.isEmpty) return null;
    final app = results.first;
    if (app is! Map) return null;
    final version = app['version'];
    if (version is! String || parseVersion(version) == null) return null;
    return StoreRelease(version: version);
  } catch (_) {
    return null;
  }
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

  /// x.y.z, or empty when the store does not say which version it offers
  /// and latest.json does not describe that build.
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
    this.store,
    this.running = AppVersion.current,
    this.timeout = const Duration(seconds: 10),
  });

  final Uri source;
  final UpdateRoute route;
  final Fetch fetch;

  /// Required for [UpdateRoute.store].
  final StoreLookup? store;
  final AppVersion running;
  final Duration timeout;

  Future<UpdateInfo?> check() async => decide(await fetchLatest());

  /// Decides from an already-fetched `latest.json`, asking the store first
  /// when this build updates through one.
  Future<UpdateInfo?> decide(Object? latest) async {
    if (route != UpdateRoute.store) return evaluate(latest);
    try {
      return evaluate(latest, store: await store!().timeout(timeout));
    } on NotFromStore {
      return evaluate(latest, via: UpdateRoute.download);
    } catch (_) {
      return null;
    }
  }

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

  /// Decides from an already-decoded `latest.json` and, for the store
  /// route, what the store offers. Public for tests.
  UpdateInfo? evaluate(Object? json, {StoreRelease? store, UpdateRoute? via}) {
    final route = via ?? this.route;
    if (route == UpdateRoute.store) return _fromStore(json, store);
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

    return UpdateInfo(
      version: version,
      buildNumber: buildNumber,
      notes: _notes(json),
      forced: _forced(json),
      route: route,
    );
  }

  /// The store decides whether there is an update; latest.json still says
  /// whether this build is too old to use, and names and describes the
  /// store's build when it is the same one.
  UpdateInfo? _fromStore(Object? json, StoreRelease? store) {
    if (store == null) return null;
    final latest = json is Map ? json : const {};
    final bool newer;
    if (store.version != null) {
      final order = compareVersions(store.version!, running.version);
      if (order == null) return null;
      newer =
          order > 0 ||
          (order == 0 && (store.buildNumber ?? 0) > running.buildNumber);
    } else if (store.buildNumber != null) {
      newer = store.buildNumber! > running.buildNumber;
    } else {
      return null;
    }
    if (!newer) return null;

    final latestVersion = latest['version'];
    final latestBuild = latest['buildNumber'];
    final same =
        latestVersion is String &&
        (store.version != null
            ? latestVersion == store.version
            : latestBuild == store.buildNumber);

    return UpdateInfo(
      version: store.version ?? (same ? latestVersion : ''),
      buildNumber:
          store.buildNumber ?? (same && latestBuild is int ? latestBuild : 0),
      notes: same ? _notes(latest) : const {},
      forced: _forced(latest),
      route: UpdateRoute.store,
    );
  }

  bool _forced(Map json) {
    final minVersion = json['minVersion'];
    return minVersion is String &&
        minVersion.isNotEmpty &&
        (compareVersions(running.version, minVersion) ?? 0) < 0;
  }

  static Map<String, String> _notes(Map json) {
    final notes = <String, String>{};
    final rawNotes = json['notes'];
    if (rawNotes is Map) {
      rawNotes.forEach((key, value) {
        if (key is String && value is String) notes[key] = value;
      });
    }
    return notes;
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
