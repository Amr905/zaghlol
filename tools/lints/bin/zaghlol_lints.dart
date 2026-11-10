import 'dart:io';

import 'package:zaghlol_lints/src/checker.dart';
import 'package:zaghlol_lints/src/runner.dart';

/// Usage: `dart run bin/zaghlol_lints.dart <dir>...`
/// Prints one line per violation and exits 1 when there is any.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: zaghlol_lints <dir>...');
    exit(64);
  }
  final files = <ParsedFile>[];
  for (final root in args) {
    final parsed = parseTree([root]);
    // A broken glob or mis-pointed root must not pass silently.
    if (countLinted(parsed) == 0) {
      stderr.writeln(
        'zaghlol_lints: error: no lintable files (.dart under lib/) found '
        'in "$root". Refusing to report success on an empty scan.',
      );
      exit(2);
    }
    files.addAll(parsed);
  }
  final violations = checkAll(files);
  for (final v in violations) {
    stdout.writeln(v);
  }
  stdout.writeln(
    'zaghlol_lints: ${countLinted(files)} file(s) scanned, '
    '${violations.length} issue(s).',
  );
  exit(violations.isEmpty ? 0 : 1);
}
