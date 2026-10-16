import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Android build settings, read as plain text.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  int sdk(String name) =>
      int.parse(RegExp('$name\\s*=\\s*(\\d+)').firstMatch(gradle)!.group(1)!);

  // Google Play refused the 1.1.3 bundle ("Target SDK of artifact is too
  // low") once its floor rose to API 36 on 31 August 2026.
  test('the app targets an SDK Google Play still accepts', () {
    expect(sdk('targetSdk'), greaterThanOrEqualTo(36));
  });

  test('the app compiles against the SDK it targets', () {
    expect(sdk('compileSdk'), greaterThanOrEqualTo(sdk('targetSdk')));
  });
}
