// T-156b: scanned statement import. The PDF renderer and the OCR engine are
// fakes (PDFium and the OCR hosts need a device); the bank layout is
// synthetic.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/ocr_port.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/export_import/application/scanned_pdf_text_extractor.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'import_csv_test.dart' show FakeStore;

const double pw = 850;
const double ph = 1100;

OcrTextLine line(String s, double x0, double x1, double y) => OcrTextLine(
  text: s,
  confidence: 0.9,
  x: x0 / pw,
  y: (y - 5.5) / ph,
  width: (x1 - x0) / pw,
  height: 11 / ph,
);

/// (date, description, debit, credit, balance)
const rows = [
  ('10/02', 'POS PURCHASE', '4.23', '', '65.73'),
  ('10/03', 'PREAUTHORIZED CREDIT', '', '763.01', '828.74'),
  ('10/04', 'POS PURCHASE', '11.68', '', '817.06'),
  ('10/30', 'CHECK 1239', '451.20', '', '365.86'),
  ('11/09', 'INTEREST CREDIT', '', '.26', '366.12'),
];

OcrOutcome page1() {
  final l = <OcrTextLine>[
    line('Statement of Account', 77, 282, 84),
    line('Beginning balance on October 10', 127, 313, 532),
    line(r'$69.96', 395, 430, 532),
    line('Date', 89, 113, 776),
    line('Description', 127, 182, 776),
    line('Debit', 465, 490, 776),
    line('Credit', 589, 619, 776),
    line('Balance', 702, 742, 776),
  ];
  var y = 790.0;
  for (final r in rows) {
    l.add(line('${r.$1} ${r.$2}', 89, 127 + r.$2.length * 5.6, y));
    if (r.$3.isNotEmpty) l.add(line(r.$3, 491 - r.$3.length * 5.2, 491, y));
    if (r.$4.isNotEmpty) l.add(line(r.$4, 619 - r.$4.length * 5.2, 619, y));
    l.add(line(r.$5, 742 - r.$5.length * 5.2, 742, y));
    y += 13.3;
  }
  return OcrOutcome(l);
}

/// Page 2 repeats the credits by type (no balance column).
OcrOutcome page2() => OcrOutcome([
  line('Deposits and Other Credits', 89, 232, 180),
  line('Date', 89, 113, 196),
  line('Description', 127, 182, 196),
  line('Amount', 702, 740, 196),
  line('10/03 PREAUTHORIZED CREDIT', 89, 253, 209),
  line('763.01', 702, 740, 209),
  line('11/09 INTEREST CREDIT', 89, 200, 222),
  line('0.26', 718, 740, 222),
]);

class FakeSession implements PdfRasterSession {
  FakeSession(this.dir, this.pages, this.log);
  final Directory dir;
  final int pages;
  final List<String> log;
  @override
  int get pageCount => pages;
  @override
  Future<RenderedPdfPage> render(int page) async {
    log.add('render $page');
    final f = File('${dir.path}/page_$page.png')..writeAsBytesSync([1, 2, 3]);
    return RenderedPdfPage(path: f.path, heightPoints: ph.round());
  }

  @override
  Future<void> close() async => log.add('close');
}

class FakeRasterizer implements PdfPageRasterizer {
  FakeRasterizer(this.dir, {this.pages = 2});
  final Directory dir;
  final int pages;
  final List<String> log = [];
  Object? failOpen;
  @override
  Future<PdfRasterSession> open(Uint8List bytes, {String? password}) async {
    if (failOpen != null) throw failOpen!;
    log.add('open');
    return FakeSession(dir, pages, log);
  }
}

class FakeOcr implements OcrEngine {
  FakeOcr(this.outcomes);
  final List<OcrOutcome> outcomes;
  int calls = 0;
  OcrException? failSeal;
  OcrException? failRecognize;
  final List<List<String>> languagesSeen = [];

  @override
  Future<String> sealImage(String plainImagePath) async {
    if (failSeal != null) throw failSeal!;
    // The host moves the plain file into the spool.
    final f = File(plainImagePath);
    if (f.existsSync()) f.deleteSync();
    return 'spool/${calls + 1}';
  }

