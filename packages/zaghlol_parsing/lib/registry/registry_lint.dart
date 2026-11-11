import 'fixture_runner.dart';
import 'guard_export.dart';
import 'registry_issue.dart';
import 'registry_loader.dart';

/// Result of a full lint run.
final class LintReport {
  const LintReport({
    required this.issues,
    required this.fixturesRun,
    required this.fixturesPassed,
    required this.registry,
    required this.guardConfigJson,
  });

  /// Every problem; empty means the registry is clean.
  final List<RegistryIssue> issues;
  final int fixturesRun;
  final int fixturesPassed;
  final Registry? registry;

  /// Guard config for the registry, null when it could not be built.
  final String? guardConfigJson;

  bool get ok => issues.isEmpty;
}

/// Fewest fixtures each template must have (FR-PAR-01).
const int defaultMinFixturesPerTemplate = 4;

/// Lints a registry: schema, regex compile and safety (inside the loader),
/// manifest, every fixture (with cross-match detection), per-template
/// fixture coverage and the Guard config export.
///
/// Pure: all inputs are file contents. [fixtures] maps
/// `<institution>/<case>.json` to its text.
LintReport lintRegistry({
  required String manifest,
  String? shared,
  required Map<String, String> institutions,
  required Map<String, String> fixtures,
  int minFixturesPerTemplate = defaultMinFixturesPerTemplate,
}) {
  final load = RegistryLoader.load(
    manifest: manifest,
    shared: shared,
    institutions: institutions,
  );
  final issues = [...load.issues];
  final registry = load.registry;
  if (registry == null) {
    return LintReport(
      issues: issues,
      fixturesRun: 0,
      fixturesPassed: 0,
      registry: null,
      guardConfigJson: null,
    );
  }
  var run = 0;
  var passed = 0;
  final covered = <String, int>{};
  final paths = fixtures.keys.toList()..sort();
  for (final path in paths) {
    run += 1;
    final outcome = runFixture(registry, path, fixtures[path]!);
    if (outcome.passed) {
      passed += 1;
      final id = outcome.templateId;
      if (id != null) {
        covered[id] = (covered[id] ?? 0) + 1;
      }
    } else {
      issues.addAll(outcome.issues);
    }
  }
  for (final inst in registry.institutions) {
    for (final t in inst.templates) {
      if ((covered[t.id] ?? 0) < minFixturesPerTemplate) {
        issues.add(
          RegistryIssue(
            'institutions/${inst.code}.json',
            RegistryIssueCode.fixtureCoverage,
            t.id,
          ),
        );
      }
    }
  }
  final guard = exportGuardConfig(registry);
  issues.addAll(guard.issues);
  return LintReport(
    issues: issues,
    fixturesRun: run,
    fixturesPassed: passed,
    registry: registry,
    guardConfigJson: guard.json,
  );
}
