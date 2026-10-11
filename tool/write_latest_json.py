#!/usr/bin/env python3
"""Writes latest.json, the file the in-app update checker reads.

Usage: python3 tool/write_latest_json.py <output path>

Every release workflow calls this one script, so the web build and the
installed builds always describe themselves the same way.

  version      from pubspec.yaml (without the +build suffix)
  buildNumber  BUILD_NUMBER, else GITHUB_RUN_NUMBER (the CI run number)
  build        BUILD_SHA, else GITHUB_SHA (the commit; the web checker uses it)
  minVersion   release/min_version.txt; empty means no forced update
  notes        release/notes.json, else commit subjects since the last tag
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION_RE = re.compile(r'^\d+\.\d+\.\d+$')


def fail(message):
    print(f'write_latest_json: {message}', file=sys.stderr)
    sys.exit(1)


def pubspec_version():
    with open(os.path.join(ROOT, 'pubspec.yaml')) as f:
        for line in f:
            m = re.match(r'^version:\s*([^\s+]+)', line)
            if m:
                return m.group(1)
    fail('no version in pubspec.yaml')


def min_version():
    path = os.path.join(ROOT, 'release', 'min_version.txt')
    if not os.path.exists(path):
        return ''
    value = open(path).read().strip()
    if value and not VERSION_RE.match(value):
        fail(f'release/min_version.txt must be x.y.z or empty, got {value!r}')
    return value


def git(*args):
    return subprocess.run(
        ['git', *args], cwd=ROOT, capture_output=True, text=True
    ).stdout.strip()


def notes():
    path = os.path.join(ROOT, 'release', 'notes.json')
    if os.path.exists(path):
        data = json.load(open(path))
        if not isinstance(data, dict):
            fail('release/notes.json must be an object of language -> text')
        return {k: str(v) for k, v in data.items()}

    last_tag = git('describe', '--tags', '--abbrev=0')
    span = f'{last_tag}..HEAD' if last_tag else 'HEAD'
    subjects = git('log', '--no-merges', '--format=- %s', '-n', '20', span)
    return {'en': subjects, 'ar': subjects}


def main():
    if len(sys.argv) != 2:
        fail('usage: write_latest_json.py <output path>')

    version = pubspec_version()
    if not VERSION_RE.match(version):
        fail(f'pubspec version must be x.y.z, got {version!r}')

    build_number = os.environ.get('BUILD_NUMBER') or os.environ.get(
        'GITHUB_RUN_NUMBER', '0'
    )
    if not build_number.isdigit():
        fail(f'build number must be a whole number, got {build_number!r}')

    data = {
        'version': version,
        'buildNumber': int(build_number),
        'build': os.environ.get('BUILD_SHA') or os.environ.get('GITHUB_SHA', ''),
        'minVersion': min_version(),
        'notes': notes(),
    }

    out = sys.argv[1]
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(json.dumps(data, ensure_ascii=False))


if __name__ == '__main__':
    main()
