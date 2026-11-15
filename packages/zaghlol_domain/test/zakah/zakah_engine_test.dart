import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final sar = Currency.of('SAR');
final jpy = Currency.of('JPY');
final kwd = Currency.of('KWD');

CivilDate d(int y, int m, int day) => CivilDate(y, m, day);
final today = d(2026, 11, 15);
CivilDate ago(int days) => today.plusDays(-days);

Money egpM(String s) => Money.parse(s, egp);

/// Rates as numerator/denominator of the target per source unit (exact).
final _rates = <String, (int, int)>{
  'USD>EGP': (4950, 100),
  'SAR>EGP': (1320, 100),
};

ZakahMarket market({
  Map<String, String?> gold = const {
    'XAU24_G': '4280',
    'XAU21_G': '3750',
    'XAU18_G': '3210',
  },
  bool fx = true,
}) => ZakahMarket(
  goldPrice: (s) {
    final p = gold[s];
    return p == null ? null : Money.parse(p, egp);
  },
  convert: (m, to) {
    if (m.currency == to) return m;
    if (!fx) return null;
    final r = _rates['${m.currency.code}>${to.code}'];
    if (r == null) return null;
    // minor units of the source -> minor units of the target (EGP, USD, SAR
    // all have exponent 2 in this test).
    return m
        .mulDiv(r.$1, r.$2, MoneyRounding.halfEven)
        .let((x) => Money(to, x.minor));
  },
);

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

ZakahLot gold(String id, String sym, int grams, int daysHeld, {int paid = 0}) =>
    ZakahLot(
      id: id,
      kind: ZakahLotKind.gold,
      unit: sym,
      amount: grams * 1000,
      hawlStart: ago(daysHeld),
      paid: paid,
    );

ZakahLot cashLot(
  String id,
  Currency c,
  int minor,
  int daysHeld, {
  ZakahLotKind kind = ZakahLotKind.cash,
  bool zakatable = true,
  int paid = 0,
}) => ZakahLot(
  id: id,
  kind: kind,
  unit: c.code,
  amount: minor,
  hawlStart: ago(daysHeld),
  zakatable: zakatable,
  paid: paid,
);

ZakahResult run(
  List<ZakahLot> lots, {
  List<Money> debts = const [],
  ZakahMarket? m,
  ZakahRules rules = const ZakahRules(),
}) => computeZakah(
  lots: lots,
  debts: debts,
  today: today,
  market: m ?? market(),
  costCurrency: egp,
  rules: rules,
);

ZakahLotResult lot(ZakahResult r, String id) =>
    r.lots.firstWhere((l) => l.lotId == id);

