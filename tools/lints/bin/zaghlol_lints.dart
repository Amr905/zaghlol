import 'dart:io';

import 'package:zaghlol_lints/src/runner.dart';

/// Usage: `dart run bin/zaghlol_lints.dart <dir>...`
/// Prints one line per violation and exits 1 when there is any.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: zaghlol_lints <dir>...');
    exit(64);
  }
  final violations = checkAll(parseTree(args));
  for (final v in violations) {
    stdout.writeln(v);
  }
  stdout.writeln('zaghlol_lints: ${violations.length} issue(s).');
  exit(violations.isEmpty ? 0 : 1);
}
