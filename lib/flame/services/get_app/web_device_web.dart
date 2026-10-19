import 'package:web/web.dart' as web;

import 'get_app.dart';

/// The device this browser runs on, read from its user agent.
WebDevice? currentWebDevice() => webDeviceFor(
  web.window.navigator.userAgent,
  touchPoints: web.window.navigator.maxTouchPoints,
);
