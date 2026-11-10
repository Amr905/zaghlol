import 'dart:convert';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

LintReport _lint(RegistryFiles f, {int min = 4}) => lintRegistry(
  manifest: f.manifest,
  shared: f.shared,
  institutions: f.institutions,
  fixtures: f.fixtures,
  minFixturesPerTemplate: min,
);

Set<RegistryIssueCode> _codes(LintReport r) =>
    r.issues.map((i) => i.code).toSet();

void main() {
  final base = RegistryFiles.load();

  test('table: every fixture in the test registry passes', () {
    final r = _lint(base);
    expect(r.issues, isEmpty, reason: r.issues.join('\n'));
    expect(r.fixturesRun, base.fixtures.length);
    expect(r.fixturesPassed, r.fixturesRun);
    expect(r.fixturesRun, greaterThanOrEqualTo(30));
  });

  test('each template has at least four passing fixtures', () {
    expect(_lint(base, min: 4).issues, isEmpty);
    expect(
      _codes(_lint(base, min: 6)),
      contains(RegistryIssueCode.fixtureCoverage),
    );
  });

  group('lint fails on an invalid regex', () {
    test('uncompilable pattern', () {
      final f = base.copy()
        ..editInstitution('nbe.json', (j) {
          ((j['templates']! as List<Object?>).first!
                  as Map<String, Object?>)['pattern'] =
              '(?<amount>\\d+';
        });
      final r = _lint(f);
      expect(r.ok, isFalse);
      expect(_codes(r), contains(RegistryIssueCode.badRegex));
    });

    test('catastrophic-backtracking pattern', () {
      final f = base.copy()
        ..editInstitution('cib.json', (j) {
          ((j['templates']! as List<Object?>).first!
                  as Map<String, Object?>)['pattern'] =
              '^cib: (?<amount>(\\d+)+)\$';
        });
      final r = _lint(f);
      expect(r.ok, isFalse);
      expect(_codes(r), contains(RegistryIssueCode.unsafeRegex));
    });
  });

  group('lint fails on a fixture regression', () {
    const path = 'nbe/card_purchase_ar_plain.json';

    test('wrong amount', () {
      final f = base.copy()
        ..editFixture(
          path,
          (j) => (j['expect']! as Map<String, Object?>)['amount'] = '451.00',
        );
      final r = _lint(f);
      expect(r.ok, isFalse);
      final hit = r.issues.firstWhere(
        (i) => i.code == RegistryIssueCode.fixtureFailed,
      );
      expect(hit.detail, 'amount');
      expect(hit.path, path);
    });

    test('template change that breaks the pattern', () {
      final f = base.copy()
        ..editInstitution('nbe.json', (j) {
          final t =
              (j['templates']! as List<Object?>).first! as Map<String, Object?>;
          t['pattern'] = (t['pattern']! as String).replaceFirst(
            'تم خصم',
            'تم سحب',
          );
        });
      final r = _lint(f);
      expect(r.ok, isFalse);
      expect(_codes(r), contains(RegistryIssueCode.fixtureFailed));
    });

    test('a field expected absent that is present', () {
      final f = base.copy()
        ..editFixture(
          path,
          (j) => (j['expect']! as Map<String, Object?>)['balance'] = null,
        );
      expect(_codes(_lint(f)), contains(RegistryIssueCode.fixtureFailed));
    });

    test('expected outcome mismatch', () {
      final f = base.copy()
        ..editFixture(
          'nbe/otp_is_dropped.json',
          (j) =>
              (j['expect']! as Map<String, Object?>)['outcome'] = 'unmatched',
        );
      expect(_codes(_lint(f)), contains(RegistryIssueCode.fixtureFailed));
    });

    test('sender resolves to another institution', () {
      final f = base.copy()..editFixture(path, (j) => j['sender'] = 'CIB');
      expect(_codes(_lint(f)), contains(RegistryIssueCode.fixtureFailed));
    });

    test('unexpected extraction problem', () {
      // Feb 30 is a date the template reads but the calendar rejects.
      final f = base.copy()
        ..editFixture(path, (j) {
          j['body'] = (j['body']! as String).replaceFirst('23/10', '30/02');
          final e = j['expect']! as Map<String, Object?>;
          e['date'] = null;
        });
      final r = _lint(f);
      expect(r.issues.where((i) => i.detail == 'problems'), isNotEmpty);
    });

    test('declared problems are accepted', () {
      final f = base.copy()
        ..editFixture(path, (j) {
          j['body'] = (j['body']! as String).replaceFirst('23/10', '30/02');
          final e = j['expect']! as Map<String, Object?>;
          e['date'] = null;
          e['problems'] = ['date'];
        });
      expect(_lint(f).issues.where((i) => i.path == path), isEmpty);
    });
  });

  group('fixture file validation', () {
    final edits = <(String, void Function(Map<String, Object?>))>[
      (
        'unknown expect key',
        (j) => (j['expect']! as Map<String, Object?>)['colour'] = 'x',
      ),
      ('unknown top key', (j) => j['note'] = 'x'),
      ('missing body', (j) => j.remove('body')),
      ('missing expect', (j) => j.remove('expect')),
      ('bad received at', (j) => j['receivedAt'] = 'yesterday'),
      ('bad channel', (j) => j['channel'] = 'fax'),
      ('sender and package', (j) => j['package'] = 'com.example.nbe'),
      (
        'non-string expect value',
        (j) => (j['expect']! as Map<String, Object?>)['amount'] = 450,
      ),
      ('body too long', (j) => j['body'] = 'x' * (maxFixtureBodyLength + 1)),
    ];
    for (final (name, edit) in edits) {
      test(name, () {
        final f = base.copy()
          ..editFixture('nbe/card_purchase_ar_plain.json', edit);
        expect(_lint(f).ok, isFalse);
      });
    }

    test('fixture in an unknown institution directory', () {
      final f = base.copy()..fixtures['zzz/a.json'] = '{}';
      expect(_codes(_lint(f)), contains(RegistryIssueCode.fixtureInvalid));
    });

    test('non-JSON fixture', () {
      final f = base.copy()..fixtures['nbe/a.json'] = 'not json';
      expect(_codes(_lint(f)), contains(RegistryIssueCode.invalidJson));
    });

    test('lint output never contains message text or amounts', () {
      final f = base.copy()
        ..editFixture('nbe/card_purchase_ar_plain.json', (j) {
          (j['expect']! as Map<String, Object?>)['amount'] = '999.99';
        });
      final out = _lint(f).issues.join('\n');
      expect(out, isNot(contains('999.99')));
      expect(out, isNot(contains('450.00')));
      expect(out, isNot(contains('CARREFOUR')));
    });
  });

  group('cross-match detection', () {
    test('a second template that also matches a fixture is reported', () {
      final f = base.copy()
        ..editInstitution('nbe.json', (j) {
          final ts = (j['templates']! as List<Object?>)
              .cast<Map<String, Object?>>();
          final dup = jsonDecode(jsonEncode(ts.first)) as Map<String, Object?>;
          dup['id'] = 'nbe.card_purchase_loose.ar';
          dup['pattern'] = 'تم خصم (?<amount>[\\d,.]+) (?<cur>جم)';
          dup['date'] = null;
          dup.remove('date');
          ts.add(dup);
        });
      final r = _lint(f);
      final hits = r.issues.where(
        (i) => i.code == RegistryIssueCode.crossMatch,
      );
      expect(hits, isNotEmpty);
      expect(hits.first.detail, contains('nbe.card_purchase.ar'));
      expect(hits.first.detail, contains('nbe.card_purchase_loose.ar'));
    });

    test('templates outside the fixture channel do not count', () {
      final f = base.copy()
        ..editInstitution('nbe.json', (j) {
          final ts = (j['templates']! as List<Object?>)
              .cast<Map<String, Object?>>();
          final dup = jsonDecode(jsonEncode(ts.first)) as Map<String, Object?>;
          dup['id'] = 'nbe.card_purchase.notification';
          dup['channel'] = ['notification'];
          ts.add(dup);
        });
      expect(_codes(_lint(f)), isNot(contains(RegistryIssueCode.crossMatch)));
    });
  });

  group('guard config export', () {
    final report = _lint(base);
    final json = jsonDecode(report.guardConfigJson!) as Map<String, Object?>;

    test('has the platform-channels §1.1 shape', () {
      expect(json.keys, [
        'v',
        'registryVersion',
        'senders',
        'packages',
        'shortcutKeywords',
        'drop',
        'last4',
        'generic',
      ]);
      expect(json['v'], 3);
      expect(json['registryVersion'], 3);
    });

    test('senders and packages carry the institution', () {
      final senders = (json['senders']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(senders.first, {'match': 'exact', 'value': 'CIB', 'inst': 'cib'});
      expect(
        senders.any((s) => s['match'] == 'regex' && s['inst'] == 'cib'),
        isTrue,
      );
      expect(json['packages'], [
        {'value': 'com.example.nbe', 'inst': 'nbe'},
      ]);
    });

    test('drop, last4 and generic hints come from shared and institutions', () {
      final drop = json['drop']! as Map<String, Object?>;
      expect((drop['global']! as List<Object?>), contains(r'(?i)\botp\b'));
      expect((drop['byInst']! as Map<String, Object?>).keys, ['nbe']);
      final last4 = json['last4']! as Map<String, Object?>;
      expect(last4.keys, ['nbe', '*']);
      expect((json['generic']! as Map<String, Object?>)['alwaysCapture'], [
        'BDC-ALERT',
      ]);
    });

    test('is deterministic and under the size cap', () {
      expect(_lint(base).guardConfigJson, report.guardConfigJson);
      expect(
        utf8.encode(report.guardConfigJson!).length,
        lessThan(maxGuardConfigBytes),
      );
    });

    test('every exported regex compiles in Dart', () {
      void check(Object? v) {
        if (v is String && (v.contains(r'\') || v.startsWith('(?'))) {
          expect(compilePattern(v), isNotNull, reason: v);
        } else if (v is List<Object?>) {
          v.forEach(check);
        } else if (v is Map<String, Object?>) {
          v.values.forEach(check);
        }
      }

      check(json['drop']);
      check(json['last4']);
      check(json['generic']);
    });

    test('over the size cap is an error and no config', () {
      final f = base.copy()
        ..shared = jsonEncode({
          'schema': 1,
          'shortcutKeywords': [for (var i = 0; i < 200; i++) 'k$i${'x' * 580}'],
          'generic': {
            'alwaysCapture': [for (var i = 0; i < 200; i++) 'a$i${'y' * 580}'],
          },
        });
      final r = _lint(f);
      expect(r.guardConfigJson, isNull);
      expect(_codes(r), contains(RegistryIssueCode.guardConfigTooLarge));
    });
  });

  group('per-message time budget', () {
    test('matching every fixture body 50 times stays far below 10 ms each', () {
      final reg = RegistryLoader.load(
        manifest: base.manifest,
        shared: base.shared,
        institutions: base.institutions,
      ).registry!;
      final bodies = [
        for (final raw in base.fixtures.values)
          foldBody(
            (jsonDecode(raw) as Map<String, Object?>)['body']! as String,
          ),
      ];
      final sw = Stopwatch()..start();
      var n = 0;
      for (var round = 0; round < 50; round++) {
        for (final b in bodies) {
          for (final i in reg.institutions) {
            for (final t in i.templates) {
              matchTemplate(t, b);
            }
          }
          n += 1;
        }
      }
      sw.stop();
      expect(sw.elapsedMilliseconds ~/ n, lessThan(10));
    });
  });
}
