import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the release workflows, read as plain text.
void main() {
  final workflows = Directory(
    '.github/workflows',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.yml')).toList();

  /// Shell commands with `\` continuations joined, so one `flutter build`
  /// reads as one line however it is wrapped.
  List<String> commands(File file) =>
      file.readAsStringSync().replaceAll(RegExp(r'\\\n\s*'), ' ').split('\n');

  List<String> builds(String name) => commands(
    File('.github/workflows/$name'),
  ).where((line) => line.contains('flutter build ')).toList();

  test('every release build carries a build number', () {
    final lines = [...builds('release.yml'), ...builds('pages.yml')];
    expect(lines, isNotEmpty);
    for (final line in lines) {
      expect(line, contains('--build-number='), reason: line.trim());
      expect(
        line,
        contains('--dart-define=BUILD_NUMBER='),
        reason: line.trim(),
      );
    }
  });

  test('no release build points at another entry point', () {
    for (final line in [...builds('release.yml'), ...builds('pages.yml')]) {
      expect(line, isNot(matches(RegExp(r'\s(-t|--target)[\s=]'))));
    }
  });

  test('every workflow uses the Flutter version pinned in .fvmrc', () {
    final pinned = RegExp(
      r'"flutter":\s*"([^"]+)"',
    ).firstMatch(File('.fvmrc').readAsStringSync())!.group(1);

    for (final file in workflows) {
      final text = file.readAsStringSync();
      if (!text.contains('subosito/flutter-action')) continue;
      expect(text, contains('FLUTTER_VERSION: $pinned'), reason: file.path);
      // No job may name a version of its own.
      final versions = RegExp(
        r'flutter-version:\s*(\S+)',
      ).allMatches(text).map((m) => m.group(1)).toSet();
      expect(versions, {r'${{'}, reason: file.path);
    }
  });
}
