import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

// T-161: OCR text through ParsingPipeline.parseOcr. The bundled registry's
// `ocr` fixtures (app/test/fixtures/sms/<institution>/ocr_*.json) must give
// the same template, amount, currency and counterparty through the pipeline
// as through the registry lint; receipt fixtures cover the generic reader.
const String _registryDir = '../../app/assets/registry';
const String _smsFixtures = '../../app/test/fixtures/sms';
const String _receiptFixtures = 'test/fixtures/ocr/receipt';

DateTime _received(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})')
      .firstMatch(iso)!;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime.utc(g(1), g(2), g(3), g(4), g(5));
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final institutions = <String, String>{};
  for (final f in Directory('$_registryDir/institutions').listSync()) {
    if (f is File) institutions[f.uri.pathSegments.last] = f.readAsStringSync();
  }
  final load = RegistryLoader.load(
    manifest: File('$_registryDir/registry_manifest.json').readAsStringSync(),
    shared: File('$_registryDir/shared.json').readAsStringSync(),
    institutions: institutions,
  );
  test('the bundled registry loads clean', () => expect(load.issues, isEmpty));
  final pipeline = ParsingPipeline(load.registry!);

  final ocrFixtures = <File>[
    for (final f in Directory(_smsFixtures).listSync(recursive: true))
      if (f is File &&
          f.path.endsWith('.json') &&
          f.uri.pathSegments.last.startsWith('ocr_'))
        f,
  ]..sort((a, b) => a.path.compareTo(b.path));

  test('OCR fixtures cover every template at least four times', () {
    expect(ocrFixtures.length, greaterThanOrEqualTo(32));
    final ocrTemplates = [
      for (final i in load.registry!.institutions)
        for (final t in i.templates)
          if (t.channels.contains(RegistryChannel.ocr)) t.id,
    ];
    expect(ocrTemplates.length, greaterThanOrEqualTo(8));
    final counts = <String, int>{};
    for (final f in ocrFixtures) {
      final e = (jsonDecode(f.readAsStringSync()) as Map)['expect'] as Map;
      counts.update(e['template'] as String, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final id in ocrTemplates) {
      expect(counts[id] ?? 0, greaterThanOrEqualTo(4), reason: id);
    }
  });

  for (final f in ocrFixtures) {
    test('ocr fixture ${f.uri.pathSegments.last}', () {
      final map = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      final e = map['expect'] as Map<String, Object?>;
      final r = pipeline.parseOcr(
        map['body'] as String,
        _received(map['receivedAt'] as String),
      );
      expect(r, isA<ParseParsed>());
      final p = r as ParseParsed;
      expect(p.templateId, e['template']);
      expect(p.fields.amount?.toCanonicalString(), e['amount']);
      expect(p.fields.amount?.currency.code, e['currency']);
      expect(p.direction.name, e['direction']);
      expect(p.fields.last4, e['last4']);
      expect(p.fields.ref, e['ref']);
      expect(
        p.fields.date == null ? null : _isoDate(p.fields.date!),
        e['date'],
      );
      if (e.containsKey('counterpartyKind')) {
        expect(p.fields.counterparty?.kind.name, e['counterpartyKind']);
      }
      expect(p.confidencePermille, greaterThan(0));
    });
  }

  final receipts =
      Directory(_receiptFixtures)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  test('receipt fixture count', () => expect(receipts.length, 9));
  for (final f in receipts) {
    test('receipt ${f.uri.pathSegments.last}', () {
      final map = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      final e = map['expect'] as Map<String, Object?>;
      final r = pipeline.parseOcr(
        map['body'] as String,
        _received(map['receivedAt'] as String),
      );
      if (e['unrecognized'] == true) {
        expect(r, isA<ParseUnrecognized>());
        return;
      }
      final p = r as ParseParsed;
      expect(p.institutionCode, 'ocr_receipt');
      expect(p.fields.amount?.toCanonicalString(), e['amount']);
      expect(p.fields.amount?.currency.code, e['currency']);
      expect(p.fields.merchant?.display, e['merchant']);
      expect(
        p.fields.date == null ? null : _isoDate(p.fields.date!),
        e['date'],
      );
      final t = p.fields.time;
      expect(
        t == null ? null : '${t.hour}:${t.minute.toString().padLeft(2, '0')}',
        e['time'],
      );
      expect(p.needsReview, isTrue, reason: 'never auto-accepted');
    });
  }

  group('total function', () {
    for (final body in <String>[
      '',
      '   \n  ',
      'hello world',
      'x' * 5000,
      '\u0000‮ total ' * 50,
      'Total ' * 400,
    ]) {
      test('never throws (${body.length} chars)', () {
        final r = pipeline.parseOcr(body, DateTime.utc(2026, 10, 23));
        expect(r, isA<ParseResult>());
      });
    }

    test('adversarial text stays fast', () {
      final text = '${'transfer successful egp 1 ' * 100}to:' * 3;
      final w = Stopwatch()..start();
      pipeline.parseOcr(text, DateTime.utc(2026, 10, 23));
      expect(w.elapsedMilliseconds, lessThan(200));
    });
  });
}
