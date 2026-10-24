import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';
import 'platform_update.dart';
import 'update_checker.dart';

/// Keeps track of whether a newer build is out, for the update card.
///
/// Checks once at start and again whenever the app comes back to the
/// foreground, on every platform. Store builds ask their store.
class UpdateService with WidgetsBindingObserver {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const String _lastRunKey = 'update.lastRunVersion';

  /// The update waiting to be taken, or null.
  final ValueNotifier<UpdateInfo?> available = ValueNotifier(null);

  /// True once the player said "Later" to an optional update. The settings
  /// drawer still offers it.
  final ValueNotifier<bool> postponed = ValueNotifier(false);

  /// Set once after an update, to show "What's new" a single time.
  final ValueNotifier<UpdateInfo?> whatsNew = ValueNotifier(null);

  late final UpdateChecker _checker = UpdateChecker(
    source: latestJsonUrl,
    route: platformRoute,
    store: storeLookup,
    fetch: _fetch,
  );

  bool _started = false;
  bool _checking = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_firstCheck());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  Future<void> _firstCheck() async {
    final latest = await _checker.fetchLatest();
    _apply(await _checker.decide(latest));
    await _noteWhatsNew(latest);
  }

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      _apply(await _checker.check());
    } finally {
      _checking = false;
    }
  }

  void _apply(UpdateInfo? info) {
    // A failed check says nothing; it never clears an update already found.
    if (info == null) return;
    final previous = available.value;
    available.value = info;
    if (previous?.version != info.version) postponed.value = false;
    if (info.forced) postponed.value = false;
  }

  /// Shows "What's new" once, on the first run of a new version.
  Future<void> _noteWhatsNew(Object? latest) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_lastRunKey);
      final current = AppVersion.current.version;
      await prefs.setString(_lastRunKey, current);

      // A first install has nothing to compare with, so nothing is new.
      if (last == null || last == current) return;
      if (latest is! Map || latest['version'] != current) return;

      final notes = <String, String>{};
      final raw = latest['notes'];
      if (raw is Map) {
        raw.forEach((k, v) {
          if (k is String && v is String) notes[k] = v;
        });
      }
      if (notes.isEmpty) return;
      whatsNew.value = UpdateInfo(
        version: current,
        buildNumber: AppVersion.current.buildNumber,
        notes: notes,
        forced: false,
        route: platformRoute,
      );
    } catch (error) {
      debugPrint('UpdateService: whats-new skipped: $error');
    }
  }

  void later() => postponed.value = true;

  Future<void> update() => applyUpdate(available.value?.route ?? platformRoute);

  static Future<String> _fetch(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw StateError('latest.json: HTTP ${response.statusCode}');
    }
    return response.body;
  }
}
