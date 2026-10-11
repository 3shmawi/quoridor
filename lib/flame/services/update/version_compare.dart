/// Compares dotted version strings numerically, so 1.10.0 is newer than
/// 1.9.0. Missing parts count as zero. Returns null when either side is not
/// a version at all, so a broken file never decides anything.
int? compareVersions(String a, String b) {
  final left = parseVersion(a);
  final right = parseVersion(b);
  if (left == null || right == null) return null;

  for (var i = 0; i < 3; i++) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

/// [major, minor, patch], or null when [value] is not x.y.z (x or x.y also
/// accepted).
List<int>? parseVersion(String value) {
  final parts = value.trim().split('.');
  if (parts.isEmpty || parts.length > 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  while (numbers.length < 3) {
    numbers.add(0);
  }
  return numbers;
}
