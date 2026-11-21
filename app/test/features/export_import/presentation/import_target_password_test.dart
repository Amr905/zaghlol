// FU-240c: the summary's target-card "Change" action and the PDF password
// step of the import flow (S-67).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/export_import/application/import_statement_pdf.dart';
import 'package:zaghlol/features/export_import/presentation/import_done_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/import_source_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../../../support/hide_amounts_support.dart';
import 'import_flow_support.dart';

const _secret = 'S3cretPw-9137';

void main() {
  for (final lang in ['ar', 'en']) {
    group('S-67 target card + PDF password ($lang)', () {
      String d(int v) => lang == 'ar'
          ? '$v'
                .split('')
                .map((c) => String.fromCharCode(0x0660 + int.parse(c)))
                .join()
          : '$v';
      late FakePicker picker;
      late FakeRunner runner;
      late HideAmountsHarness harness;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        List<ImportTargetCard> cards = const [
          ImportTargetCard(id: 'a1', name: 'CIB Visa'),
          ImportTargetCard(id: 'a2', name: 'NBE Debit'),
        ],
        String? card = 'CIB Visa',
      }) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: [
            ...harness.overrides,
            ...importOverrides(lang, picker: picker, runner: runner),
            importTargetCardsProvider.overrideWith((ref) async => cards),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(entitlementStateProvider.notifier)
            .applyVerified(verified: true, status: 'active');
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(ImportSourceScreen(targetCardName: card), lang: lang),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(Scaffold).first));
      }

      setUp(() {
        harness = HideAmountsHarness();
        picker = FakePicker(pickedFile());
        runner = FakeRunner(preview_: samplePreview());
      });

      testWidgets('Change picks another card and the import files under it', (
        t,
      ) async {
        runner.outcome = const ImportOutcome(imported: 142);
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.text(l.importFlowTarget('CIB Visa')), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('importTargetChange')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('importTarget_a2')));
        await t.pumpAndSettle();
        expect(find.text(l.importFlowTarget('NBE Debit')), findsOneWidget);
        await t.tap(find.text(l.importFlowConfirm(142, d(142))).last);
        await t.pumpAndSettle();
        expect(runner.lastTargetCardId, 'a2');
        expect(find.byType(ImportDoneScreen), findsOneWidget);
      });

      testWidgets('no Change with a single card or no target', (t) async {
        final l = await pump(
          t,
          cards: const [ImportTargetCard(id: 'a1', name: 'CIB Visa')],
        );
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('importTargetChange')), findsNothing);
      });

      testWidgets('untouched target sends no card id', (t) async {
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        await t.tap(find.text(l.importFlowConfirm(142, d(142))).last);
        await t.pumpAndSettle();
        expect(runner.commits, 1);
        expect(runner.lastTargetCardId, isNull);
      });

      testWidgets('password: asked, wrong then right, then summary', (t) async {
        runner.requirePassword = _secret;
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.text(l.exportsImportPasswordTitle), findsOneWidget);
        expect(find.text(l.exportsImportPasswordWrong), findsNothing);
        await t.enterText(find.byKey(const ValueKey('pdfPassword')), 'nope');
        await t.tap(find.byKey(const ValueKey('pdfPasswordOk')));
        await t.pumpAndSettle();
        // Wrong: asked again with the hint.
        expect(find.text(l.exportsImportPasswordWrong), findsOneWidget);
        await t.enterText(find.byKey(const ValueKey('pdfPassword')), _secret);
        await t.tap(find.byKey(const ValueKey('pdfPasswordOk')));
        await t.pumpAndSettle();
        expect(find.text(l.importFlowRowFound), findsOneWidget);
        expect(runner.previewPasswords, [null, 'nope', _secret]);
      });

      testWidgets('password: cancel ends the flow quietly', (t) async {
        runner.requirePassword = _secret;
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        await t.tap(find.text(l.commonActionCancel));
        await t.pumpAndSettle();
        expect(find.text(l.importFlowRowFound), findsNothing);
        expect(find.text(l.exportsImportFailed), findsNothing);
        expect(runner.commits, 0);
      });

      testWidgets('the password never reaches logs or storage', (t) async {
        runner.requirePassword = _secret;
        final logs = <String>[];
        final oldPrint = debugPrint;
        debugPrint = (m, {wrapWidth}) => logs.add(m ?? '');

        await runZoned(
          () async {
            final l = await pump(t);
            await t.tap(find.text(l.exportsImportZaghlolCsv));
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const ValueKey('pdfPassword')),
              _secret,
            );
            await t.tap(find.byKey(const ValueKey('pdfPasswordOk')));
            await t.pumpAndSettle();
            await t.tap(find.text(l.importFlowConfirm(142, d(142))).last);
            await t.pumpAndSettle();
          },
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) => logs.add(line),
          ),
        );
        debugPrint = oldPrint;
        expect(logs.join('\n'), isNot(contains(_secret)));
        // Nothing the flow handles prints it either.
        expect(pickedFile().toString(), isNot(contains(_secret)));
        expect(
          const ImportFlowException(ImportFailureKind.wrongPassword).toString(),
          isNot(contains(_secret)),
        );
        expect(
          const StatementImportException(StatementImportFailure.wrongPassword)
              .toString(),
          isNot(contains(_secret)),
        );
        // No preference was written with it: the settings keys hold no
        // password slot, and the field is cleared with its dialog.
        expect(harness.writes.values.join(), isNot(contains(_secret)));
        expect(harness.writes.keys.join(), isNot(contains('password')));
        expect(find.byKey(const ValueKey('pdfPassword')), findsNothing);
      });
    });
  }
}
