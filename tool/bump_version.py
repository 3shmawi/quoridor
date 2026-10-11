#!/usr/bin/env python3
"""Raises the app version in pubspec.yaml and in the app's own copy of it.

Usage: python3 tool/bump_version.py patch|minor|major
Prints the new version. The build number is not kept in pubspec.yaml: the
release workflow uses its run number, so two uploads can never collide.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / 'pubspec.yaml'
APP_VERSION = ROOT / 'lib/flame/services/update/app_version.dart'


def main():
    part = sys.argv[1] if len(sys.argv) > 1 else ''
    if part not in ('patch', 'minor', 'major'):
        sys.exit('usage: bump_version.py patch|minor|major')

    pubspec = PUBSPEC.read_text()
    m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)', pubspec, re.M)
    if not m:
        sys.exit('pubspec.yaml has no x.y.z version')
    major, minor, patch = map(int, m.groups())
    if part == 'major':
        major, minor, patch = major + 1, 0, 0
    elif part == 'minor':
        minor, patch = minor + 1, 0
    else:
        patch += 1
    new = f'{major}.{minor}.{patch}'

    PUBSPEC.write_text(
        re.sub(r'^version:.*$', f'version: {new}', pubspec, count=1, flags=re.M)
    )
    dart = APP_VERSION.read_text()
    dart, n = re.subn(
        r"(String\.fromEnvironment\('APP_VERSION', defaultValue: ')[^']*'",
        rf"\g<1>{new}'",
        dart,
    )
    if n != 1:
        sys.exit('could not find the APP_VERSION default in app_version.dart')
    APP_VERSION.write_text(dart)
    print(new)


if __name__ == '__main__':
    main()