void main() {
  group('spec section 11 table', () {
    final lots = [
      gold('g24', 'XAU24_G', 50, 390),
      gold('g21', 'XAU21_G', 120, 410),
      gold('g18', 'XAU18_G', 40, 120),
      cashLot('usdCash', usd, 800000, 365),
      cashLot('usdStock', usd, 400000, 365, kind: ZakahLotKind.stock),
      cashLot('sar', sar, 1200000, 360),
      cashLot('egx', egp, 10000000, 100, kind: ZakahLotKind.stock),
      cashLot('egp', egp, 24000000, 400),
    ];
    final r = run(lots, debts: [egpM('20000')]);

    test('nisab is 85 g of 24K and wealth meets it', () {
      expect(r.state, ZakahNisabState.eligible);
      expect(r.nisab, egpM('363800'));
    });

    test('24K bars: 50 g -> 1.25 g, 5,350 EGP', () {
      final x = lot(r, 'g24');
      expect(x.status, ZakahLotStatus.due);
      expect(x.hawlDaysElapsed, 390);
      expect(x.dueNative, 1250); // milligrams
      expect(x.costOfDue, egpM('5350'));
    });

    test('21K: 120 g -> 3.00 g, 11,250 EGP; counts as 105 g of 24K', () {
      final x = lot(r, 'g21');
      expect(x.dueNative, 3000);
      expect(x.costOfDue, egpM('11250'));
      final only = run([gold('g21', 'XAU21_G', 120, 410)]);
      expect(only.wealth, egpM('449400')); // 105 g x 4,280
    });

    test('18K not due: hawl 120/354, 1.00 g in 234 days, future 3,210', () {
      final x = lot(r, 'g18');
      expect(x.status, ZakahLotStatus.notDue);
      expect(x.dueNative, 0);
      expect(x.costOfDue, isNull);
      expect(x.daysRemaining, 234);
      expect(x.projectedDueNative, 1000);
      expect(x.projectedCost, egpM('3210'));
      expect(x.dueOn, ago(120).plusDays(354));
    });

    test('USD cash 8,000 + stocks 4,000: 200 + 100 = 300 USD, 14,850 EGP', () {
      final a = lot(r, 'usdCash');
      final b = lot(r, 'usdStock');
      expect(a.dueNative, 20000);
      expect(b.dueNative, 10000);
      expect(a.costOfDue! + b.costOfDue!, egpM('14850'));
      expect(r.dueByUnit['USD'], 30000);
    });

    test('SAR 12,000 -> 300 SAR, 3,960 EGP', () {
      final x = lot(r, 'sar');
      expect(x.dueNative, 30000);
      expect(x.costOfDue, egpM('3960'));
    });

    test('EGX trading stocks 100,000 EGP: 2,500 once hawl completes', () {
      expect(lot(r, 'egx').status, ZakahLotStatus.notDue);
      expect(lot(r, 'egx').projectedDueNative, 250000);
      final done = run([
        cashLot('egx', egp, 10000000, 354, kind: ZakahLotKind.stock),
        gold('g24', 'XAU24_G', 100, 0),
      ]);
      expect(lot(done, 'egx').dueNative, 250000);
      expect(lot(done, 'egx').costOfDue, egpM('2500'));
    });

    test('EGP cash 240,000 - 20,000 debt = 220,000 -> 5,500', () {
      final x = lot(r, 'egp');
      expect(x.netBase, 22000000);
      expect(x.dueNative, 550000);
      expect(x.costOfDue, egpM('5500'));
    });

    test('units never merge in dueByUnit', () {
      expect(r.dueByUnit.keys.toSet(), {
        'XAU24_G',
        'XAU21_G',
        'USD',
        'SAR',
        'EGP',
      });
      expect(r.dueByUnit['XAU24_G'], 1250);
    });
  });

  group('hawl', () {
    final big = gold('big', 'XAU24_G', 100, 0);
    test('353 days is not due, 354 is (boundary)', () {
      expect(
        lot(run([gold('a', 'XAU24_G', 100, 353)]), 'a').status,
        ZakahLotStatus.notDue,
      );
      final r = run([gold('a', 'XAU24_G', 100, 354)]);
      expect(lot(r, 'a').status, ZakahLotStatus.due);
      expect(lot(r, 'a').daysRemaining, 0);
    });

    test('a start date in the future counts as 0 days', () {
      final x = lot(
        run([
          ZakahLot(
            id: 'f',
            kind: ZakahLotKind.gold,
            unit: 'XAU24_G',
            amount: 100000,
            hawlStart: today.plusDays(5),
          ),
        ]),
        'f',
      );
      expect(x.hawlDaysElapsed, 0);
      expect(x.daysRemaining, 354);
    });

    test('continuation: next hawl starts at the due date', () {
      final start = ago(400);
      final next = nextHawlStart(start, const ZakahRules());
      expect(next, start.plusDays(354));
      final r = run([
        ZakahLot(
          id: 'c',
          kind: ZakahLotKind.gold,
          unit: 'XAU24_G',
          amount: 100000,
          hawlStart: next,
        ),
      ]);
      expect(lot(r, 'c').hawlDaysElapsed, 46);
      expect(lot(r, 'c').status, ZakahLotStatus.notDue);
    });

    test('hawl length is a parameter', () {
      final r = run([
        gold('a', 'XAU24_G', 100, 355),
        big,
      ], rules: const ZakahRules(hawlDays: 365));
      expect(lot(r, 'a').status, ZakahLotStatus.notDue);
    });

    test('hawl is counted per lot; a young lot does not delay an old one', () {
      final r = run([
        gold('old', 'XAU24_G', 100, 500),
        gold('new', 'XAU24_G', 100, 1),
      ]);
      expect(lot(r, 'old').status, ZakahLotStatus.due);
      expect(lot(r, 'new').status, ZakahLotStatus.notDue);
    });
  });

  group('nisab', () {
    test('84.9 g of 24K is below nisab even with hawl done: no dues', () {
      final r = run(
        [gold('a', 'XAU24_G', 0, 400)]
          ..clear()
          ..add(
            ZakahLot(
              id: 'a',
              kind: ZakahLotKind.gold,
              unit: 'XAU24_G',
              amount: 84900,
              hawlStart: ago(400),
            ),
          ),
      );
      expect(r.state, ZakahNisabState.belowNisab);
      expect(lot(r, 'a').status, ZakahLotStatus.belowNisab);
      expect(lot(r, 'a').dueNative, 0);
      expect(r.dueByUnit, isEmpty);
    });

    test('exactly 85 g meets nisab (>=)', () {
      final r = run([
        ZakahLot(
          id: 'a',
          kind: ZakahLotKind.gold,
          unit: 'XAU24_G',
          amount: 85000,
          hawlStart: ago(400),
        ),
      ]);
      expect(r.state, ZakahNisabState.eligible);
      expect(lot(r, 'a').dueNative, 2125);
    });

    test('nisab is combined across lots and units', () {
      // 40 g 24K (171,200) + 200,000 EGP cash = 371,200 >= 363,800
      final r = run([
        gold('a', 'XAU24_G', 40, 400),
        cashLot('c', egp, 20000000, 400),
      ]);
      expect(r.state, ZakahNisabState.eligible);
      expect(r.wealth, egpM('371200'));
    });

    test('lots still in hawl count toward nisab', () {
      final r = run([
        gold('old', 'XAU24_G', 40, 400),
        gold('new', 'XAU24_G', 50, 10),
      ]);
      expect(r.state, ZakahNisabState.eligible);
      expect(lot(r, 'old').status, ZakahLotStatus.due);
    });

    test('debt can push wealth below nisab', () {
      final r = run([cashLot('c', egp, 40000000, 400)], debts: [egpM('40000')]);
      expect(r.state, ZakahNisabState.belowNisab); // 360,000 < 363,800
      expect(r.dueByUnit, isEmpty);
    });

    test('non-zakatable lots are excluded and not counted', () {
      final r = run([
        cashLot('c', egp, 50000000, 400, zakatable: false),
        gold('g', 'XAU24_G', 10, 400),
      ]);
      expect(lot(r, 'c').status, ZakahLotStatus.excluded);
      expect(r.state, ZakahNisabState.belowNisab);
    });

    test('8 g coin counts as 8 g of 21K; due in coins', () {
      // 13 coins = 104 g 21K = 91 g 24K -> eligible. due 0.325 coin.
      final r = run([
        ZakahLot(
          id: 'coin',
          kind: ZakahLotKind.gold,
          unit: 'XAU_COIN8G',
          amount: 13000,
          hawlStart: ago(400),
        ),
      ], m: market(gold: {'XAU24_G': '4280', 'XAU_COIN8G': '30000'}));
      expect(r.wealth, egpM('389480')); // 91 x 4,280
      expect(lot(r, 'coin').dueNative, 325);
      expect(lot(r, 'coin').costOfDue, egpM('9750'));
    });
  });

  group('debts (BR-ZAK-04)', () {
    test('deduct from cash of the same currency only', () {
      final r = run(
        [cashLot('egp', egp, 40000000, 400), cashLot('usd', usd, 1000000, 400)],
        debts: [Money.parse('100000', usd)],
      );
      expect(lot(r, 'usd').netBase, 0); // capped at that cash
      expect(lot(r, 'egp').netBase, 40000000); // not touched
    });

    test('oldest cash lot absorbs the debt first', () {
      final r = run(
        [
          cashLot('young', egp, 30000000, 100),
          cashLot('old', egp, 30000000, 400),
        ],
        debts: [egpM('350000')],
      );
      expect(lot(r, 'old').netBase, 0);
      expect(lot(r, 'young').netBase, 25000000);
    });

    test('debt is not deducted from gold or stocks', () {
      final r = run(
        [cashLot('s', egp, 40000000, 400, kind: ZakahLotKind.stock)],
        debts: [egpM('1000')],
      );
      expect(lot(r, 's').netBase, 40000000);
    });

    test('negative debt is refused', () {
      expect(() => run([], debts: [egpM('-1')]), throwsArgumentError);
    });
  });

  group('rounding per currency exponent', () {
    ZakahResult cashRun(Currency c, int minor, {ZakahRules? rules}) => run([
      cashLot('c', c, minor, 400),
      gold('g', 'XAU24_G', 1000, 400),
    ], rules: rules ?? const ZakahRules());

    test('EGP 2 decimals: 100.10 -> 2.5025 -> 2.50', () {
      expect(lot(cashRun(egp, 10010), 'c').dueNative, 250);
    });
    test(
      'JPY 0 decimals: 1,001 -> 25.025 -> 25; 1,020 -> 25.5 -> 26 (even)',
      () {
        final m = ZakahMarket(
          goldPrice: (s) => s == 'XAU24_G' ? egpM('4280') : null,
          convert: (a, to) => a.currency == to ? a : egpM('1'),
        );
        expect(
          lot(
            run([
              cashLot('c', jpy, 1001, 400),
              gold('g', 'XAU24_G', 1000, 400),
            ], m: m),
            'c',
          ).dueNative,
          25,
        );
        expect(
          lot(
            run([
              cashLot('c', jpy, 1020, 400),
              gold('g', 'XAU24_G', 1000, 400),
            ], m: m),
            'c',
          ).dueNative,
          26,
        );
      },
    );
    test('KWD 3 decimals: 1.001 KWD -> 0.025025 -> 0.025', () {
      final m = ZakahMarket(
        goldPrice: (s) => s == 'XAU24_G' ? egpM('4280') : null,
        convert: (a, to) => a.currency == to ? a : egpM('1'),
      );
      expect(
        lot(
          run([
            cashLot('c', kwd, 1001, 400),
            gold('g', 'XAU24_G', 1000, 400),
          ], m: m),
          'c',
        ).dueNative,
        25,
      );
    });
    test('rounding mode is a parameter (ceil)', () {
      final r = cashRun(
        egp,
        10010,
        rules: const ZakahRules(rounding: MoneyRounding.ceil),
      );
      expect(lot(r, 'c').dueNative, 251);
    });
    test('gold rounds to the milligram: 33.333 g -> 833.325 mg -> 833', () {
      final r = run([
        ZakahLot(
          id: 'a',
          kind: ZakahLotKind.gold,
          unit: 'XAU24_G',
          amount: 100001,
          hawlStart: ago(400),
        ),
      ]);
      expect(lot(r, 'a').dueNative, 2500); // 2500.025 mg
    });
  });

  group('ledger status (FR-ZAK-04)', () {
    test('pending / partial / paid, remaining never negative', () {
      ZakahLotResult one(int paid) =>
          lot(run([gold('a', 'XAU24_G', 100, 400, paid: paid)]), 'a');
      expect(one(0).payment, ZakahPayment.pending);
      expect(one(0).remainingNative, 2500);
      expect(one(1000).payment, ZakahPayment.partial);
      expect(one(1000).remainingNative, 1500);
      expect(one(2500).payment, ZakahPayment.paid);
      expect(one(9000).remainingNative, 0);
    });
    test('paid lot leaves dueByUnit', () {
      expect(
        run([gold('a', 'XAU24_G', 100, 400, paid: 2500)]).dueByUnit,
        isEmpty,
      );
    });
  });

  group('missing prices fail closed', () {
    test('no 24K price: needsPrices, no dues', () {
      final r = run([gold('a', 'XAU24_G', 100, 400)], m: market(gold: {}));
      expect(r.state, ZakahNisabState.needsPrices);
      expect(r.nisab, isNull);
      expect(lot(r, 'a').dueNative, 0);
      expect(lot(r, 'a').status, ZakahLotStatus.needsPrices);
    });
    test('currency lot without a rate: needsPrices, never summed blindly', () {
      final r = run([
        gold('a', 'XAU24_G', 100, 400),
        cashLot('u', usd, 100000, 400),
      ], m: market(fx: false));
      expect(r.state, ZakahNisabState.needsPrices);
      expect(r.dueByUnit, isEmpty);
    });
    test('cost is null (not guessed) without a rate or a karat price', () {
      final r = run([
        gold('a', 'XAU21_G', 120, 400),
        cashLot('u', usd, 100000, 400),
      ], m: market(gold: {'XAU24_G': '4280'}));
      expect(r.state, ZakahNisabState.eligible);
      expect(lot(r, 'a').dueNative, 3000);
      expect(lot(r, 'a').costOfDue, isNull);
    });
  });

  group('validation and limits', () {
    test('gold lot with a currency unit is refused', () {
      expect(
        () => ZakahLot(
          id: 'x',
          kind: ZakahLotKind.gold,
          unit: 'EGP',
          amount: 1,
          hawlStart: today,
        ),
        throwsArgumentError,
      );
      expect(
        () => ZakahLot(
          id: 'x',
          kind: ZakahLotKind.cash,
          unit: 'XAU24_G',
          amount: 1,
          hawlStart: today,
        ),
        throwsArgumentError,
      );
    });
    test('unknown karat and negative amount are refused', () {
      expect(
        () => ZakahLot(
          id: 'x',
          kind: ZakahLotKind.gold,
          unit: 'XAU99_G',
          amount: 1,
          hawlStart: today,
        ),
        throwsArgumentError,
      );
      expect(() => cashLot('x', egp, -1, 1), throwsArgumentError);
    });
    test('overflow is a typed code', () {
      final lots = [
        cashLot('a', egp, Money.maxMinor, 400),
        cashLot('b', egp, Money.maxMinor, 400),
      ];
      expect(() => run(lots), throwsA(isA<ZakahOverflow>()));
    });
    test('no lots: below nisab, empty', () {
      final r = run([]);
      expect(r.state, ZakahNisabState.belowNisab);
      expect(r.lots, isEmpty);
    });
  });

  group('hijri (display only)', () {
    test('tabular conversion, month 1..12 and day 1..30', () {
      // 1 Muharram 1446 AH is 2024-07-07 (UQ) / 2024-07-07 or 08 (tabular).
      final h = hijriFromCivil(d(2024, 7, 8));
      expect(h.year, 1446);
      expect(h.month, 1);
      expect(h.day, inInclusiveRange(1, 2));
      for (var i = 0; i < 1500; i++) {
        final x = hijriFromCivil(d(2020, 1, 1).plusDays(i));
        expect(x.month, inInclusiveRange(1, 12));
        expect(x.day, inInclusiveRange(1, 30));
      }
      expect(
        hijriFromCivil(d(2026, 11, 15)).toIso(),
        matches(r'^\d{4}-\d\d-\d\d$'),
      );
    });
    test('before the epoch is refused', () {
      expect(() => hijriFromCivil(d(600, 1, 1)), throwsArgumentError);
    });
  });
}
