import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_components.dart';

Widget _wrap(Widget child, Locale locale, {double scale = 1}) => MaterialApp(
  theme: ZaghlolTheme.light,
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

void main() {
  for (final loc in const [Locale('ar'), Locale('en')]) {
    group(loc.languageCode, () {
      testWidgets('single currency shows no switcher (EC-55)', (t) async {
        await t.pumpWidget(
          _wrap(
            ZCurrencySwitcher(
              codes: const ['EGP'],
              selected: 'EGP',
              onSelected: (_) {},
            ),
            loc,
          ),
        );
        expect(find.byType(ZChip), findsNothing);
      });

      testWidgets('two currencies select, 1.3x scale, no overflow', (t) async {
        String? picked;
        await t.pumpWidget(
          _wrap(
            ZCurrencySwitcher(
              codes: const ['EGP', 'USD'],
              selected: 'EGP',
              onSelected: (c) => picked = c,
            ),
            loc,
            scale: 1.3,
          ),
        );
        await t.tap(find.text('USD'));
        expect(picked, 'USD');
        expect(t.takeException(), isNull);
      });

      testWidgets('approx row: date, stale and not-included note', (t) async {
        await t.pumpWidget(
          _wrap(
            const ZApproxRow(
              figureText: '100',
              rateDateText: '13',
              excludedCodes: ['JPY', 'KWD'],
              stale: true,
            ),
            loc,
            scale: 1.3,
          ),
        );
        expect(find.byKey(const Key('approx-rate-date')), findsOneWidget);
        expect(find.byKey(const Key('approx-stale')), findsOneWidget);
        expect(find.text('JPY · KWD'), findsOneWidget);
      });

      testWidgets('approx row without exclusions has no note', (t) async {
        await t.pumpWidget(
          _wrap(
            const ZApproxRow(
              figureText: '100',
              rateDateText: null,
              excludedCodes: [],
            ),
            loc,
          ),
        );
        expect(find.byKey(const Key('approx-not-included')), findsNothing);
      });
    });
  }
}
