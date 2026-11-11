import 'dart:convert';

import '../normalize/text_normalizer.dart';
import 'fixture_runner.dart';
import 'guard_export.dart';
import 'registry_issue.dart';
import 'registry_loader.dart';
import 'registry_models.dart';

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
  int maxMatchMillis = defaultMaxMatchMillis,
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
  final samples = <String, String>{};
  final paths = fixtures.keys.toList()..sort();
  for (final path in paths) {
    run += 1;
    final outcome = runFixture(
      registry,
      path,
      fixtures[path]!,
      maxMatchMillis: maxMatchMillis,
    );
    if (outcome.passed) {
      passed += 1;
      final id = outcome.templateId;
      if (id != null) {
        covered[id] = (covered[id] ?? 0) + 1;
        final body = _fixtureBody(fixtures[path]!);
        if (body != null) {
          samples.putIfAbsent(id, () => body);
        }
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
  for (final inst in registry.institutions) {
    for (final t in inst.templates) {
      if (_isSlowOnAdversarial(t, samples[t.id], maxMatchMillis)) {
        issues.add(
          RegistryIssue(
            'institutions/${inst.code}.json',
            RegistryIssueCode.slowMatch,
            '${t.id} adversarial',
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

/// Lengths of the adversarial bodies, smallest first. A long concatenated
/// SMS is under 1600 characters; the lint stops at the first length that is
/// over the limit, so a high-degree polynomial pattern is caught at a small
/// size instead of hanging the lint at the largest.
const List<int> adversarialBodyLengths = [64, 128, 256, 512];

String? _fixtureBody(String text) {
  try {
    final map = jsonDecode(text);
    final body = map is Map<String, Object?> ? map['body'] : null;
    return body is String ? body : null;
  } on FormatException {
    return null;
  }
}

/// Bodies of [length] built to stress a template: digits only, Arabic words
/// only, and the template's own fixture body repeated (so its literals
/// recur).
List<String> adversarialBodies(String? sample, int length) {
  final out = <String>['1' * length, '\u0627 ' * (length ~/ 2)];
  if (sample != null && sample.isNotEmpty) {
    final b = StringBuffer();
    while (b.length < length) {
      b
        ..write(sample)
        ..write(' ');
    }
    out.add(b.toString().substring(0, length));
  }
  return out;
}

bool _isSlowOnAdversarial(Template t, String? sample, int limitMillis) {
  final clock = Stopwatch();
  for (final length in adversarialBodyLengths) {
    for (final body in adversarialBodies(sample, length)) {
      final folded = foldKey(body);
      clock
        ..reset()
        ..start();
      t.pattern.regex.firstMatch(folded);
      clock.stop();
      if (clock.elapsedMilliseconds > limitMillis) {
        return true;
      }
    }
  }
  return false;
}
