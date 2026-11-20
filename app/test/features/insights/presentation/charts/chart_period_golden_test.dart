@Tags(['golden'])
library;

// T-188 AC6: the period picker sheet and a 6-month view, ar + en, light +
// dark. PNGs are not committed (CI app-regen creates them).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/ui/z_sheet.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/domain/chart_period_selection.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_period_bar.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_period_text.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'charts_test_support.dart';

void main() {
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    for (final dark in [false, true]) {
      final name = '${locale.languageCode}_${dark ? 'dark' : 'light'}';

      testWidgets('period sheet golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            RepaintBoundary(
              key: const ValueKey('golden-root'),
              child: Builder(
                builder: (context) {
                  final lang = locale.languageCode;
                  final text = ChartPeriodText(
                    l: AppLocalizations.of(context),
                    lang: lang,
                    digits: DigitsMode.resolve(DigitsPref.auto, lang),
                    today: chartsToday,
                  );
                  final schedule = PaydaySchedule.single(25);
                  const selection = ChartPeriodSelection(
                    ChartPreset.last6Months,
                  );
                  return ZSheetBody(
                    title: text.l.insightsChartsPeriodSheetTitle,
                    child: ChartPeriodSheetBody(
                      current: selection,
                      currentPeriod: selection.resolve(chartsToday, schedule),
                      today: chartsToday,
                      schedule: schedule,
                      text: text,
                      onPick: (_) {},
                      onCustom: () {},
                    ),
                  );
                },
              ),
            ),
            locale: locale,
            dark: dark,
            overrides: chartOverrides(),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../../goldens/chart_period_sheet_$name.png'),
        );
      });

      testWidgets('six-month view golden $name', (tester) async {
        await initDateFormatting();
        await tester.binding.setSurfaceSize(const Size(390, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const RepaintBoundary(
              key: ValueKey('golden-root'),
              child: ChartsScreen(),
            ),
            locale: locale,
            dark: dark,
            overrides: chartOverrides(
              selection: const ChartPeriodSelection(ChartPreset.last6Months),
              cashFlow: ChartReady(weeklyCashFlowPoints()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('../../../../goldens/charts_6months_$name.png'),
        );
      });
    }
  }
}
