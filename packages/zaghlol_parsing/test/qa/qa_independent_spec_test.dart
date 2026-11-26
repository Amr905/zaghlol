// Zaghlol QA: independent spec-example tests (written by QA from the SRS examples, not by the developers).
// Each test quotes the requirement, business rule, edge case or decision it checks.
// Run: `dart test test/qa/qa_independent_spec_test.dart` in packages/zaghlol_parsing.
import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');

Money m(String s, [Currency? c]) => Money.parse(s, c ?? egp);

int? minorOf(Result<Money, ParseFailure> r) => switch (r) {
  Ok(:final value) => value.minor,
  Err() => null,
};

String? codeOf(Result<Money, ParseFailure> r) => switch (r) {
  Ok(:final value) => value.currency.code,
  Err() => null,
};

void main() {
  group('Budget and payday', () {
    test('TC-BUD-001 FR-BUD-01: payday 25 gives cycle 25 Oct to 24 Nov', () {
      final c = PaydaySchedule.single(25).cycleOn(CivilDate(2026, 10, 30));
      expect(c.start, CivilDate(2026, 10, 25));
      expect(c.end, CivilDate(2026, 11, 24));
    });
    test('TC-BUD-002 BR-BUD-01: payday accepts 1..28 only', () {
      expect(() => PaydaySchedule.single(29), throwsArgumentError);
      expect(() => PaydaySchedule.single(0), throwsArgumentError);
      expect(() => PaydaySchedule.single(31), throwsArgumentError);
      expect(PaydaySchedule.single(28).currentDay, 28);
      expect(PaydaySchedule.single(1).currentDay, 1);
    });
    test(
      'TC-BUD-003 payday 28 across February in a leap and a non-leap year',
      () {
        final s = PaydaySchedule.single(28);
        expect(s.cycleOn(CivilDate(2027, 2, 27)).end, CivilDate(2027, 2, 27));
        expect(s.cycleOn(CivilDate(2027, 2, 28)).start, CivilDate(2027, 2, 28));
        expect(s.cycleOn(CivilDate(2028, 2, 29)).start, CivilDate(2028, 2, 28));
        expect(s.cycleOn(CivilDate(2026, 12, 31)).end, CivilDate(2027, 1, 27));
      },
    );
    test(
      'TC-BUD-004 FR-BUD-04 / BR-BUD-03: 2,200 left and 7 days gives 314 a day',
      () {
        final cycle = PaydaySchedule.single(25)
            .cycleOn(CivilDate(2026, 11, 18));
        final today = CivilDate(
          2026,
          11,
          18,
        ); // 18..24 = 7 days including today
        expect(cycle.daysRemaining(today), 7);
        final s = safeToSpend(
          budget: m('5000.00'),
          spend: m('2800.00'),
          cycle: cycle,
          today: today,
        );
        expect(s, m('314.28'));
      },
    );
    test('TC-BUD-005 EC-24: zero budget hides safe-to-spend; overspent shows zero, never negative', () {
      final cycle = PaydaySchedule.single(1).cycleOn(CivilDate(2026, 11, 10));
      final today = CivilDate(2026, 11, 10);
      expect(
        safeToSpend(
          budget: m('0.00'),
          spend: m('10.00'),
          cycle: cycle,
          today: today,
        ),
        isNull,
      );
      expect(
        safeToSpend(
          budget: null,
          spend: m('10.00'),
          cycle: cycle,
          today: today,
        ),
        isNull,
      );
      expect(
        safeToSpend(
          budget: m('100.00'),
          spend: m('250.00'),
          cycle: cycle,
          today: today,
        ),
        m('0.00'),
      );
    });
    test(
      'TC-BUD-006 last day of the cycle: all that is left is safe today',
      () {
        final cycle = PaydaySchedule.single(1).cycleOn(CivilDate(2026, 11, 30));
        expect(
          safeToSpend(
            budget: m('900.00'),
            spend: m('600.00'),
            cycle: cycle,
            today: CivilDate(2026, 11, 30),
          ),
          m('300.00'),
        );
      },
    );
    test('TC-BUD-007 BR-BUD-04: ideal burn on day d = budget x d / length', () {
      expect(idealBurn(m('3000.00'), 10, 30), m('1000.00'));
      expect(idealBurn(m('3000.00'), 0, 30), m('0.00'));
      expect(idealBurn(m('3000.00'), 30, 30), m('3000.00'));
      expect(() => idealBurn(m('3000.00'), 31, 30), throwsRangeError);
    });
    test('TC-BUD-008 D-82: a cycle starting on day 21..28 is named as the next month', () {
      expect(cycleLabelMonth(CivilDate(2026, 11, 24)), (year: 2026, month: 12));
      expect(cycleLabelMonth(CivilDate(2026, 11, 21)), (year: 2026, month: 12));
      expect(cycleLabelMonth(CivilDate(2026, 11, 20)), (year: 2026, month: 11));
      expect(cycleLabelMonth(CivilDate(2026, 11, 1)), (year: 2026, month: 11));
      expect(cycleLabelMonth(CivilDate(2026, 12, 25)), (year: 2027, month: 1));
    });
    test('TC-BUD-009 EC-21: payday changed mid-cycle: current cycle ends early, new one starts next payday', () {
      final s = PaydaySchedule.single(25)
          .withChange(CivilDate(2026, 11, 10), 15);
      expect(
        s.cycleOn(CivilDate(2026, 11, 12)),
        Cycle(start: CivilDate(2026, 10, 25), end: CivilDate(2026, 11, 14)),
      );
      expect(s.cycleOn(CivilDate(2026, 11, 15)).start, CivilDate(2026, 11, 15));
      expect(s.cycleOn(CivilDate(2026, 11, 15)).end, CivilDate(2026, 12, 14));
      // history before the change is not rewritten
      expect(
        s.cycleOn(CivilDate(2026, 10, 1)),
        PaydaySchedule.single(25).cycleOn(CivilDate(2026, 10, 1)),
      );
    });
  });

  group('Money', () {
    test('TC-MON-001 BR-MON-03: ISO exponents (KWD/BHD/OMR/JOD/TND/LYD/IQD 3; JPY/KRW 0; CLF/UYW 4)', () {
      for (final c in ['KWD', 'BHD', 'OMR', 'JOD', 'TND', 'LYD', 'IQD']) {
        expect(Currency.of(c).exponent, 3, reason: c);
      }
      for (final c in ['JPY', 'KRW']) {
        expect(Currency.of(c).exponent, 0, reason: c);
      }
      for (final c in ['CLF', 'UYW']) {
        expect(Currency.of(c).exponent, 4, reason: c);
      }
      for (final c in [
        'EGP',
        'USD',
        'SAR',
        'EUR',
        'AED',
        'QAR',
        'GBP',
        'INR',
      ]) {
        expect(Currency.of(c).exponent, 2, reason: c);
      }
    });
    test('TC-MON-002 FR-TXN-04: KWD 1.250, BHD 0.375, JPY 1500 keep their decimals', () {
      expect(Money.parse('1.250', kwd).minor, 1250);
      expect(Money.parse('0.375', Currency.of('BHD')).minor, 375);
      expect(Money.parse('1500', Currency.of('JPY')).minor, 1500);
      expect(Money.parse('1.250', kwd).toCanonicalString(), '1.250');
    });
    test(
      'TC-MON-003 BR-FX-02: adding two currencies is refused, never converted',
      () {
        expect(() => m('1.00') + Money.parse('1.00', usd), throwsA(anything));
      },
    );
    test('TC-MON-004 D-51 / D-67: metals and accounting units are not currencies here', () {
      for (final c in ['XAU', 'XAG', 'XDR', 'XAD', 'XXX', 'XTS']) {
        expect(Currency.tryOf(c), isNull, reason: c);
      }
      expect(Currency.tryOf('BOV'), isNotNull);
    });
    test('TC-MON-005 equal split adds up exactly', () {
      final parts = equalSplit(m('100.00'), 3);
      expect(parts.map((p) => p.minor).toList(), [3334, 3333, 3333]);
    });
  });

  group('Transfers, splits, reimbursements', () {
    test('TC-XFR-001 FR-XFR-04 / BR-XFR-04: paid 1,200, received 800: net 400, never below zero', () {
      expect(netOfOffsets(m('1200.00'), m('800.00')), m('400.00'));
      expect(netOfOffsets(m('1200.00'), m('1500.00')), m('0.00'));
    });
    test(
      'TC-XFR-002 FR-XFR-07: 1,200 bill + 400 + 400 gives own share 400',
      () {
        expect(ownShare(m('1200.00'), [m('400.00'), m('400.00')]), m('400.00'));
      },
    );
    TransferLeg leg(String id, String acc, bool out, String amt, DateTime at) =>
        TransferLeg(
          id: id,
          accountId: acc,
          isOut: out,
          amount: m(amt),
          occurredAt: at,
        );
    final t0 = DateTime.utc(2026, 11, 1, 12);
    test('TC-XFR-003 FR-XFR-01 / BR-XFR-01: -1,000 NBE and +1,000 CIB within 2 minutes pair', () {
      final a = leg('a', 'nbe', true, '1000.00', t0);
      final b = leg(
        'b',
        'cib',
        false,
        '1000.00',
        t0.add(const Duration(minutes: 2)),
      );
      expect(decideSameCurrency(a, [b]), isA<PairWith>());
    });
    test('TC-XFR-003b BUG-019 (fixed): the documented contract "pool may contain leg; it is ignored" holds', () {
      final a = leg('a', 'nbe', true, '1000.00', t0);
      final b = leg(
        'b',
        'cib',
        false,
        '1000.00',
        t0.add(const Duration(minutes: 2)),
      );
      expect(decideSameCurrency(a, [a, b]), isA<PairWith>());
    });
    test('TC-XFR-004 BR-XFR-01: no pair after 5 minutes, on the same account, or with a different amount', () {
      final a = leg('a', 'nbe', true, '1000.00', t0);
      expect(
        decideSameCurrency(a, [
          a,
          leg(
            'b',
            'cib',
            false,
            '1000.00',
            t0.add(const Duration(minutes: 5, seconds: 1)),
          ),
        ]),
        isA<NoMatch>(),
      );
      expect(
        decideSameCurrency(a, [a, leg('b', 'nbe', false, '1000.00', t0)]),
        isA<NoMatch>(),
      );
      expect(
        decideSameCurrency(a, [a, leg('b', 'cib', false, '1000.01', t0)]),
        isA<NoMatch>(),
      );
      expect(
        decideSameCurrency(a, [a, leg('b', 'cib', true, '1000.00', t0)]),
        isA<NoMatch>(),
      );
    });
    test('TC-XFR-005 BR-XFR-02 / EC-16: two candidates of the same amount: ask, do not pair', () {
      final a = leg('a', 'nbe', true, '1000.00', t0);
      final b = leg(
        'b',
        'cib',
        false,
        '1000.00',
        t0.add(const Duration(minutes: 1)),
      );
      final c = leg(
        'c',
        'qnb',
        false,
        '1000.00',
        t0.add(const Duration(minutes: 2)),
      );
      expect(decideSameCurrency(a, [a, b, c]), isA<AmbiguousMatch>());
    });
    test('TC-XFR-006 FR-CUR-06: cross-currency within 3 % and 3 days is only a candidate', () {
      expect(withinTolerance(m('4895.00'), m('4990.00'), 300), isTrue);
      expect(withinTolerance(m('4895.00'), m('5100.00'), 300), isFalse);
    });
  });

  group('Mascot rules', () {
    test('TC-MAS-001 BR-MAS-01: over 85 % before day 20 shocks; at 85 % or on day 20 it does not', () {
      MascotCandidate? f(int spent, int day, [String cat = 'sys:dining']) =>
          budgetShocked(
            categoryId: cat,
            spentMinor: spent,
            limitMinor: 100000,
            dayOfCycle: day,
            cycleId: 'c',
          );
      expect(f(86000, 19)?.pose, MascotPose.shocked);
      expect(f(85000, 19), isNull);
      expect(f(99000, 20), isNull);
    });
    test('TC-MAS-002 Q-25: essential categories are never roasted', () {
      for (final cat in ['sys:groceries', 'sys:health', 'sys:education']) {
        expect(
          budgetShocked(
            categoryId: cat,
            spentMinor: 99000,
            limitMinor: 100000,
            dayOfCycle: 5,
            cycleId: 'c',
          ),
          isNull,
          reason: cat,
        );
      }
    });
    test('TC-MAS-003 BR-MAS-03: same merchant, amount and card within 10 minutes is a duplicate', () {
      PosDebit d(int at, {String card = 'k1', int amt = 5000}) => PosDebit(
        merchantId: 'm1',
        cardId: card,
        currency: 'EGP',
        amountMinor: amt,
        atUtcMs: at,
      );
      expect(duplicatePos(d(600000), [d(0)])?.pose, MascotPose.detective);
      expect(duplicatePos(d(600001), [d(0)]), isNull);
      expect(duplicatePos(d(1000, card: 'k2'), [d(0)]), isNull);
      expect(duplicatePos(d(1000, amt: 5001), [d(0)]), isNull);
    });
  });

  group('Zakah (flag off at launch)', () {
    test('TC-ZAK-001 BR-ZAK-01: nisab = 85 g of 24K', () {
      expect(nisabValue(m('4000.00'), const ZakahRules()), m('340000.00'));
    });
    test('TC-ZAK-002 BR-ZAK-02: hawl is 354 days', () {
      expect(
        nextHawlStart(CivilDate(2026, 1, 1), const ZakahRules()),
        CivilDate(2026, 12, 21),
      );
    });
  });

  group('Amount parsing', () {
    test('TC-PAR-001 FR-PAR-04: Arabic-Indic digits and separators: ١٬٢٥٠٫٠٠ = 1250.00', () {
      expect(minorOf(parseAmount('١٬٢٥٠٫٠٠', currency: egp)), 125000);
      expect(
        minorOf(parseAmount('۱۲۵۰', currency: egp)),
        125000,
      ); // Persian digits
      expect(minorOf(parseAmount('1,250.5', currency: egp)), 125050);
    });
    test('TC-PAR-002 EC-36: KWD 12.345 keeps 3 decimals; EGP 12.345 is refused, never rounded', () {
      expect(minorOf(parseAmount('12.345', currency: kwd)), 12345);
      expect(minorOf(parseAmount('12.345', currency: egp)), isNull);
      expect(minorOf(parseAmount('12.340', currency: egp)), 1234);
    });
    test('TC-PAR-003 EC-50: 1.234 is 1,234 under EU grouping and 1.234 KWD under standard', () {
      expect(
        minorOf(parseAmount('1.234', currency: egp, locale: NumberLocale.eu)),
        123400,
      );
      expect(minorOf(parseAmount('1.234', currency: kwd)), 1234);
      expect(
        minorOf(
          parseAmount(
            '1.234,56',
            currency: Currency.of('EUR'),
            locale: NumberLocale.eu,
          ),
        ),
        123456,
      );
    });
    test('TC-PAR-004 EC-51: Indian grouping 1,23,456.78', () {
      expect(
        minorOf(parseAmount('1,23,456.78', currency: Currency.of('INR'))),
        12345678,
      );
    });
    test(
      'TC-PAR-005 FR-PAR-11: symbols and codes before or after the number',
      () {
        expect(codeOf(parseMoneyText(r'$20.00')), 'USD');
        expect(minorOf(parseMoneyText(r'$20.00')), 2000);
        expect(codeOf(parseMoneyText('20.00 USD')), 'USD');
        expect(codeOf(parseMoneyText('£15.50')), 'GBP');
        expect(codeOf(parseMoneyText('€ 9.99')), 'EUR');
        expect(codeOf(parseMoneyText('₹1,23,456.78')), 'INR');
        expect(minorOf(parseMoneyText('JPY 1500')), 1500);
        expect(minorOf(parseMoneyText('KWD 12.345')), 12345);
      },
    );
    test('TC-PAR-006 T-080: "12,5" is rejected, never read as 125', () {
      expect(minorOf(parseAmount('12,5', currency: egp)), isNull);
    });
    test(
      'TC-PAR-007 hostile or broken amounts never throw and never yield money',
      () {
        for (final s in [
          '',
          ' ',
          '.',
          ',',
          '٫',
          '1e5',
          '-5',
          '+5',
          '1,,2',
          '1..2',
          'NaN',
          '0x10',
          '١٢٣abc',
          '9' * 40,
          '1.2.3',
          '١٢٫٣٤٫٥',
        ]) {
          expect(
            minorOf(parseAmount(s, currency: egp)),
            isNull,
            reason: 'input "$s"',
          );
        }
        expect(minorOf(parseMoneyText('USD 20 EGP 1010')), isNull);
        expect(minorOf(parseMoneyText('20')), isNull);
      },
    );
    test('TC-PAR-008 tatweel and mixed digit systems normalise', () {
      expect(
        foldForMatching('جـــنيه'),
        'جنيه',
      ); // matching level drops tatweel; display level keeps it by design
      expect(minorOf(parseAmount('١2٣4', currency: egp)), 123400);
    });
  });

  group('Merchant cleaning', () {
    test('TC-PAR-009 FR-PAR-05: CARREFOUR MAADI EG 041 becomes Carrefour', () {
      final c = cleanMerchant('CARREFOUR MAADI EG 041');
      expect(c.key, 'carrefour');
      expect(c.display.toLowerCase(), 'carrefour');
    });
    test('TC-PAR-010 blank, noise-only and very long merchants are safe', () {
      expect(cleanMerchant('').key, '');
      expect(cleanMerchant('   ').key, '');
      expect(cleanMerchant('POS').key, isNotEmpty);
      expect(
        cleanMerchant('A' * 5000).key.length,
        lessThanOrEqualTo(merchantKeyMaxLength),
      );
    });
  });

  group('Voice', () {
    List<int?> amounts(VoiceParseResult r) => switch (r) {
      VoiceParsed(:final items) => [for (final i in items) i.amount?.minor],
      VoiceUnrecognized() => const [],
    };
    test('TC-VOI-001 FR-VOI-02: one phrase, three items: 150, 45, 30', () {
      final r = parseVoicePhrase(
        'دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي',
        defaultCurrency: egp,
      );
      expect(amounts(r), [15000, 4500, 3000]);
    });
    test('TC-VOI-002 FR-VOI-05: spoken Egyptian numbers', () {
      expect(
        amounts(
          parseVoicePhrase('ميت وخمسين جنيه بنزين', defaultCurrency: egp),
        ),
        [15000],
      );
      expect(
        amounts(
          parseVoicePhrase('ميتين وخمسين جنيه قهوة', defaultCurrency: egp),
        ),
        [25000],
      );
      expect(
        amounts(parseVoicePhrase('ألف ونص جنيه إيجار', defaultCurrency: egp)),
        [150000],
      );
    });
    test('TC-VOI-003 EC-31: mixed Arabic and English: دفعت 200 Uber', () {
      expect(amounts(parseVoicePhrase('دفعت 200 Uber', defaultCurrency: egp)), [
        20000,
      ]);
    });
    test('TC-VOI-004 EC-30: a phrase with no amount invents no amount', () {
      final r = parseVoicePhrase('اشتريت قهوة', defaultCurrency: egp);
      expect(amounts(r).whereType<int>(), isEmpty);
    });
    test('TC-VOI-005 very long or empty speech is refused, not crashed on', () {
      expect(
        parseVoicePhrase('', defaultCurrency: egp),
        isA<VoiceUnrecognized>(),
      );
      expect(
        parseVoicePhrase('قهوة ' * 50000, defaultCurrency: egp),
        isA<VoiceUnrecognized>(),
      );
    });
  });
}
