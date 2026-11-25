// T-156: statement import use case. Synthetic fragments only; the PDF
// reader is a fake (pdfrx needs the native PDFium library).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/import_csv.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'import_csv_test.dart' show FakeStore;

PdfTextFragment f(String t, int x0, int x1, int y) =>
    PdfTextFragment(page: 1, text: t, x0: x0, x1: x1, y: y);

List<PdfTextFragment> statement({bool header = true}) => [
  if (header) ...[
    f('Date', 40, 80, 100),
    f('Description', 170, 260, 100),
    f('Debit', 540, 600, 100),
    f('Credit', 660, 720, 100),
    f('Balance', 820, 880, 100),
  ],
  f('05/01/2026', 40, 140, 120),
  f('CARREFOUR', 170, 330, 120),
  f('1,250.50', 530, 600, 120),
  f('10,000.00', 790, 880, 120),
  f('05/01/2026', 40, 140, 140),
  f('CARREFOUR', 170, 330, 140),
  f('1,250.50', 530, 600, 140),
  f('8,749.50', 790, 880, 140),
  f('06/01/2026', 40, 140, 160),
  f('SALARY', 170, 280, 160),
  f('15,000.00', 650, 720, 160),
  f('23,749.50', 790, 880, 160),
];

class FakeExtractor implements PdfTextExtractor {
  FakeExtractor(this.fragments, {this.password});
  final List<PdfTextFragment> fragments;

  /// Non-null: the file is "encrypted" with this password.
  final String? password;
  final List<String?> offered = [];
  int calls = 0;
  Object? failWith;

  @override
  Future<List<PdfTextFragment>> extract(
    Uint8List bytes, {
    String? password,
  }) async {
    calls++;
    offered.add(password);
    if (failWith != null) throw failWith!;
    if (this.password != null) {
      if (password == null) {
        throw PdfExtractException(PdfExtractFailureKind.passwordRequired);
      }
      if (password != this.password) {
        throw PdfExtractException(PdfExtractFailureKind.wrongPassword);
      }
    }
    return fragments;
  }
}

class MemTemplates implements StatementTemplateStore {
  final Map<String, StatementTemplate> saved = {};
  @override
  Future<StatementTemplate?> load(String k) async => saved[k];
  @override
  Future<void> save(StatementTemplate t) async => saved[t.bankKey] = t;
}

Uint8List pdfBytes() => Uint8List.fromList(List.filled(64, 7));

final egp = Currency.of('EGP');

StatementMapping mapping() => StatementMapping(
  currency: egp,
  roles: const [
    StatementColumnRole.date,
    StatementColumnRole.description,
    StatementColumnRole.debit,
    StatementColumnRole.credit,
    StatementColumnRole.balance,
  ],
);

