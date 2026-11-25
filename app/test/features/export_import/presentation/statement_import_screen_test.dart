// T-269 / US-P08: the bank statement import screen, from the picker to the
// saved rows, over synthetic statements (no real bank data).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/ui/z_components.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/export_import/application/statement_image_reader.dart'
    show StatementImageReader;
import 'package:zaghlol/features/export_import/presentation/import_done_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/import_source_screen.dart';
import 'package:zaghlol/features/export_import/presentation/statement_import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/statement_import_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../support/hide_amounts_support.dart';
import '../application/import_csv_test.dart' show FakeStore;
import '../application/import_statement_pdf_test.dart'
    show FakeExtractor, MemTemplates, f, mapping, statement;
import 'import_flow_support.dart';

class FakeStatementPicker implements StatementFilePicker {
  FakeStatementPicker({this.pdf, this.images});
  PickedStatement? pdf;
  PickedStatement? images;
  int calls = 0;

  @override
  Future<PickedStatement?> pickPdf() async {
    calls++;
    return pdf;
  }

  @override
  Future<PickedStatement?> pickImages() async {
    calls++;
    return images;
  }
}

PickedStatement pdfPick() => PickedStatement(
  isPdf: true,
  files: [PickedImportFile(name: 'stmt.pdf', bytes: Uint8List(64))],
);

PickedStatement imagePick() => PickedStatement(
  isPdf: false,
  files: [
    PickedImportFile(name: 'p1.jpg', bytes: Uint8List.fromList([1, 2, 3])),
  ],
);

class FakeAccounts implements StatementAccountsPort {
  FakeAccounts(this.accounts);
  final List<StatementAccountChoice> accounts;
  final List<String> created = [];

  @override
  Future<List<StatementAccountChoice>> list() async => accounts;

  @override
  Future<StatementAccountChoice> create({
    required String institutionCode,
    required String name,
    required Currency currency,
    String? last4,
  }) async {
    created.add('$institutionCode|$name|${currency.code}|${last4 ?? ''}');
    return StatementAccountChoice(id: 'a1', name: name, currency: currency);
  }
}

class FakeImageReader implements StatementImageReader {
  FakeImageReader(this.fragments, {this.error});
  final List<PdfTextFragment> fragments;
  final Object? error;
  int calls = 0;

  @override
  Future<List<PdfTextFragment>> read(List<Uint8List> images) async {
    calls++;
    if (error != null) throw error!;
    return fragments;
  }
}

final _egp = Currency.of('EGP');
final _cib = StatementAccountChoice(id: 'a1', name: 'CIB', currency: _egp);

