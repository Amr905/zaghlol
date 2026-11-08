import 'violation.dart';

final RegExp _ignore = RegExp(r'//\s*ignore:\s*([\w,\s]+)');
final RegExp _ignoreFile = RegExp(r'//\s*ignore_for_file:\s*([\w,\s]+)');
final RegExp _expect = RegExp(r'//\s*expect_lint:\s*([\w,\s]+)');

Set<String> _names(String list) =>
    list.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

/// Drops violations silenced by `// ignore: rule` (same or previous line) or
/// `// ignore_for_file: rule`.
List<Violation> applyIgnores(String source, List<Violation> violations) {
  final lines = source.split('\n');
  final fileIgnored = <String>{};
  for (final line in lines) {
    final m = _ignoreFile.firstMatch(line);
    if (m != null) fileIgnored.addAll(_names(m.group(1)!));
  }
  bool ignoredAt(int index, String rule) {
    if (index < 0 || index >= lines.length) return false;
    final m = _ignore.firstMatch(lines[index]);
    return m != null && _names(m.group(1)!).contains(rule);
  }

  return violations.where((v) {
    if (fileIgnored.contains(v.rule)) return false;
    return !ignoredAt(v.line - 1, v.rule) && !ignoredAt(v.line - 2, v.rule);
  }).toList();
}

/// Fixture verification: every `// expect_lint: rule` comment must match a
/// violation on the next line, and every violation must be expected.
/// Returns human-readable mismatches; empty means the file is as annotated.
List<String> verifyExpectations(
  String path,
  String source,
  List<Violation> violations,
) {
  final expected = <String>{};
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _expect.firstMatch(lines[i]);
    if (m == null) continue;
    for (final rule in _names(m.group(1)!)) {
      expected.add('${i + 2}:$rule');
    }
  }
  final actual = violations.map((v) => '${v.line}:${v.rule}').toSet();
  return [
    for (final e in expected.difference(actual))
      '$path:${e.split(':').first}: expected ${e.split(':').last} was not '
          'reported',
    for (final a in actual.difference(expected))
      '$path:${a.split(':').first}: unexpected ${a.split(':').last}',
  ];
}
