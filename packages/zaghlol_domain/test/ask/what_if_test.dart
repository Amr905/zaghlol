import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money e(String s) => Money.parse(s, egp);

WhatIfCutResult res(WhatIfCutOutcome o) => o as WhatIfCutResult;

void main() {
  final periods = [e('3000'), e('3200'), e('3400')];

  test('AC1 dining 50% x 12 -> 19200.00', () {
    final r = res(
      whatIfCut(
        spendPerFullPeriod: periods,
        mode: const WhatIfPercent(50),
        months: 12,
      ),
    );
    expect(r.base, e('3200'));
    expect(r.monthlySaving, e('1600'));
    expect(r.total.toCanonicalString(), '19200.00');
    expect(r.basisPeriods, 3);
    expect(r.capped, isFalse);
  });

  test('AC1 one full period is used and reported', () {
    final r = res(
      whatIfCut(
        spendPerFullPeriod: [e('3200')],
        mode: const WhatIfPercent(50),
        months: 12,
      ),
    );
    expect(r.basisPeriods, 1);
    expect(r.total, e('19200'));
  });

  test('AC1 zero full periods -> NotEnoughData', () {
    expect(
      whatIfCut(
        spendPerFullPeriod: const [],
        mode: const WhatIfPercent(50),
        months: 12,
      ),
      isA<NotEnoughData>(),
    );
  });

  test('AC1 amount 500 x 6 with B 3200 -> 3000.00', () {
    final r = res(
      whatIfCut(
        spendPerFullPeriod: periods,
        mode: WhatIfAmount(e('500')),
        months: 6,
      ),
    );
    expect(r.total.toCanonicalString(), '3000.00');
    expect(r.capped, isFalse);
  });

  test('AC1 amount above B is capped and flagged', () {
    final r = res(
      whatIfCut(
        spendPerFullPeriod: periods,
        mode: WhatIfAmount(e('5000')),
        months: 2,
      ),
    );
    expect(r.monthlySaving, e('3200'));
    expect(r.total, e('6400'));
    expect(r.capped, isTrue);
  });

  test('only the last 3 periods are used', () {
    final r = res(
      whatIfCut(
        spendPerFullPeriod: [e('9999'), ...periods],
        mode: const WhatIfPercent(100),
        months: 1,
      ),
    );
    expect(r.base, e('3200'));
    expect(r.basisPeriods, 3);
  });

  test('AC3 half-even rounding once per figure', () {
    // 0.01 + 0.02 = 0.03 / 2 = 0.015 -> 0.02 (tie to even)
    final r = res(
      whatIfCut(
        spendPerFullPeriod: [e('0.01'), e('0.02')],
        mode: const WhatIfPercent(100),
        months: 1,
      ),
    );
    expect(r.base, e('0.02'));
    // 0.05 * 50% = 0.025 -> 0.02 (even)
    final r2 = res(
      whatIfCut(
        spendPerFullPeriod: [e('0.05')],
        mode: const WhatIfPercent(50),
        months: 10,
      ),
    );
    expect(r2.monthlySaving, e('0.02'));
    expect(r2.total, e('0.20'));
  });

  test('AC3 one result per currency, never summed', () {
    final out = whatIfCutByCurrency(
      spendByCurrency: {
        egp: [e('100')],
        usd: [Money.parse('10', usd)],
      },
      mode: const WhatIfPercent(10),
      months: 1,
    );
    expect(res(out[egp]!).monthlySaving, e('10'));
    expect(res(out[usd]!).monthlySaving, Money.parse('1', usd));
    final amountOut = whatIfCutByCurrency(
      spendByCurrency: {
        egp: [e('100')],
        usd: [Money.parse('10', usd)],
      },
      mode: WhatIfAmount(e('5')),
      months: 1,
    );
    expect(amountOut.keys, [egp]);
  });

  test('mixed currencies in one list are refused', () {
    expect(
      () => whatIfCut(
        spendPerFullPeriod: [e('1'), Money.parse('1', usd)],
        mode: const WhatIfPercent(10),
        months: 1,
      ),
      throwsA(isA<CurrencyMismatch>()),
    );
  });

  test('invalid parameters', () {
    for (final bad in [0, 101]) {
      expect(
        () => whatIfCut(
          spendPerFullPeriod: periods,
          mode: WhatIfPercent(bad),
          months: 1,
        ),
        throwsArgumentError,
      );
    }
    for (final m in [0, 61]) {
      expect(
        () => whatIfCut(
          spendPerFullPeriod: periods,
          mode: const WhatIfPercent(5),
          months: m,
        ),
        throwsArgumentError,
      );
      expect(() => whatIfSave(amount: e('1'), months: m), throwsArgumentError);
    }
    expect(
      () => whatIfCut(
        spendPerFullPeriod: periods,
        mode: WhatIfAmount(e('0')),
        months: 1,
      ),
      throwsArgumentError,
    );
  });

  test('whatIfSave', () {
    expect(whatIfSave(amount: e('500'), months: 12), e('6000'));
    expect(
      whatIfSave(
        amount: Money.parse('1.250', Currency.of('KWD')),
        months: 3,
      ).toCanonicalString(),
      '3.750',
    );
  });
}