List<PdfTextFragment> _yearless() => [
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

/// Unsigned single amount column: the direction cannot be told.
List<PdfTextFragment> _unsigned() => [
  f('Date', 40, 80, 100),
  f('Description', 170, 260, 100),
  f('Amount', 600, 660, 100),
  f('Balance', 820, 880, 100),
  f('05/01/2026', 40, 140, 120),
  f('SHOP A', 170, 240, 120),
  f('100.00', 600, 660, 120),
  f('900.00', 790, 880, 120),
];

void main() {
  late String lang0;
  String d(int v) => lang0 == 'ar'
      ? '$v'
            .split('')
            .map((c) => String.fromCharCode(0x0660 + int.parse(c)))
            .join()
      : '$v';

  for (final lang in ['ar', 'en']) {
    group('T-269 statement import ($lang)', () {
      setUpAll(() => lang0 = lang);
      setUp(() => lang0 = lang);

      late FakeStore store;
      late FakeStatementPicker picker;
      late FakeAccounts accounts;
      late FakeImageReader images;
      late ImportStatementPdfUseCase uc;
      bool ocrAvailable = true;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        required FakeExtractor extractor,
        DateTime? now,
        double scale = 1.0,
      }) async {
        await t.binding.setSurfaceSize(const Size(390, 1700));
        addTearDown(() => t.binding.setSurfaceSize(null));
        uc = ImportStatementPdfUseCase(
          extractor,
          store,
          MemTemplates(),
          now: now == null ? null : () => now,
        );
        final container = ProviderContainer(
          overrides: [
            ...amountsShown(),
            ...importOverrides(
              lang,
              picker: FakePicker(null),
              runner: FakeRunner(),
            ),
            statementFilePickerProvider.overrideWithValue(picker),
            statementImportUseCaseProvider.overrideWith((ref) async => uc),
            statementAccountsProvider.overrideWithValue(accounts),
            statementImageReaderProvider.overrideWithValue(images),
            statementOcrAvailableProvider.overrideWith(
              (ref) async => ocrAvailable,
            ),
          ],
        );
        addTearDown(container.dispose);
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(
              const StatementImportScreen(bankKey: 'cib', bankName: 'CIB'),
              lang: lang,
              scale: scale,
            ),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(Scaffold).first));
      }

      Future<void> pickPdf(WidgetTester t) async {
        await t.tap(find.byKey(const ValueKey('pickPdf')));
        await t.pumpAndSettle();
      }

      Finder button(String label) => find.widgetWithText(ZButton, label);

      ZButton confirm(WidgetTester t) =>
          t.widget<ZButton>(find.byKey(const ValueKey('stmtConfirm')));

      setUp(() {
        store = FakeStore();
        picker = FakeStatementPicker(pdf: pdfPick(), images: imagePick());
        accounts = FakeAccounts([_cib]);
        images = FakeImageReader(statement());
        ocrAvailable = true;
      });

      testWidgets('choose step offers PDF and photos, nothing read yet', (
        t,
      ) async {
        final l = await pump(t, extractor: FakeExtractor(statement()));
        expect(find.text(l.stmtImportTitle('CIB')), findsOneWidget);
        expect(find.text(l.stmtImportPickPdf), findsOneWidget);
        expect(find.text(l.stmtImportPickImages), findsOneWidget);
        expect(picker.calls, 0);
      });

      testWidgets('happy path: rows shown, nothing saved until Confirm', (
        t,
      ) async {
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        expect(find.text(l.stmtImportReviewTitle), findsOneWidget);
        expect(find.text('CARREFOUR'), findsNWidgets(2));
        expect(find.text('SALARY'), findsOneWidget);
        expect(find.text(l.stmtImportSectionRows(d(3))), findsOneWidget);
        // The one EGP account is preselected; the button counts the rows.
        expect(find.text(l.importFlowConfirm(3, d(3))), findsOneWidget);
        expect(confirm(t).onPressed, isNotNull);
        expect(store.rows, isEmpty);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows, hasLength(3));
        expect(store.rows.every((r) => r.accountId == 'a1'), isTrue);
        expect(store.rows.first.direction, TxnDirection.expense);
        expect(find.byType(ImportDoneScreen), findsOneWidget);
      });

      testWidgets('skipping a row from its menu drops it from the import', (
        t,
      ) async {
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        await t.tap(find.byTooltip(l.stmtImportRowEdit).first);
        await t.pumpAndSettle();
        await t.tap(find.text(l.stmtImportChoiceSkip));
        await t.pumpAndSettle();
        expect(find.text(l.stmtImportRowSkipped), findsOneWidget);
        expect(find.text(l.importFlowConfirm(2, d(2))), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows, hasLength(2));
      });

      testWidgets('year not printed: asked once, Confirm waits for it', (
        t,
      ) async {
        final l = await pump(
          t,
          extractor: FakeExtractor(_yearless()),
          now: DateTime(2026, 11, 18),
        );
        await pickPdf(t);
        expect(find.text(l.stmtImportYearTitle), findsOneWidget);
        expect(confirm(t).onPressed, isNull);
        expect(find.text(l.stmtImportBlockedYear), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('year_2024')));
        await t.pumpAndSettle();
        expect(confirm(t).onPressed, isNotNull);
        expect(store.rows, isEmpty);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows.single.occurredAt.toLocal().year, 2024);
      });

      testWidgets('unknown direction: Confirm blocked until answered', (
        t,
      ) async {
        final l = await pump(t, extractor: FakeExtractor(_unsigned()));
        await pickPdf(t);
        expect(find.text(l.stmtImportSectionAnswer(d(1))), findsOneWidget);
        expect(find.text(l.stmtImportReasonDirection), findsOneWidget);
        expect(confirm(t).onPressed, isNull);
        expect(find.text(l.stmtImportBlockedAnswers), findsOneWidget);
        await t.tap(button(l.stmtImportChoiceOut));
        await t.pumpAndSettle();
        expect(find.text(l.stmtImportReasonDirection), findsNothing);
        expect(confirm(t).onPressed, isNotNull);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows.single.direction, TxnDirection.expense);
      });

      testWidgets('unknown direction can be skipped instead', (t) async {
        final l = await pump(t, extractor: FakeExtractor(_unsigned()));
        await pickPdf(t);
        await t.tap(button(l.stmtImportChoiceSkip));
        await t.pumpAndSettle();
        expect(confirm(t).onPressed, isNull);
        expect(find.text(l.stmtImportNothingToAdd), findsOneWidget);
        expect(store.rows, isEmpty);
      });

      testWidgets('balance mismatch is flagged and can be kept', (t) async {
        final bad = [
          ...statement().take(9),
          f('05/01/2026', 40, 140, 140),
          f('CARREFOUR', 170, 330, 140),
          f('1,250.50', 530, 600, 140),
          f('8,749.50', 790, 880, 140),
          f('06/01/2026', 40, 140, 160),
          f('SALARY', 170, 280, 160),
          f('15,000.00', 650, 720, 160),
          f('23,000.00', 790, 880, 160), // should be 23,749.50
        ];
        final l = await pump(t, extractor: FakeExtractor(bad));
        await pickPdf(t);
        expect(find.text(l.stmtImportReasonBalance), findsOneWidget);
        expect(confirm(t).onPressed, isNull);
        await t.tap(button(l.stmtImportChoiceKeep));
        await t.pumpAndSettle();
        expect(confirm(t).onPressed, isNotNull);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows, hasLength(3));
      });

      testWidgets('possible duplicates are skipped unless added anyway', (
        t,
      ) async {
        // Same statement imported before.
        final seed = ImportStatementPdfUseCase(
          FakeExtractor(statement()),
          store,
          MemTemplates(),
        );
        await seed.run(
          await seed.open(Uint8List(8), bankKey: 'cib'),
          mapping(),
          accountId: 'a1',
        );
        expect(store.rows, hasLength(3));
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        expect(find.text(l.stmtImportSectionDup(d(3))), findsOneWidget);
        expect(find.text(l.stmtImportDupNote), findsNWidgets(3));
        expect(confirm(t).onPressed, isNull);
        expect(find.text(l.stmtImportNothingToAdd), findsOneWidget);
        await t.tap(button(l.stmtImportDupAddAnyway).last);
        await t.pumpAndSettle();
        expect(find.text(l.importFlowConfirm(1, d(1))), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows, hasLength(4));
      });

      testWidgets('no matching account: a new one is created on Confirm only', (
        t,
      ) async {
        accounts = FakeAccounts(const []);
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        expect(find.text(l.stmtImportAccountNoneYet('EGP')), findsOneWidget);
        expect(
          t
              .widget<TextField>(find.byKey(const ValueKey('acctName')))
              .controller!
              .text,
          'CIB',
        );
        await t.enterText(find.byKey(const ValueKey('acctLast4')), '1234');
        await t.pumpAndSettle();
        expect(accounts.created, isEmpty);
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(accounts.created, ['cib|CIB|EGP|1234']);
        expect(store.rows, hasLength(3));
      });

      testWidgets('several accounts: none preselected, pick one', (t) async {
        accounts = FakeAccounts([
          _cib,
          StatementAccountChoice(id: 'a2', name: 'NBE', currency: _egp),
        ]);
        store = FakeStore(accounts: {'a1', 'a2'});
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        expect(confirm(t).onPressed, isNull);
        expect(find.text(l.stmtImportBlockedAccount), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('acct_a2')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('stmtConfirm')));
        await t.pumpAndSettle();
        expect(store.rows.every((r) => r.accountId == 'a2'), isTrue);
      });

      testWidgets('photos: read by the image reader, same review', (t) async {
        final l = await pump(t, extractor: FakeExtractor(const []));
        await t.tap(find.byKey(const ValueKey('pickImages')));
        await t.pumpAndSettle();
        expect(images.calls, 1);
        expect(find.text(l.stmtImportReviewTitle), findsOneWidget);
        expect(store.rows, isEmpty);
      });

      group('failures', () {
        testWidgets('no table found', (t) async {
          final l = await pump(
            t,
            extractor: FakeExtractor([f('Hello', 40, 90, 100)]),
          );
          await pickPdf(t);
          expect(find.text(l.stmtImportErrNoRows), findsOneWidget);
          expect(find.text(l.stmtImportPickPdf), findsOneWidget);
        });

        testWidgets('scan with no OCR on this phone', (t) async {
          ocrAvailable = false;
          final x = FakeExtractor(const [])
            ..failWith = PdfExtractException(PdfExtractFailureKind.noText);
          final l = await pump(t, extractor: x);
          await pickPdf(t);
          expect(find.text(l.stmtImportErrNoOcr), findsOneWidget);
        });

        testWidgets('scan with OCR but nothing readable', (t) async {
          final x = FakeExtractor(const [])
            ..failWith = PdfExtractException(PdfExtractFailureKind.noText);
          final l = await pump(t, extractor: x);
          await pickPdf(t);
          expect(find.text(l.stmtImportErrNoText), findsOneWidget);
        });

        testWidgets('unreadable file', (t) async {
          final x = FakeExtractor(const [])
            ..failWith = PdfExtractException(PdfExtractFailureKind.unreadable);
          final l = await pump(t, extractor: x);
          await pickPdf(t);
          expect(find.text(l.exportsImportFailed), findsOneWidget);
        });

        testWidgets('photos with no OCR', (t) async {
          ocrAvailable = false;
          images = FakeImageReader(
            const [],
            error: PdfExtractException(PdfExtractFailureKind.noText),
          );
          final l = await pump(t, extractor: FakeExtractor(const []));
          await t.tap(find.byKey(const ValueKey('pickImages')));
          await t.pumpAndSettle();
          expect(find.text(l.stmtImportErrNoOcr), findsOneWidget);
        });

        testWidgets('password: asked, then the right one opens it', (t) async {
          final x = FakeExtractor(statement(), password: 'pw1');
          final l = await pump(t, extractor: x);
          await pickPdf(t);
          expect(find.text(l.exportsImportPasswordTitle), findsOneWidget);
          await t.enterText(find.byKey(const ValueKey('pdfPassword')), 'nope');
          await t.tap(find.byKey(const ValueKey('pdfPasswordOk')));
          await t.pumpAndSettle();
          expect(find.text(l.exportsImportPasswordWrong), findsOneWidget);
          await t.enterText(find.byKey(const ValueKey('pdfPassword')), 'pw1');
          await t.tap(find.byKey(const ValueKey('pdfPasswordOk')));
          await t.pumpAndSettle();
          expect(find.text(l.stmtImportReviewTitle), findsOneWidget);
          expect(store.rows, isEmpty);
        });

        testWidgets('password prompt cancelled: reason shown', (t) async {
          final x = FakeExtractor(statement(), password: 'pw1');
          final l = await pump(t, extractor: x);
          await pickPdf(t);
          await t.tap(find.text(l.commonActionCancel));
          await t.pumpAndSettle();
          expect(find.text(l.stmtImportErrPassword), findsOneWidget);
        });

        testWidgets('save failure keeps the review and says nothing added', (
          t,
        ) async {
          final l = await pump(t, extractor: FakeExtractor(statement()));
          await pickPdf(t);
          store.exceptionOnInsert = true;
          await t.tap(find.byKey(const ValueKey('stmtConfirm')));
          await t.pumpAndSettle();
          expect(find.text(l.stmtImportErrSave), findsOneWidget);
          expect(store.rows, isEmpty);
          expect(find.byType(ImportDoneScreen), findsNothing);
        });
      });

      testWidgets('picker cancelled: stays on the choose step', (t) async {
        picker.pdf = null;
        final l = await pump(t, extractor: FakeExtractor(statement()));
        await pickPdf(t);
        expect(find.text(l.stmtImportPickPdf), findsOneWidget);
        expect(find.text(l.stmtImportReviewTitle), findsNothing);
      });

      testWidgets('text scale 1.3 does not overflow in review', (t) async {
        await pump(t, extractor: FakeExtractor(_unsigned()), scale: 1.3);
        await pickPdf(t);
        expect(t.takeException(), isNull);
      });

      testWidgets('source list: a bank opens the statement screen', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: [
            ...amountsShown(),
            ...importOverrides(
              lang,
              picker: FakePicker(null),
              runner: FakeRunner(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(entitlementStateProvider.notifier)
            .applyVerified(verified: true, status: 'active');
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(const ImportSourceScreen(), lang: lang),
          ),
        );
        await t.pumpAndSettle();
        final l = AppLocalizations.of(t.element(find.byType(Scaffold).first));
        await t.tap(find.text(l.importFlowBankNbe));
        await t.pumpAndSettle();
        expect(find.byType(StatementImportScreen), findsOneWidget);
        expect(
          find.text(l.stmtImportTitle(l.importFlowBankNbe)),
          findsOneWidget,
        );
      });
    });
  }
}
