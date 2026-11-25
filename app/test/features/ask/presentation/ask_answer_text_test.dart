// FU-178b: the list separator follows the locale, not a hard-coded comma.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
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
    hidden: false,
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

  group('cycle naming (D-82)', () {
    setUpAll(initDateFormatting);
    final spend = AskSpendAnswer(
      target: AskTarget.everything,
      period: ChartPeriod(CivilDate(2026, 11, 24), CivilDate(2026, 12, 23)),
      periodDefaulted: false,
      figures: [Money(egp, 7000)],
    );

    String text(String lang, {PaydaySchedule? schedule}) =>
        AskAnswerTextBuilder(
          l: lookupAppLocalizations(Locale(lang)),
          languageCode: lang,
          digits: DigitsMode.western,
          hidden: false,
          today: CivilDate(2026, 11, 25),
          categoryNames: const {},
          schedule: schedule,
        ).build(spend).lines.single;

    test('with payday 24 the current cycle reads as "this month"', () {
      final en = text('en', schedule: PaydaySchedule.single(24));
      expect(en, contains('this month'));
      expect(
        text('ar', schedule: PaydaySchedule.single(24)),
        contains('الشهر ده'),
      );
    });

    test('without a schedule the dates are shown', () {
      expect(text('en'), isNot(contains('this month')));
    });
  });
}
