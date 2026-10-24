import 'package:web/web.dart' as web;

import 'update_checker.dart';

/// Deployed next to the site itself.
final Uri latestJsonUrl = Uri.base.resolve('latest.json');

UpdateRoute get platformRoute => UpdateRoute.reload;

/// The site is its own store.
StoreLookup? get storeLookup => null;

Future<void> applyUpdate(UpdateRoute route) async {
  web.window.location.reload();
}
