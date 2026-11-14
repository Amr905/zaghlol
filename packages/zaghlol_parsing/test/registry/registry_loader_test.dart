import 'dart:convert';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

RegistryLoadResult _load(RegistryFiles f) => RegistryLoader.load(
  manifest: f.manifest,
  shared: f.shared,
  institutions: f.institutions,
);

Set<RegistryIssueCode> _codes(RegistryLoadResult r) =>
    r.issues.map((i) => i.code).toSet();

void main() {
  final base = RegistryFiles.load();

  test('the test bundle loads clean', () {
    final r = _load(base);
    expect(r.issues, isEmpty);
    final reg = r.registry!;
    expect(reg.registryVersion, 3);
    expect(reg.institutions.map((i) => i.code), ['cib', 'nbe']);
    expect(reg.byCode('nbe')!.templates, hasLength(4));
    expect(reg.byCode('nope'), isNull);
  });

  test('base confidence is stored as thousandths', () {
    final t = _load(base).registry!.byCode('nbe')!.templates.first;
    expect(t.baseConfidencePermille, 980);
  });

  test('manifest text matches the registry (canonical form)', () {
    final reg = _load(base).registry!;
    expect(jsonDecode(reg.manifestJson()), jsonDecode(base.manifest));
  });

  group('sender resolution', () {
    final reg = _load(base).registry!;
    final cases = <(String, RegistryChannel, String?)>[
      ('NBE', RegistryChannel.sms, 'nbe'),
      ('nbe', RegistryChannel.sms, 'nbe'),
      (' AlAhly ', RegistryChannel.sms, 'nbe'),
      ('CIB-EGY', RegistryChannel.sms, 'cib'),
      ('CIB-XYZ', RegistryChannel.sms, null),
      ('com.example.nbe', RegistryChannel.notification, 'nbe'),
      ('NBE', RegistryChannel.notification, null),
      ('', RegistryChannel.sms, null),
    ];
    for (final (source, channel, code) in cases) {
      test('$source on ${channel.wire}', () {
        expect(reg.resolveSource(source, channel)?.code, code);
      });
    }
  });

  group('schema rejects', () {
    final edits =
        <
          (
            String,
            String,
            void Function(Map<String, Object?>),
            RegistryIssueCode,
          )
        >[
          (
            'unknown top key',
            'nbe.json',
            (j) => j['extra'] = 1,
            RegistryIssueCode.unknownKey,
          ),
          (
            'code differs from file',
            'nbe.json',
            (j) => j['code'] = 'nbx',
            RegistryIssueCode.badValue,
          ),
          (
            'missing names',
            'nbe.json',
            (j) => j.remove('names'),
            RegistryIssueCode.missingKey,
          ),
          (
            'unknown currency',
            'nbe.json',
            (j) => j['defaultCurrency'] = 'XXQ',
            RegistryIssueCode.badValue,
          ),
          (
            'senders wrong type',
            'nbe.json',
            (j) => j['senders'] = 'NBE',
            RegistryIssueCode.wrongType,
          ),
          (
            'bad sender match',
            'nbe.json',
            (j) => j['senders'] = [
              {'match': 'prefix', 'value': 'N'},
            ],
            RegistryIssueCode.badValue,
          ),
          (
            'bad drop regex',
            'nbe.json',
            (j) => j['drop'] = ['a('],
            RegistryIssueCode.badRegex,
          ),
          (
            'unsafe drop regex',
            'nbe.json',
            (j) => j['drop'] = ['(a+)+b'],
            RegistryIssueCode.unsafeRegex,
          ),
          (
            'no templates',
            'nbe.json',
            (j) => j['templates'] = <Object?>[],
            RegistryIssueCode.badValue,
          ),
          (
            'template not object',
            'nbe.json',
            (j) => j['templates'] = [1],
            RegistryIssueCode.wrongType,
          ),
          (
            'template bad lang',
            'nbe.json',
            (j) => _tpl(j)['lang'] = 'fr',
            RegistryIssueCode.badValue,
          ),
          (
            'template bad event',
            'nbe.json',
            (j) => _tpl(j)['event'] = 'shopping',
            RegistryIssueCode.badValue,
          ),
          (
            'template bad direction',
            'nbe.json',
            (j) => _tpl(j)['direction'] = 'sideways',
            RegistryIssueCode.badValue,
          ),
          (
            'template bad channel',
            'nbe.json',
            (j) => _tpl(j)['channel'] = ['fax'],
            RegistryIssueCode.badValue,
          ),
          (
            'confidence above one',
            'nbe.json',
            (j) => _tpl(j)['baseConfidence'] = 1.5,
            RegistryIssueCode.badValue,
          ),
          (
            'confidence as string',
            'nbe.json',
            (j) => _tpl(j)['baseConfidence'] = '0.9',
            RegistryIssueCode.wrongType,
          ),
          (
            'confidence four decimals',
            'nbe.json',
            (j) => _tpl(j)['baseConfidence'] = 0.9801,
            RegistryIssueCode.badValue,
          ),
          (
            'version zero',
            'nbe.json',
            (j) => _tpl(j)['version'] = 0,
            RegistryIssueCode.badValue,
          ),
          (
            'bad id shape',
            'nbe.json',
            (j) => _tpl(j)['id'] = 'Nbe',
            RegistryIssueCode.badValue,
          ),
          (
            'template unknown key',
            'nbe.json',
            (j) => _tpl(j)['colour'] = 'red',
            RegistryIssueCode.unknownKey,
          ),
          (
            'pattern bad regex',
            'nbe.json',
            (j) => _tpl(j)['pattern'] = '(?<amount>\\d+',
            RegistryIssueCode.badRegex,
          ),
          (
            'pattern unsafe',
            'nbe.json',
            (j) => _tpl(j)['pattern'] = '(?<amount>(\\d+)+)x',
            RegistryIssueCode.unsafeRegex,
          ),
          (
            'pattern without amount',
            'nbe.json',
            (j) => _tpl(j)['pattern'] = 'تم خصم (?<last4>\\d{4})',
            RegistryIssueCode.missingGroup,
          ),
          (
            'pattern unknown group',
            'nbe.json',
            (j) => _tpl(j)['pattern'] = '(?<amount>\\d+) (?<colour>x)',
            RegistryIssueCode.unknownGroup,
          ),
          (
            'currency map unknown code',
            'nbe.json',
            (j) => _tpl(j)['currencyMap'] = {'جم': 'ZZZ'},
            RegistryIssueCode.badValue,
          ),
          (
            'date format garbage',
            'nbe.json',
            (j) => _tpl(j)['date'] = {'format': 'q/q'},
            RegistryIssueCode.badValue,
          ),
          (
            'date without date group',
            'nbe.json',
            (j) => _tpl(j)['pattern'] = '(?<amount>\\d+) x',
            RegistryIssueCode.missingGroup,
          ),
          (
            'bad locale',
            'nbe.json',
            (j) => _tpl(j)['locale'] = 'fr',
            RegistryIssueCode.badValue,
          ),
          (
            'duplicate template id',
            'nbe.json',
            (j) => _tpls(j)[1]['id'] = _tpls(j)[0]['id'],
            RegistryIssueCode.duplicateId,
          ),
        ];
    for (final (name, file, edit, code) in edits) {
      test(name, () {
        final f = base.copy()..editInstitution(file, edit);
        final r = _load(f);
        expect(
          r.registry,
          isNull,
          reason: 'a registry with issues is never returned',
        );
        expect(_codes(r), contains(code));
      });
    }

    test('duplicate exact sender across institutions', () {
      final f = base.copy()
        ..editInstitution(
          'cib.json',
          (j) => j['senders'] = [
            {'match': 'exact', 'value': 'nbe'},
          ],
        );
      expect(_codes(_load(f)), contains(RegistryIssueCode.duplicateSender));
    });

    test('manifest version differs from the max template version', () {
      final f = base.copy()
        ..manifest = jsonEncode({
          'schema': 1,
          'registryVersion': 9,
          'institutions': ['cib', 'nbe'],
        });
      expect(_codes(_load(f)), contains(RegistryIssueCode.manifestMismatch));
    });

    test('manifest lists a different institution set', () {
      final f = base.copy()
        ..manifest = jsonEncode({
          'schema': 1,
          'registryVersion': 3,
          'institutions': ['nbe'],
        });
      expect(_codes(_load(f)), contains(RegistryIssueCode.manifestMismatch));
    });

    test('shared.json with an unknown key or bad regex', () {
      final f = base.copy()..shared = jsonEncode({'schema': 1, 'oops': 1});
      expect(_codes(_load(f)), contains(RegistryIssueCode.unknownKey));
      f.shared = jsonEncode({
        'schema': 1,
        'drop': {
          'global': ['a('],
        },
      });
      expect(_codes(_load(f)), contains(RegistryIssueCode.badRegex));
    });

    test('invalid JSON and wrong top-level type', () {
      final f = base.copy()..institutions['nbe.json'] = '{not json';
      expect(_codes(_load(f)), contains(RegistryIssueCode.invalidJson));
      f.institutions['nbe.json'] = '[]';
      expect(_codes(_load(f)), contains(RegistryIssueCode.notAnObject));
    });

    test('oversized file', () {
      final f = base.copy()
        ..institutions['nbe.json'] = ' ' * (maxRegistryFileBytes + 1);
      expect(_codes(_load(f)), contains(RegistryIssueCode.tooLarge));
    });

    test('non-json file name', () {
      final f = base.copy()..institutions['readme.txt'] = 'x';
      expect(_codes(_load(f)), contains(RegistryIssueCode.badValue));
    });
  });

  test('issues never contain the offending text', () {
    const secret = 'SECRET-SENTINEL-9911'; // hyphens: not an identifier
    final f = base.copy()
      ..editInstitution('nbe.json', (j) {
        j['extra$secret'] = 1;
        _tpl(j)['pattern'] = '($secret+)+';
        _tpl(j)['lang'] = secret;
      });
    final r = _load(f);
    expect(r.issues, isNotEmpty);
    for (final i in r.issues) {
      expect(i.toString().contains(secret), isFalse, reason: i.code.name);
    }
  });

  test('garbage input never throws', () {
    const junk = [
      '',
      '{}',
      '[]',
      'null',
      '"x"',
      '{"code":1}',
      '\u0000',
      '{"templates":{}}',
    ];
    for (final a in junk) {
      for (final b in junk) {
        final r = RegistryLoader.load(
          manifest: a,
          shared: b,
          institutions: {'nbe.json': a, 'x.json': b},
        );
        expect(r.registry, isNull);
      }
    }
  });

  test('registry with 80 institutions loads in under 150 ms', () {
    final template =
        jsonDecode(base.institutions['cib.json']!) as Map<String, Object?>;
    final nbe =
        jsonDecode(base.institutions['nbe.json']!) as Map<String, Object?>;
    final files = <String, String>{};
    final codes = <String>[];
    for (var i = 0; i < 80; i++) {
      final code = 'bank${i.toString().padLeft(2, '0')}';
      final src = (i.isEven ? template : nbe);
      final j = jsonDecode(jsonEncode(src)) as Map<String, Object?>;
      j['code'] = code;
      j['senders'] = [
        {'match': 'exact', 'value': 'SND$i'},
      ];
      j['packages'] = <Object?>[];
      final ts = (j['templates']! as List<Object?>)
          .cast<Map<String, Object?>>();
      for (var k = 0; k < ts.length; k++) {
        ts[k]['id'] = '$code.t$k.en';
      }
      files['$code.json'] = jsonEncode(j);
      codes.add(code);
    }
    final manifest = jsonEncode({
      'schema': 1,
      'registryVersion': 3,
      'institutions': codes,
    });
    final sw = Stopwatch();
    var best = 1 << 30;
    var first = 0;
    for (var run = 0; run < 3; run++) {
      sw
        ..reset()
        ..start();
      final r = RegistryLoader.load(
        manifest: manifest,
        shared: base.shared,
        institutions: files,
      );
      sw.stop();
      expect(r.issues, isEmpty);
      expect(r.registry!.institutions, hasLength(80));
      if (run == 0) {
        first = sw.elapsedMilliseconds;
      }
      best = sw.elapsedMilliseconds < best ? sw.elapsedMilliseconds : best;
    }
    // The cold (JIT) first load is what a device sees, so it is held to the
    // acceptance budget itself (150 ms); best-of-3 is the stable check.
    expect(first, lessThan(150), reason: 'cold first load $first ms');
    expect(best, lessThan(150));
  }, tags: 'benchmark');
}

Map<String, Object?> _tpl(Map<String, Object?> j) => _tpls(j).first;

List<Map<String, Object?>> _tpls(Map<String, Object?> j) =>
    (j['templates']! as List<Object?>).cast<Map<String, Object?>>();
