import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

/// Table-driven: every fixture file of the pipeline test registry runs
/// through the registry lint (template match, extraction, cross-match and
/// the full pipeline keys of `expect`).
void main() {
  final files = RegistryFiles.load(pipelineRoot);
  final load = RegistryLoader.load(
    manifest: files.manifest,
    shared: files.shared,
    institutions: files.institutions,
  );

  test('the pipeline registry loads clean', () {
    expect(load.issues, isEmpty);
  });

  final registry = load.registry!;
  final paths = files.fixtures.keys.toList()..sort();

  test('fixture count and coverage', () {
    expect(paths.length, greaterThanOrEqualTo(40));
    final report = lintRegistry(
      manifest: files.manifest,
      shared: files.shared,
      institutions: files.institutions,
      fixtures: files.fixtures,
    );
    expect(report.issues.map((i) => i.toString()), isEmpty);
    expect(report.fixturesRun, report.fixturesPassed);
  });

  for (final path in paths) {
    test(path, () {
      final outcome = runFixture(registry, path, files.fixtures[path]!);
      expect(outcome.issues.map((i) => i.toString()), isEmpty);
    });
  }
}
