import 'package:web/web.dart' as web;

import 'update_checker.dart';

/// Deployed next to the site itself.
final Uri latestJsonUrl = Uri.base.resolve('latest.json');

const UpdateRoute platformRoute = UpdateRoute.reload;

Future<void> applyUpdate() async {
  web.window.location.reload();
}
