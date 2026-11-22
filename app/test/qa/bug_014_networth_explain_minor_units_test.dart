// QA BUG-014 (B57): "Explain this chart" for the net-worth chart prints the
// raw minor units: a net worth of EGP 1,234.50 (123450 minor) reads
// "123450 EGP" (100x too big, no grouping, no decimal). `UnitAmountArg` is
// rendered as `digits.render('$minor $unit')` in chart_explain_l10n.dart.
// Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/insights/domain/explanations.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_l10n.dart';

import '../support/hide_amounts_support.dart';

void main() {
  testWidgets('BUG-014 net worth explanation amount is in major units', (
    t,
  ) async {
    String? out;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ...amountsShown(),
          digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              final f = ExplainFormat.of(
                context,
                ref,
                (_) => '',
                now: '',
                prev: '',
              );
              out = f.arg(const UnitAmountArg('EGP', 123450));
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(out, contains('1,234.5'), reason: 'rendered as "$out"');
  });
}
