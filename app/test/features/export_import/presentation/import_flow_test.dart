import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/export_import/presentation/import_done_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/import_source_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import 'import_flow_support.dart';
import '../../../support/hide_amounts_support.dart';

void main() {
  // Arabic uses Arabic-Indic digits under the default digit mode.
  late String lang0;
  String d(int v) => lang0 == 'ar'
      ? '$v'
            .split('')
            .map((c) => String.fromCharCode(0x0660 + int.parse(c)))
            .join()
      : '$v';
  for (final lang in ['ar', 'en']) {
    group('S-67 import flow ($lang)', () {
      setUpAll(() => lang0 = lang);
      setUp(() => lang0 = lang);
      late FakePicker picker;
      late FakeRunner runner;
      late ProviderContainer container;
      GoldCapability? paywallFor;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        bool gold = true,
        double scale = 1.0,
        Widget? screen,
      }) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        paywallFor = null;
        container = ProviderContainer(
          overrides: [
            ...amountsShown(),
            ...importOverrides(lang, picker: picker, runner: runner),
            paywallTriggerProvider.overrideWithValue((c) => paywallFor = c),
          ],
        );
        addTearDown(container.dispose);
        if (gold) {
          container
              .read(entitlementStateProvider.notifier)
              .applyVerified(verified: true, status: 'active');
        }
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(
              screen ?? const ImportSourceScreen(),
              lang: lang,
              scale: scale,
            ),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(Scaffold).first));
      }

      setUp(() {
        picker = FakePicker(pickedFile());
        runner = FakeRunner(preview_: samplePreview());
      });

      testWidgets(
        'lists every source; online-bank CSVs are still coming soon',
        (t) async {
          final l = await pump(t);
          expect(find.text(l.importFlowTitle), findsOneWidget);
          expect(find.text(l.importFlowGroupEgypt), findsOneWidget);
          expect(find.text(l.importFlowGroupOnline), findsOneWidget);
          expect(find.text(l.importFlowBankNbe), findsOneWidget);
          expect(find.text(l.importFlowBankRevolut), findsOneWidget);
          expect(find.textContaining(l.importFlowSoon), findsNWidgets(3));
          await t.tap(find.text(l.importFlowBankRevolut), warnIfMissed: false);
          await t.pumpAndSettle();
          expect(picker.calls, 0);
        },
      );

      testWidgets('text scale 1.3 does not overflow', (t) async {
        await pump(t, scale: 1.3);
        expect(t.takeException(), isNull);
      });

      testWidgets('Free: a tap opens the paywall, no picker', (t) async {
        final l = await pump(t, gold: false);
        expect(find.text(l.exportsImportLockedBody), findsOneWidget);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(paywallFor, GoldCapability.csvImport);
        expect(picker.calls, 0);
      });

      testWidgets('how-to link opens the sheet', (t) async {
        final l = await pump(t);
        await t.tap(find.text(l.importFlowHowTo));
        await t.pumpAndSettle();
        expect(find.text(l.importFlowHowToBody), findsOneWidget);
      });

      testWidgets('pick -> summary -> confirm -> done', (t) async {
        runner.outcome = const ImportOutcome(imported: 142);
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(picker.lastKind, ImportFileKind.csv);
        expect(find.text('CIB_Statement_Oct.csv'), findsOneWidget);
        expect(find.text(l.importFlowRowFound), findsOneWidget);
        expect(find.text(l.importFlowRowDup), findsOneWidget);
        expect(find.text(l.importFlowRowUntracked), findsOneWidget);
        expect(find.text(l.importFlowRowNew), findsOneWidget);
        expect(find.text(l.importFlowRowUnreadable), findsNothing);
        expect(runner.commits, 0);
        await t.tap(find.text(l.importFlowConfirm(142, d(142))).last);
        await t.pumpAndSettle();
        expect(runner.commits, 1);
        expect(find.byType(ImportDoneScreen), findsOneWidget);
        expect(find.text(l.importFlowDoneTitle(142, d(142))), findsWidgets);
      });

      testWidgets('picker cancelled: nothing happens', (t) async {
        picker.file = null;
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.byType(ImportDoneScreen), findsNothing);
        expect(find.text(l.importFlowRowFound), findsNothing);
      });

      testWidgets('empty file: warning and no confirm', (t) async {
        runner.preview_ = samplePreview(
          found: 0,
          dup: 0,
          untracked: 0,
          newCount: 0,
        );
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.text(l.exportsImportEmptyTitle), findsOneWidget);
        expect(find.text(l.importFlowConfirm(0, d(0))), findsOneWidget);
      });

      testWidgets('nothing new: info and disabled confirm', (t) async {
        runner.preview_ = samplePreview(
          found: 5,
          dup: 5,
          untracked: 0,
          newCount: 0,
        );
        final l = await pump(t);
        await t.tap(find.text(l.exportsImportZaghlolCsv));
        await t.pumpAndSettle();
        expect(find.text(l.exportsImportNothingNew), findsOneWidget);
        await t.tap(
          find.text(l.importFlowConfirm(0, d(0))),
          warnIfMissed: false,
        );
        await t.pumpAndSettle();
        expect(runner.commits, 0);
      });

      for (final kind in [
        ImportFailureKind.wrongType,
        ImportFailureKind.unsupported,
        ImportFailureKind.failed,
      ]) {
        testWidgets('error ${kind.name} shows a banner', (t) async {
          runner.failure = kind;
          final l = await pump(t);
          await t.tap(find.text(l.exportsImportZaghlolCsv));
          await t.pumpAndSettle();
          final text = switch (kind) {
            ImportFailureKind.wrongType => l.exportsImportWrongType,
            ImportFailureKind.unsupported => l.exportsImportUnsupportedTitle,
            _ => l.exportsImportFailed,
          };
          expect(find.text(text), findsOneWidget);
          expect(runner.commits, 0);
        });
      }

      testWidgets('done: stats, top categories, review button', (t) async {
        var reviewed = 0;
        final l = await pump(
          t,
          screen: ImportDoneScreen(
            outcome: const ImportOutcome(
              imported: 143,
              autoCategorised: 131,
              needReview: 11,
            ),
            cardName: 'CIB',
            onReview: () => reviewed++,
          ),
        );
        expect(find.text(l.importFlowDoneAuto), findsOneWidget);
        expect(find.text(l.importFlowDoneReview), findsOneWidget);
        expect(find.text(l.importFlowDoneBubble), findsOneWidget);
        await t.tap(find.text(l.importFlowDoneReviewButton(11, d(11))));
        expect(reviewed, 1);
      });

      testWidgets('done without stats hides the tiles', (t) async {
        final l = await pump(
          t,
          screen: const ImportDoneScreen(outcome: ImportOutcome(imported: 3)),
        );
        expect(find.text(l.importFlowDoneAuto), findsNothing);
        expect(find.text(l.importFlowDoneFromFile), findsOneWidget);
        expect(find.text(l.commonActionDone), findsOneWidget);
      });
    });
  }
}
