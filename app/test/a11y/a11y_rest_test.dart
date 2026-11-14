// T-174 (batch 21): guideline + 1.3x sweep over the screens that had no
// expectA11yGuidelines yet. ar/en x light/dark x scale 1.0/1.3.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail_providers.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/compare.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/card_details_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_detail.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol/features/transfers/presentation/assign_sheet.dart';
import 'package:zaghlol/features/transfers/presentation/link_transfer_sheet.dart';
import 'package:zaghlol/features/transfers/presentation/split_sheet.dart';

import '../features/accounts/presentation/card_detail_test.dart' as detail;
import '../features/accounts/presentation/edit_card_test.dart' as edit;
import '../features/insights/presentation/charts/charts_test_support.dart';
import '../features/share_cards/share_studio_test.dart' as share;
import '../features/transfers/presentation/transfers_harness.dart' as xfer;
import '../support/a11y_guidelines.dart';
import '../support/ios_setup_host.dart';
import '../support/golden_matrix.dart';
import 'a11y_pumps.dart';

Future<void> main() async {
  await initDateFormatting();
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;

    final pumps = <String, Future<void> Function(WidgetTester)>{
      'account S-69': (t) => pumpAccountS69(t, v),
      'template builder': (t) => pumpTemplateBuilder(t, v),
      'card capture sheet': (t) => pumpCardCaptureSheet(t, v),
      'passphrase sheet': (t) => pumpPassphraseSheet(t, v),
      'home card filter sheet': (t) => pumpHomeCardFilterSheet(t, v),
    };
    pumps.forEach((name, pump) {
      testWidgets('$name a11y ${v.name}', (t) async {
        await pump(t);
        await expectA11yGuidelines(t);
      });
    });

    testWidgets('ios setup S-03 a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(iosSetupHost(lang, scale: v.textScale, dark: v.dark));
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('card detail a11y ${v.name}', (t) async {
      await detail.pumpDetail(
        t,
        overrides: detail.detailOverrides(),
        locale: v.locale,
        dark: v.dark,
        scale: v.textScale,
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('compare cards a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final cards = [
        CompareCard(
          accountId: 'a1',
          label: 'NBE',
          spend: detail.m(891000),
          byCategory: {'dining': detail.m(210000), 'groc': detail.m(300000)},
        ),
        CompareCard(
          accountId: 'a2',
          label: 'CIB',
          spend: detail.m(495000),
          byCategory: {'dining': detail.m(175000), 'groc': detail.m(140000)},
        ),
      ];
      await t.pumpWidget(
        detail.host(
          const CompareCardsScreen(),
          overrides: [
            compareDataProvider.overrideWith(
              (ref) async => CompareData(
                currencies: [detail.egp],
                currency: detail.egp,
                available: cards,
                cards: cards,
                categoryIds: const ['groc', 'dining'],
                period: ChartPeriod.month(2026, 11),
              ),
            ),
          ],
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('edit card a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        edit.host(
          CardDetailsScreen.create(
            kind: AccountKind.credit,
            institution: edit.banks.first,
          ),
          repo: edit.FakeRepo([]),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('charts a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          const ChartsScreen(),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: chartOverrides(),
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('gold charts a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 5200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          const ChartsScreen(),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: [...chartOverrides(), ...goldChartOverrides()],
        ),
      );
      ProviderScope.containerOf(t.element(find.byType(ChartsScreen)))
          .read(entitlementStateProvider.notifier)
          .applyVerified(verified: true, status: 'active');
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('chart detail a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        harness(
          const ChartDetailScreen(chart: ChartId.cashFlow, code: 'EGP'),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
          overrides: chartOverrides(),
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('share studio a11y ${v.name}', (t) async {
      await share.pumpStudio(
        t,
        locale: v.locale,
        dark: v.dark,
        scale: v.textScale,
      );
      await expectA11yGuidelines(t);
    });

    final sheets =
        <String, (xfer.FakePort, Future<Object?> Function(BuildContext))>{
          'split sheet': (
            xfer.FakePort(split: xfer.sampleSplit()),
            (c) => showSplitSheet(c, 'x1'),
          ),
          'assign sheet': (
            xfer.FakePort(assignData: xfer.sampleAssign()),
            (c) => showAssignSheet(c, 'in1'),
          ),
          'link transfer sheet': (
            xfer.FakePort(linkData: xfer.sampleLink()),
            (c) => showLinkTransferSheet(c, 'out1'),
          ),
        };
    sheets.forEach((name, s) {
      testWidgets('$name a11y ${v.name} ($lang)', (t) async {
        await xfer.pumpSheet(
          t,
          port: s.$1,
          open: s.$2,
          locale: v.locale,
          dark: v.dark,
          textScale: v.textScale,
        );
        await expectA11yGuidelines(t);
      });
    });
  }
}
