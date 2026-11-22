// QA BUG-012 (B57): the Charts screen opens on the alphabetically first
// currency with activity (`currenciesWithActivity` is `ORDER BY c`), not on
// the user's primary currency; the switcher also lists the primary last.
// Glossary: "Primary currency: the currency shown first in views";
// C-09 "currencies present, primary first". Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/ui/z_currency_switcher.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../features/insights/presentation/charts/charts_test_support.dart';

void main() {
  testWidgets('BUG-012 charts open on the primary currency (EGP), '
      'not AED', (tester) async {
    final egp = Currency.of('EGP');
    final aed = Currency.of('AED');
    await tester.binding.setSurfaceSize(const Size(390, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const ChartsScreen(),
        locale: const Locale('en'),
        overrides: [
          // What the repository returns: `ORDER BY c`.
          ...chartOverrides(currencies: [aed, egp]),
          primaryCurrencyProvider.overrideWith((ref) => Stream.value(egp)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final sw = tester.widget<ZCurrencySwitcher>(
      find.byType(ZCurrencySwitcher).first,
    );
    expect(sw.selected, 'EGP', reason: 'chips ${sw.codes}');
    expect(sw.codes.first, 'EGP', reason: 'primary first (C-09)');
  });
}