void main() {
  late FakeStore store;
  late MemTemplates templates;

  setUp(() {
    store = FakeStore();
    templates = MemTemplates();
  });

  ImportStatementPdfUseCase make(FakeExtractor x) =>
      ImportStatementPdfUseCase(x, store, templates);

  test('reads, imports rows as pdf source with exact money', () async {
    final uc = make(FakeExtractor(statement()));
    final reading = await uc.open(pdfBytes(), bankKey: 'cib');
    expect(reading.needsMapping, isFalse);
    final s = await uc.run(reading, mapping(), accountId: 'a1');
    expect(s.imported, 3);
    expect(s.duplicates, 0);
    expect(s.invalid, 0);
    expect(store.rows.map((r) => r.source).toSet(), {TxnSource.pdf});
    expect(store.rows[0].amount, Money.parse('1250.50', egp));
    expect(store.rows[0].direction, TxnDirection.expense);
    expect(store.rows[2].direction, TxnDirection.income);
    expect(store.rows[2].amount.minor, 1500000);
    expect(store.rows[0].merchant, 'CARREFOUR');
    expect(s.earliest, DateTime(2026, 1, 5, 12));
    expect(s.latest, DateTime(2026, 1, 6, 12));
  });

  group('dedupe', () {
    test('re-import adds nothing', () async {
      final uc = make(FakeExtractor(statement()));
      await uc.run(
        await uc.open(pdfBytes(), bankKey: 'cib'),
        mapping(),
        accountId: 'a1',
      );
      final again = await uc.run(
        await uc.open(pdfBytes(), bankKey: 'cib'),
        mapping(),
        accountId: 'a1',
      );
      expect(again.imported, 0);
      expect(again.duplicates, 3);
      expect(store.rows.length, 3);
    });

    test('matches an SMS row of the same day, direction and amount', () async {
      store.rows.add(
        ImportedTxn(
          accountId: 'a1',
          direction: TxnDirection.expense,
          status: TxnStatus.posted,
          amount: Money.parse('1250.50', egp),
          occurredAt: DateTime(2026, 1, 5, 18, 42).toUtc(),
          occurredTzOffsetMin: 0,
          merchant: 'Carrefour Maadi',
          source: TxnSource.sms,
        ),
      );
      final uc = make(FakeExtractor(statement()));
      final s = await uc.run(
        await uc.open(pdfBytes(), bankKey: 'cib'),
        mapping(),
        accountId: 'a1',
      );
      // Two identical purchases in the file, one already in the book.
      expect(s.duplicates, 1);
      expect(s.imported, 2);
    });

    test('another currency or account is not a duplicate', () async {
      store.rows.add(
        ImportedTxn(
          accountId: 'a1',
          direction: TxnDirection.expense,
          status: TxnStatus.posted,
          amount: Money.parse('1250.50', Currency.of('USD')),
          occurredAt: DateTime(2026, 1, 5, 12).toUtc(),
          occurredTzOffsetMin: 0,
        ),
      );
      final uc = make(FakeExtractor(statement()));
      final s = await uc.run(
        await uc.open(pdfBytes(), bankKey: 'cib'),
        mapping(),
        accountId: 'a1',
      );
      expect(s.duplicates, 0);
    });
  });

  group('password', () {
    test('required, then wrong, then right; never kept', () async {
      final x = FakeExtractor(statement(), password: 's3cret');
      final uc = make(x);
      await expectLater(
        uc.open(pdfBytes(), bankKey: 'cib'),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.passwordRequired,
          ),
        ),
      );
      await expectLater(
        uc.open(pdfBytes(), bankKey: 'cib', password: 'nope'),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.wrongPassword,
          ),
        ),
      );
      final r = await uc.open(pdfBytes(), bankKey: 'cib', password: 's3cret');
      expect(r.table.rows, isNotEmpty);
      // The password is not in anything that outlives the call.
      final s = await uc.run(r, mapping(), accountId: 'a1');
      expect(s.toString(), isNot(contains('s3cret')));
      expect(r.toString(), isNot(contains('s3cret')));
      expect(templates.saved['cib']!.toJson(), isNot(contains('s3cret')));
    });

    test('errors never carry the password', () {
      const e = StatementImportException(StatementImportFailure.wrongPassword);
      expect(e.toString(), isNot(contains('s3cret')));
    });
  });

  group('cleanup', () {
    test('picked bytes are zeroed after a successful read', () async {
      final bytes = pdfBytes();
      await make(FakeExtractor(statement())).open(bytes, bankKey: 'cib');
      expect(bytes.every((b) => b == 0), isTrue);
    });

    test('and after a failure', () async {
      for (final failure in <Object>[
        PdfExtractException(PdfExtractFailureKind.passwordRequired),
        StateError('boom'),
      ]) {
        final bytes = pdfBytes();
        final x = FakeExtractor(statement())..failWith = failure;
        await expectLater(
          make(x).open(bytes, bankKey: 'cib'),
          throwsA(isA<StatementImportException>()),
        );
        expect(bytes.every((b) => b == 0), isTrue);
      }
    });

    test('a hostile extractor error becomes unreadable, no text', () async {
      final x = FakeExtractor(statement())..failWith = StateError('IBAN 123');
      try {
        await make(x).open(pdfBytes(), bankKey: 'cib');
        fail('should throw');
      } on StatementImportException catch (e) {
        expect(e.kind, StatementImportFailure.unreadable);
        expect(e.toString(), isNot(contains('IBAN')));
      }
    });
  });

  group('mapping and templates', () {
    test('no header asks for mapping; the template then skips it', () async {
      final uc = make(FakeExtractor(statement(header: false)));
      final first = await uc.open(pdfBytes(), bankKey: 'nbe');
      expect(first.needsMapping, isTrue);
      expect(first.table.suggestedRoles[0], StatementColumnRole.date);
      await uc.run(first, mapping(), accountId: 'a1');
      expect(templates.saved.keys, ['nbe']);

      store.rows.clear();
      final second = await uc.open(pdfBytes(), bankKey: 'nbe');
      expect(second.needsMapping, isFalse);
      final s = await uc.run(second, mapping(), accountId: 'a1');
      expect(s.imported, 3);
    });

    test('templates are per bank', () async {
      final uc = make(FakeExtractor(statement(header: false)));
      await uc.run(
        await uc.open(pdfBytes(), bankKey: 'nbe'),
        mapping(),
        accountId: 'a1',
      );
      final other = await uc.open(pdfBytes(), bankKey: 'qnb');
      expect(other.needsMapping, isTrue);
    });

    test('dry run writes nothing and saves no template', () async {
      final uc = make(FakeExtractor(statement(header: false)));
      final s = await uc.run(
        await uc.open(pdfBytes(), bankKey: 'nbe'),
        mapping(),
        accountId: 'a1',
        dryRun: true,
      );
      expect(s.imported, 3);
      expect(store.rows, isEmpty);
      expect(templates.saved, isEmpty);
    });

    test('invalid mapping and unknown account are typed failures', () async {
      final uc = make(FakeExtractor(statement()));
      final r = await uc.open(pdfBytes(), bankKey: 'cib');
      await expectLater(
        uc.run(
          r,
          mapping().copyWith(roles: List.filled(5, StatementColumnRole.ignore)),
          accountId: 'a1',
        ),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.badMapping,
          ),
        ),
      );
      await expectLater(
        uc.run(r, mapping(), accountId: 'nope'),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.unknownAccount,
          ),
        ),
      );
      expect(store.rows, isEmpty);
    });
  });

  test('a PDF with no table rows is noRows', () async {
    final uc = make(FakeExtractor([f('Hello', 10, 100, 10)]));
    await expectLater(
      uc.open(pdfBytes(), bankKey: 'cib'),
      throwsA(
        isA<StatementImportException>().having(
          (e) => e.kind,
          'kind',
          StatementImportFailure.noRows,
        ),
      ),
    );
  });

  test('store failure rolls back, typed', () async {
    store.exceptionOnInsert = true;
    final uc = make(FakeExtractor(statement()));
    await expectLater(
      uc.run(
        await uc.open(pdfBytes(), bankKey: 'cib'),
        mapping(),
        accountId: 'a1',
      ),
      throwsA(
        isA<StatementImportException>().having(
          (e) => e.kind,
          'kind',
          StatementImportFailure.storeFailed,
        ),
      ),
    );
    expect(store.rows, isEmpty);
    expect(templates.saved, isEmpty);
  });

  test('onImported runs for each new row after commit', () async {
    final ids = <String>[];
    final uc = ImportStatementPdfUseCase(
      FakeExtractor(statement()),
      store,
      templates,
      onImported: (id) async => ids.add(id),
    );
    await uc.run(
      await uc.open(pdfBytes(), bankKey: 'cib'),
      mapping(),
      accountId: 'a1',
    );
    expect(ids.length, 3);
  });

  group('review step and year confirmation (T-156b fixes)', () {
    // Row B's balance is off by one: 10,000 - 1,250.50 = 8,749.50.
    List<PdfTextFragment> mismatching() => [
      ...statement().take(5),
      f('05/01/2026', 40, 140, 120),
      f('CARREFOUR', 170, 330, 120),
      f('1,250.50', 530, 600, 120),
      f('8,749.50', 790, 880, 120),
      f('06/01/2026', 40, 140, 140),
      f('SALARY', 170, 280, 140),
      f('15,000.00', 650, 720, 140),
      f('23,000.00', 790, 880, 140), // should be 23,749.50
    ];

    // Unsigned single amount column, first row with no opening balance.
    List<PdfTextFragment> unsigned() => [
      f('Date', 40, 80, 100),
      f('Description', 170, 260, 100),
      f('Amount', 600, 660, 100),
      f('Balance', 820, 880, 100),
      f('05/01/2026', 40, 140, 120),
      f('SHOP A', 170, 240, 120),
      f('100.00', 600, 660, 120),
      f('900.00', 790, 880, 120),
    ];
    StatementMapping unsignedMapping() => StatementMapping(
      currency: egp,
      roles: const [
        StatementColumnRole.date,
        StatementColumnRole.description,
        StatementColumnRole.amount,
        StatementColumnRole.balance,
      ],
    );

    test('a balance mismatch is held for review, never dropped', () async {
      final uc = make(FakeExtractor(mismatching()));
      final reading = await uc.open(pdfBytes(), bankKey: 'b');
      final parsed = uc.parse(reading, mapping());
      expect(parsed.rows, hasLength(1));
      expect(parsed.review, hasLength(1));
      expect(
        parsed.review.single.review,
        StatementReviewReason.balanceMismatch,
      );
      expect(parsed.review.single.amount.minor, 1500000);
      // Preview: reported under its own kind, not as a bad amount.
      final dry = await uc.run(
        reading,
        mapping(),
        accountId: 'a1',
        dryRun: true,
      );
      expect(dry.needsReview, 1);
      expect(dry.invalidByProblem[ImportRowProblem.balanceMismatch], 1);
      expect(dry.invalidByProblem[ImportRowProblem.badAmount], isNull);
      // Not committed until the user decides.
      await expectLater(
        uc.run(reading, mapping(), accountId: 'a1'),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.reviewRequired,
          ),
        ),
      );
      expect(store.rows, isEmpty);
    });

    test('keep, skip and fix-direction decisions are applied', () async {
      final uc = make(FakeExtractor(mismatching()));
      final reading = await uc.open(pdfBytes(), bankKey: 'b');
      final kept = await uc.run(
        reading,
        mapping(),
        accountId: 'a1',
        decisions: {2: StatementReviewChoice.keep},
      );
      expect(kept.imported, 2);
      expect(store.rows.last.direction, TxnDirection.income);

      store.rows.clear();
      final flipped = await uc.run(
        reading,
        mapping(),
        accountId: 'a1',
        decisions: {2: StatementReviewChoice.asExpense},
      );
      expect(flipped.imported, 2);
      expect(store.rows.last.direction, TxnDirection.expense);

      store.rows.clear();
      final skipped = await uc.run(
        reading,
        mapping(),
        accountId: 'a1',
        decisions: {2: StatementReviewChoice.skip},
      );
      expect(skipped.imported, 1);
    });

    test('unsigned amount with no derivable direction is not income', () async {
      final uc = make(FakeExtractor(unsigned()));
      final reading = await uc.open(pdfBytes(), bankKey: 'u');
      final parsed = uc.parse(reading, unsignedMapping());
      expect(parsed.rows, isEmpty);
      expect(
        parsed.review.single.review,
        StatementReviewReason.directionUnknown,
      );
      expect(parsed.review.single.directionKnown, isFalse);
      // "keep" is not a valid answer when the direction is unset.
      await expectLater(
        uc.run(
          reading,
          unsignedMapping(),
          accountId: 'a1',
          decisions: {1: StatementReviewChoice.keep},
        ),
        throwsA(isA<StatementImportException>()),
      );
      expect(store.rows, isEmpty);
      final s = await uc.run(
        reading,
        unsignedMapping(),
        accountId: 'a1',
        decisions: {1: StatementReviewChoice.asExpense},
      );
      expect(s.imported, 1);
      expect(store.rows.single.direction, TxnDirection.expense);
    });

    List<PdfTextFragment> yearless() => [
      f('Date', 40, 80, 100),
      f('Description', 170, 260, 100),
      f('Debit', 540, 600, 100),
      f('Credit', 660, 720, 100),
      f('Balance', 820, 880, 100),
      f('01/05', 40, 140, 120),
      f('CARREFOUR', 170, 330, 120),
      f('100.00', 540, 600, 120),
      f('900.00', 790, 880, 120),
    ];

    test(
      'no printed year: commit refused until the year is confirmed',
      () async {
        final uc = ImportStatementPdfUseCase(
          FakeExtractor(yearless()),
          store,
          templates,
          now: () => DateTime(2026, 11, 18),
        );
        final reading = await uc.open(pdfBytes(), bankKey: 'y');
        expect(ImportStatementPdfUseCase.needsYear(reading), isTrue);
        expect(reading.table.yearSource, StatementYearSource.today);
        await expectLater(
          uc.run(reading, mapping(), accountId: 'a1', decisions: const {}),
          throwsA(
            isA<StatementImportException>().having(
              (e) => e.kind,
              'kind',
              StatementImportFailure.yearNotConfirmed,
            ),
          ),
        );
        expect(store.rows, isEmpty);
        // The user says the statement is from 2024.
        final s = await uc.run(
          reading,
          mapping(),
          accountId: 'a1',
          confirmedYear: 2024,
          decisions: {1: StatementReviewChoice.asExpense},
        );
        expect(s.imported, 1);
        expect(store.rows.single.occurredAt.toLocal().year, 2024);
      },
    );

    test('a statement with printed dates needs no year answer', () async {
      final uc = make(FakeExtractor(statement()));
      final reading = await uc.open(pdfBytes(), bankKey: 'cib');
      expect(ImportStatementPdfUseCase.needsYear(reading), isFalse);
    });
  });

  group('review decisions on clean rows and kept duplicates (T-269)', () {
    test('skip drops a clean row, a direction flip changes it', () async {
      final uc = make(FakeExtractor(statement()));
      final reading = await uc.open(pdfBytes(), bankKey: 'cib');
      final s = await uc.run(
        reading,
        mapping(),
        accountId: 'a1',
        decisions: {
          1: StatementReviewChoice.skip,
          3: StatementReviewChoice.asExpense,
        },
      );
      expect(s.imported, 2);
      expect(store.rows.map((r) => r.direction), [
        TxnDirection.expense,
        TxnDirection.expense,
      ]);
    });

    test(
      'a dry run lists duplicate rows; keepDuplicates imports them',
      () async {
        final uc = make(FakeExtractor(statement()));
        await uc.run(
          await uc.open(pdfBytes(), bankKey: 'cib'),
          mapping(),
          accountId: 'a1',
        );
        final reading = await uc.open(pdfBytes(), bankKey: 'cib');
        final dry = await uc.run(
          reading,
          mapping(),
          accountId: 'a1',
          dryRun: true,
        );
        expect(dry.duplicateRows, [1, 2, 3]);
        expect(dry.imported, 0);
        final s = await uc.run(
          reading,
          mapping(),
          accountId: 'a1',
          keepDuplicates: {2},
        );
        expect(s.imported, 1);
        expect(s.duplicates, 2);
        expect(store.rows, hasLength(4));
      },
    );

    test('openFragments with no text is noText', () async {
      final uc = make(FakeExtractor(const []));
      await expectLater(
        uc.openFragments(const [], bankKey: 'cib'),
        throwsA(
          isA<StatementImportException>().having(
            (e) => e.kind,
            'kind',
            StatementImportFailure.noText,
          ),
        ),
      );
    });
  });
}