  @override
  Future<OcrOutcome> recognize(
    String encryptedImagePath, {
    List<String> languages = const ['ar', 'en'],
  }) async {
    languagesSeen.add(languages);
    if (failRecognize != null) throw failRecognize!;
    final o = outcomes[calls < outcomes.length ? calls : outcomes.length - 1];
    calls++;
    return o;
  }

  @override
  Future<List<String>> supportedLanguages() async => ['en'];
}

class FakeTextLayer implements PdfTextExtractor {
  FakeTextLayer({this.error, this.fragments = const []});
  final PdfExtractException? error;
  final List<PdfTextFragment> fragments;
  int calls = 0;
  @override
  Future<List<PdfTextFragment>> extract(
    Uint8List bytes, {
    String? password,
  }) async {
    calls++;
    if (error != null) throw error!;
    return fragments;
  }
}

class MemTemplates implements StatementTemplateStore {
  @override
  Future<StatementTemplate?> load(String k) async => null;
  @override
  Future<void> save(StatementTemplate t) async {}
}

final usd = Currency.of('USD');
Uint8List pdfBytes() => Uint8List.fromList(List.filled(64, 7));

void main() {
  late Directory tmp;
  late FakeRasterizer raster;
  late FakeOcr ocr;
  late FakeStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('zscan');
    raster = FakeRasterizer(tmp);
    ocr = FakeOcr([page1(), page2()]);
    store = FakeStore();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ScannedPdfTextExtractor extractor({PdfTextExtractor? text, int? maxPages}) =>
      ScannedPdfTextExtractor(
        textLayer:
            text ??
            FakeTextLayer(
              error: PdfExtractException(PdfExtractFailureKind.noText),
            ),
        rasterizer: raster,
        ocr: ocr,
        maxPages: maxPages ?? scannedPdfMaxPages,
      );

  int leftovers() => tmp.listSync().length;

  test('a scan is read by OCR and imported once, with exact money', () async {
    final uc = ImportStatementPdfUseCase(
      extractor(),
      store,
      MemTemplates(),
      now: () => DateTime(2026, 11, 18),
    );
    final reading = await uc.open(pdfBytes(), bankKey: 'scan');
    expect(reading.needsMapping, isFalse);
    expect(reading.table.openingBalance, r'$69.96');
    final s = await uc.run(
      reading,
      StatementMapping(
        roles: reading.table.suggestedRoles,
        currency: usd,
        dayFirst: reading.table.dayFirst,
      ),
      accountId: 'a1',
    );
    // Page 2 lists two of the same credits: they are not imported twice.
    expect(s.imported, 5);
    expect(s.invalid, 0);
    expect(store.rows.map((r) => r.source).toSet(), {TxnSource.pdf});
    expect(store.rows.map((r) => r.amount.minor).toList(), [
      423,
      76301,
      1168,
      45120,
      26,
    ]);
    expect(store.rows[1].direction, TxnDirection.income);
    expect(store.rows[0].direction, TxnDirection.expense);
    expect(store.rows.every((r) => r.amount.currency == usd), isTrue);
    expect(s.earliest, DateTime(2026, 10, 2, 12));
    expect(s.latest, DateTime(2026, 11, 9, 12));
    expect(ocr.calls, 2);
    expect(ocr.languagesSeen.first, ['ar', 'en']);
  });

  test('rendered images are gone after success', () async {
    await extractor().extract(pdfBytes());
    expect(leftovers(), 0);
    expect(raster.log, ['open', 'render 1', 'render 2', 'close']);
  });

  test(
    'rendered images are gone after an OCR failure, session closed',
    () async {
      ocr.failRecognize = const OcrException(OcrFailureCode.ocrFailed);
      await expectLater(
        extractor().extract(pdfBytes()),
        throwsA(
          isA<PdfExtractException>().having(
            (e) => e.kind,
            'kind',
            PdfExtractFailureKind.noText,
          ),
        ),
      );
      expect(leftovers(), 0);
      expect(raster.log.last, 'close');
    },
  );

  test('rendered images are gone when sealing fails (no OCR host)', () async {
    ocr.failSeal = const OcrException(OcrFailureCode.notAvailable);
    final uc = ImportStatementPdfUseCase(extractor(), store, MemTemplates());
    await expectLater(
      uc.open(pdfBytes(), bankKey: 'scan'),
      throwsA(
        isA<StatementImportException>().having(
          (e) => e.kind,
          'kind',
          StatementImportFailure.noText,
        ),
      ),
    );
    expect(leftovers(), 0);
  });

  test('a text PDF never touches the rasterizer or OCR', () async {
    final text = FakeTextLayer(
      fragments: [PdfTextFragment(page: 1, text: 'x', x0: 1, x1: 2, y: 3)],
    );
    final r = await extractor(text: text).extract(pdfBytes());
    expect(r, hasLength(1));
    expect(raster.log, isEmpty);
    expect(ocr.calls, 0);
  });

  test('a password problem is not mistaken for a scan', () async {
    for (final kind in [
      PdfExtractFailureKind.passwordRequired,
      PdfExtractFailureKind.wrongPassword,
      PdfExtractFailureKind.unreadable,
    ]) {
      final x = extractor(
        text: FakeTextLayer(error: PdfExtractException(kind)),
      );
      await expectLater(
        x.extract(pdfBytes()),
        throwsA(isA<PdfExtractException>().having((e) => e.kind, 'k', kind)),
      );
    }
    expect(raster.log, isEmpty);
    expect(ocr.calls, 0);
  });

  test('page cap: a long scan reads only the first pages', () async {
    raster = FakeRasterizer(tmp, pages: 100);
    await extractor(maxPages: 3).extract(pdfBytes());
    expect(raster.log.where((e) => e.startsWith('render')).length, 3);
  });

  test('a scan with nothing recognised is noText', () async {
    ocr = FakeOcr([const OcrOutcome([])]);
    await expectLater(
      extractor().extract(pdfBytes()),
      throwsA(
        isA<PdfExtractException>().having(
          (e) => e.kind,
          'kind',
          PdfExtractFailureKind.noText,
        ),
      ),
    );
    expect(leftovers(), 0);
  });

  test('rasterizer open errors are typed', () async {
    raster.failOpen = StateError('boom');
    await expectLater(
      extractor().extract(pdfBytes()),
      throwsA(
        isA<PdfExtractException>().having(
          (e) => e.kind,
          'kind',
          PdfExtractFailureKind.unreadable,
        ),
      ),
    );
    raster.failOpen = PdfExtractException(PdfExtractFailureKind.wrongPassword);
    await expectLater(
      extractor().extract(pdfBytes(), password: 'x'),
      throwsA(
        isA<PdfExtractException>().having(
          (e) => e.kind,
          'kind',
          PdfExtractFailureKind.wrongPassword,
        ),
      ),
    );
  });

  test('a recognised amount in the wrong place is not imported', () async {
    // The 10/03 credit read under Debit: the balance says money came in.
    final moved = [
      for (final l in page1().lines)
        if (l.text == '763.01') line('763.01', 450, 491, 803.3) else l,
    ];
    ocr = FakeOcr([OcrOutcome(moved), page2()]);
    final uc = ImportStatementPdfUseCase(
      extractor(),
      store,
      MemTemplates(),
      now: () => DateTime(2026, 11, 18),
    );
    final reading = await uc.open(pdfBytes(), bankKey: 'scan');
    final s = await uc.run(
      reading,
      StatementMapping(
        roles: reading.table.suggestedRoles,
        currency: usd,
        dayFirst: reading.table.dayFirst,
      ),
      accountId: 'a1',
    );
    expect(s.invalid, 1);
    expect(s.imported, 4);
    expect(store.rows.any((r) => r.amount.minor == 76301), isFalse);
  });

  test('the picked bytes are zeroed even for a scan', () async {
    final bytes = pdfBytes();
    final uc = ImportStatementPdfUseCase(extractor(), store, MemTemplates());
    await uc.open(bytes, bankKey: 'scan');
    expect(bytes.every((b) => b == 0), isTrue);
  });
}
