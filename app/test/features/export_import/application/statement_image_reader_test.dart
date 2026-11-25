// T-269: photos of a statement. The OCR engine is a fake; images are
// synthetic bytes.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/ocr_port.dart';
import 'package:zaghlol/features/export_import/application/statement_image_reader.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'scanned_statement_test.dart' show FakeOcr, page1;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('t269_'));
  tearDown(() => dir.deleteSync(recursive: true));

  OcrStatementImageReader make(FakeOcr ocr) =>
      OcrStatementImageReader(ocr: ocr, tempDirectory: () async => dir);

  test(
    'reads each image as a page, deletes the temp files, zeroes bytes',
    () async {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5, 6]);
      final ocr = FakeOcr([page1(), page1()]);
      final out = await make(ocr).read([a, b]);
      expect(ocr.calls, 2);
      expect(out.map((f) => f.page).toSet(), {1, 2});
      expect(dir.listSync(), isEmpty);
      expect(a, [0, 0, 0]);
      expect(b, [0, 0, 0]);
    },
  );

  test('sealing fails (no OCR host): noText, nothing left behind', () async {
    final ocr = FakeOcr([page1()])
      ..failSeal = const OcrException(OcrFailureCode.notAvailable);
    await expectLater(
      make(ocr).read([
        Uint8List.fromList([1]),
      ]),
      throwsA(
        isA<PdfExtractException>().having(
          (e) => e.kind,
          'kind',
          PdfExtractFailureKind.noText,
        ),
      ),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('a page with no lines is noText', () async {
    final ocr = FakeOcr([const OcrOutcome([])]);
    await expectLater(
      make(ocr).read([
        Uint8List.fromList([1]),
      ]),
      throwsA(isA<PdfExtractException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test(
    'no images, too many images and an empty image are unreadable',
    () async {
      final ocr = FakeOcr([page1()]);
      final r = make(ocr);
      for (final bad in [
        <Uint8List>[],
        [for (var i = 0; i < statementImageMaxCount + 1; i++) Uint8List(1)],
        [Uint8List(0)],
      ]) {
        await expectLater(
          r.read(bad),
          throwsA(
            isA<PdfExtractException>().having(
              (e) => e.kind,
              'kind',
              PdfExtractFailureKind.unreadable,
            ),
          ),
        );
      }
      expect(ocr.calls, 0);
    },
  );
}
