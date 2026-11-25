// T-260: scan outcomes for till receipts and the dev-build counters.
// Synthetic text only.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/ocr_port.dart';
import 'package:zaghlol/features/capture/application/scan_diagnostics.dart';
import 'package:zaghlol/features/capture/application/scan_service.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final class _Ocr implements OcrEngine {
  _Ocr(this.text, {this.fail});
  final String text;
  final OcrFailureCode? fail;

  @override
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  }) async {
    if (fail != null) throw OcrException(fail!);
    return OcrOutcome([
      for (final l in text.split('\n'))
        OcrTextLine(text: l, confidence: 0.9, x: 0, y: 0, width: 1, height: 1),
    ]);
  }

  @override
  Future<String> sealImage(String plainImagePath) async => plainImagePath;

  @override
  Future<List<String>> supportedLanguages() async => const ['ar', 'en'];
}

Registry _registry() {
  const dir = 'assets/registry';
  final institutions = <String, String>{};
  for (final f in Directory('$dir/institutions').listSync()) {
    if (f is File) institutions[f.uri.pathSegments.last] = f.readAsStringSync();
  }
  return RegistryLoader.load(
    manifest: File('$dir/registry_manifest.json').readAsStringSync(),
    shared: File('$dir/shared.json').readAsStringSync(),
    institutions: institutions,
  ).registry!;
}

void main() {
  late ScanDiagnostics diag;
  late ParsingPipeline pipeline;
  setUp(() {
    diag = ScanDiagnostics();
    pipeline = ParsingPipeline(_registry());
  });

  ScanService service(_Ocr ocr) => ScanService(
    engine: ocr,
    pipeline: pipeline,
    wallClock: () => DateTime.utc(2026, 10, 23, 18),
    diagnostics: diag,
  );

  final cases =
      <(String, String, Object, Map<ScanCounter, int>, {String? merchant})>[
        (
          'amount before the label',
          'Sample Pharmacy\nPanadol 24.50\n156.75 EGP Total\n23/10/2026',
          '156.75',
          {ScanCounter.foundLabel: 1},
          merchant: 'Sample Pharmacy',
        ),
        (
          'no label, two amounts: last-resort guess',
          'Sample Pharmacy\nPanadol 24.50\nCough Syrup 62.00',
          '62.00',
          {ScanCounter.foundFallback: 1},
          merchant: 'Sample Pharmacy',
        ),
        (
          'text but no total',
          'Sample Pharmacy\nThank you for visiting\n23/10/2026',
          ScanNoTotal,
          {ScanCounter.noTotal: 1},
          merchant: 'Sample Pharmacy',
        ),
        (
          'almost no text',
          '...\n--',
          ScanNoText,
          {ScanCounter.noText: 1},
          merchant: null,
        ),
      ];
  for (final c in cases) {
    test(c.$1, () async {
      final out = await service(_Ocr(c.$2)).scanImage('/p');
      if (c.$3 is String) {
        final found = out as ScanFound;
        expect(found.draft.amount.toCanonicalString(), c.$3);
        expect(found.draft.party, c.merchant);
      } else if (c.$3 == ScanNoTotal) {
        final n = out as ScanNoTotal;
        expect(n.merchant, c.merchant);
        expect(n.date, isNotNull);
      } else {
        expect(out, isA<ScanNoText>());
      }
      for (final k in ScanCounter.values) {
        expect(diag.count(k), c.$4[k] ?? 0, reason: k.name);
      }
    });
  }

  test('an OCR failure is counted, with a code only', () async {
    final out = await service(_Ocr('', fail: OcrFailureCode.ocrFailed))
        .scanImage('/p');
    expect(out, isA<ScanFailed>());
    expect(diag.count(ScanCounter.ocrFailed), 1);
    expect(diag.snapshot.keys, contains('found_fallback'));
  });
}
