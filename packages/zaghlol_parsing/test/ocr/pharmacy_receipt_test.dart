import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// T-260: till-receipt layouts (pharmacy first) through ParsingPipeline.parseOcr.
// Synthetic text only; generic names. Each fixture gives the expected amount
// or the expected "no total" outcome (plus the hints that prefill manual entry).
const String _registryDir = '../../app/assets/registry';
const String _dir = 'test/ocr/pharmacy';

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
  final pipeline = ParsingPipeline(load.registry!);
  final now = DateTime.utc(2026, 10, 23, 18);

  final files =
      Directory(_dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('fixture count', () => expect(files.length, greaterThanOrEqualTo(10)));

  for (final f in files) {
    test(f.uri.pathSegments.last, () {
      final map = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      final e = map['expect'] as Map<String, Object?>;
      final body = map['body'] as String;
      final r = pipeline.parseOcr(body, now);
      if (e['unrecognized'] == true) {
        expect(r, isA<ParseUnrecognized>());
        final hints = pipeline.readOcrHints(body);
        expect(hints.merchant?.display, e['hintMerchant']);
        expect(
          hints.date == null ? null : _isoDate(hints.date!),
          e['hintDate'],
        );
        return;
      }
      final p = r as ParseParsed;
      expect(p.fields.amount?.toCanonicalString(), e['amount']);
      expect(p.fields.amount?.currency.code, e['currency']);
      expect(p.templateId, e['template']);
      expect(p.fields.merchant?.display, e['merchant']);
      expect(
        p.fields.date == null ? null : _isoDate(p.fields.date!),
        e['date'],
      );
      if (e['confidence'] != null) {
        expect(p.confidencePermille, e['confidence']);
      }
      expect(p.needsReview, isTrue);
    });
  }

  test('bank screens still win over the generic reader', () {
    // Covered by ocr_parse_test.dart (every ocr_* fixture); a receipt-shaped
    // text with no template keywords must not start matching a template.
    final r = pipeline.parseOcr('Total 12.00 EGP', now);
    expect((r as ParseParsed).institutionCode, 'ocr_receipt');
  });

  test('adversarial receipt text stays fast and total', () {
    final w = Stopwatch()..start();
    pipeline.parseOcr('${'Total 1.00 EGP\n' * 2000}Net\n' * 3, now);
    pipeline.parseOcr('Total\n' * 3000, now);
    pipeline.parseOcr('الاجمالي ' * 800, now);
    expect(w.elapsedMilliseconds, lessThan(2000));
  });
}
