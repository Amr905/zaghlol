// FU-178b: the list separator follows the locale, not a hard-coded comma.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/presentation/ask_answer_text.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  final egp = Currency.of('EGP');
  final answer = AskTopMerchantsAnswer(
    period: ChartPeriod.month(2026, 11),
    periodDefaulted: false,
    byCurrency: [
      [
        for (final n in ['Alpha', 'Beta'])
          MerchantSpend(
            merchantNorm: n,
            name: n,
            amount: Money(egp, 1000),
            count: 1,
          ),
      ],
    ],
  );

  String line(String lang, DigitsMode d) => AskAnswerTextBuilder(
    l: lookupAppLocalizations(Locale(lang)),
    languageCode: lang,
    digits: d,
    today: CivilDate(2026, 11, 15),
    categoryNames: const {},
  ).build(answer).lines.single;

  test('English uses ", " and no Arabic comma', () {
    final s = line('en', DigitsMode.western);
    expect(s, contains(', Beta'));
    expect(s, isNot(contains('،')));
  });

  test('Arabic keeps the Arabic comma', () {
    expect(line('ar', DigitsMode.arabicIndic), contains('، '));
  });
}
