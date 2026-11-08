import 'dart:io';

import 'checker.dart';
import 'class_graph.dart';
import 'comments.dart';
import 'violation.dart';

/// Parses every `.dart` file below [roots] that sits under a `lib/` directory.
List<ParsedFile> parseTree(List<String> roots) {
  final files = <ParsedFile>[];
  for (final root in roots) {
    final entities = Directory(root).listSync(recursive: true);
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.contains('/.dart_tool/') || path.contains('/build/')) continue;
      files.add(ParsedFile.parse(path, entity.readAsStringSync()));
    }
  }
  return files;
}

/// Violations over all [files] (only files under `lib/` are checked).
List<Violation> checkAll(List<ParsedFile> files) {
  final graph = ClassGraph();
  for (final f in files) {
    graph.addUnit(f.unit);
  }
  return [for (final f in files) ...checkFile(f, graph)];
}

/// Fixture mode: mismatches between `// expect_lint:` comments and reports.
List<String> verifyAll(List<ParsedFile> files) {
  final graph = ClassGraph();
  for (final f in files) {
    graph.addUnit(f.unit);
  }
  return [
    for (final f in files)
      ...verifyExpectations(f.path, f.source, checkFile(f, graph)),
  ];
}
