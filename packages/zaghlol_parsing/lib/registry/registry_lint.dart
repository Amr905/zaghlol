import 'dart:convert';

import '../guard/capture_guard.dart';
import '../guard/guard_config.dart';
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
  final last4Checks = <(String, String, String, String)>[];
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
          final last4 = _fixtureExpectLast4(fixtures[path]!);
          final slash = path.indexOf('/');
          if (last4 != null && slash > 0) {
            last4Checks.add((path, path.substring(0, slash), body, last4));
          }
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
      if (_isSlowOnAdversarial(
        t.pattern.regex,
        samples[t.id],
        maxMatchMillis,
      )) {
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
  // These lists run on every message too (pipeline stage 0, last-4 borrowing,
  // the generic parser), so they get the same runtime probe (T-033 M-2).
  void probe(String file, String list, List<CompiledPattern> patterns) {
    for (var i = 0; i < patterns.length; i++) {
      if (_isSlowOnAdversarial(patterns[i].regex, null, maxMatchMillis)) {
        issues.add(
          RegistryIssue(
            file,
            RegistryIssueCode.slowMatch,
            '$list[$i] adversarial',
          ),
        );
      }
    }
  }

  for (final inst in registry.institutions) {
    probe('institutions/${inst.code}.json', 'drop', inst.drop);
    probe('institutions/${inst.code}.json', 'last4', inst.last4);
  }
  probe('shared.json', 'globalDrop', registry.shared.globalDrop);
  probe('shared.json', 'globalLast4', registry.shared.globalLast4);
  probe('shared.json', 'bodyHints', registry.shared.bodyHints);
  probe('shared.json', 'senderHints', registry.shared.senderHints);
  for (final inst in registry.institutions) {
    probe('institutions/${inst.code}.json', 'senders', [
      for (final s in inst.senders)
        if (s.regex != null) s.regex!,
    ]);
  }
  final guard = exportGuardConfig(registry);
  issues.addAll(guard.issues);
  // Last-4 parity (T-035 §10): the Guard's last-4 on every fixture whose
  // template yields a last-4 must equal it, or a card-level ignore rule
  // would miss natively.
  final guardJson = guard.json;
  if (guardJson != null) {
    final cfg = parseGuardConfig(utf8.encode(guardJson)).config;
    if (cfg == null) {
      issues.add(
        const RegistryIssue('guard.cfg', RegistryIssueCode.nonPortableRegex),
      );
    } else {
      for (final (path, inst, body, last4) in last4Checks) {
        if (guardLast4(cfg, inst, foldKey(body)) != last4) {
          issues.add(
            RegistryIssue(path, RegistryIssueCode.guardLast4Mismatch, 'last4'),
          );
        }
      }
    }
  }
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
///
/// The ladder ends at the pipeline's body cap (4000), so quadratic headroom
/// on a maximum-size message is measured, not assumed.
const List<int> adversarialBodyLengths = [64, 128, 256, 512, 1600, 4000];

/// The fixture's `expect.last4`, when it is a string.
String? _fixtureExpectLast4(String text) {
  try {
    final map = jsonDecode(text);
    final expect = map is Map<String, Object?> ? map['expect'] : null;
    final last4 = expect is Map<String, Object?> ? expect['last4'] : null;
    return last4 is String ? last4 : null;
  } on FormatException {
    return null;
  }
}

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
  // Runs of mask characters (`*`, `x`) stress last-4 patterns such as
  // `\*{2,}([0-9]{4})`, which are quadratic on them (T-035).
  final out = <String>[
    '1' * length,
    '\u0627 ' * (length ~/ 2),
    '*' * length,
    'x' * length,
  ];
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

bool _isSlowOnAdversarial(RegExp regex, String? sample, int limitMillis) {
  final clock = Stopwatch();
  int timeOnce(String folded) {
    clock
      ..reset()
      ..start();
    regex.firstMatch(folded);
    clock.stop();
    return clock.elapsedMicroseconds;
  }

  final limitMicros = limitMillis * 1000;
  for (final length in adversarialBodyLengths) {
    for (final body in adversarialBodies(sample, length)) {
      final folded = foldKey(body);
      var best = timeOnce(folded);
      // A scheduler stall on a loaded runner inflates one sample, so a
      // candidate is confirmed by taking the best of three runs. Only the
      // over-limit case pays for the repeats.
      for (var k = 0; k < 2 && best > limitMicros; k++) {
        final again = timeOnce(folded);
        if (again < best) best = again;
      }
      if (best > limitMicros) return true;
    }
  }
  return false;
}
