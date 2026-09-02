/// Pure semantic-version helpers for GitHub release tags.
///
/// Zero imports beyond `dart:core` so the comparison logic can be unit-tested
/// in isolation and reused without any I/O or platform dependencies.
library;

/// Strips one leading `v` (case-insensitive) and any `+build` suffix from a
/// release tag: `'v1.2.0+3'` → `'1.2.0'`, `'1.2.0'` → `'1.2.0'`.
String stripVersionTag(String tag) {
  var s = tag.trim();
  if (s.isNotEmpty && (s.codeUnitAt(0) == 0x76 /* v */ || s.codeUnitAt(0) == 0x56 /* V */)) {
    s = s.substring(1);
  }
  final plus = s.indexOf('+');
  if (plus != -1) s = s.substring(0, plus);
  return s;
}

/// Compares two semantic-version strings ([a] against [b]).
///
/// Returns a negative number if `a < b`, zero if equal, positive if `a > b`.
/// One leading `v` and `+build` suffixes are ignored; missing components
/// count as zero, so `'1.2'` equals `'1.2.0'`.
///
/// Throws [FormatException] for a tag that isn't numeric
/// `major[.minor[.patch]]` — callers must treat that as an error, never as
/// "older", so a malformed release cannot silently hide an update.
int compareVersions(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

/// Parses a version string into exactly three ints (major, minor, patch).
List<int> _parse(String version) {
  final core = stripVersionTag(version);
  final parts = core.split('.');
  if (parts.isEmpty || parts.length > 3) {
    throw FormatException('Not a major[.minor[.patch]] version: "$version"');
  }
  final nums = <int>[];
  for (final part in parts) {
    // int.tryParse accepts signs and whitespace; versions are bare digits.
    if (part.isEmpty || !part.runes.every((r) => r >= 0x30 && r <= 0x39)) {
      throw FormatException('Not a numeric version component: "$version"');
    }
    nums.add(int.parse(part));
  }
  while (nums.length < 3) {
    nums.add(0);
  }
  return nums;
}
