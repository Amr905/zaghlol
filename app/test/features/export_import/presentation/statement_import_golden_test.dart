@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/export_import/presentation/statement_import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/statement_import_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../support/golden_matrix.dart';
import '../../../support/hide_amounts_support.dart';
import '../application/import_csv_test.dart' show FakeStore;
import '../application/import_statement_pdf_test.dart'
    show FakeExtractor, MemTemplates, f;
import 'import_flow_support.dart';
import 'statement_import_screen_test.dart'
    show FakeAccounts, FakeImageReader, FakeStatementPicker, pdfPick;

/// A yearless statement with one row whose direction is unknown: the review
/// shows the year prompt, an account, and a row that needs an answer.
List<PdfTextFragment> _fragments() => [
  f('Date', 40, 80, 100),
  f('Description', 170, 260, 100),
  f('Amount', 600, 660, 100),
  f('Balance', 820, 880, 100),
  f('01/05', 40, 140, 120),
  f('SHOP A', 170, 240, 120),
  f('100.00', 600, 660, 120),
  f('900.00', 790, 880, 120),
];

void main() {
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;
    for (final review in [false, true]) {
      final name = review ? 's67b_review' : 's67b_choose';
      testWidgets('$name golden ${v.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final uc = ImportStatementPdfUseCase(
          FakeExtractor(_fragments()),
          FakeStore(),
          MemTemplates(),
          now: () => DateTime(2026, 11, 18),
        );
        final container = ProviderContainer(
          overrides: [
            ...amountsShown(),
            ...importOverrides(
              lang,
              picker: FakePicker(null),
              runner: FakeRunner(),
            ),
            statementFilePickerProvider.overrideWithValue(
              FakeStatementPicker(pdf: pdfPick()),
            ),
            statementImportUseCaseProvider.overrideWith((ref) async => uc),
            statementAccountsProvider.overrideWithValue(
              FakeAccounts([
                StatementAccountChoice(
                  id: 'a1',
                  name: 'CIB',
                  currency: Currency.of('EGP'),
                ),
              ]),
            ),
            statementImageReaderProvider.overrideWithValue(
              FakeImageReader(const []),
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
              scale: v.textScale,
              dark: v.dark,
            ),
          ),
        );
        await t.pumpAndSettle();
        if (review) {
          await t.tap(find.byKey(const ValueKey('pickPdf')));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('goldens/${name}_${v.name}.png'),
        );
      });
    }
  }
}
