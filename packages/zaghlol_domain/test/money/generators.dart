// glados generators for money property tests (T-012 design note).
import 'package:glados/glados.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

const int maxMinor = Money.maxMinor;

/// A fresh config for every property (design note: 1000 runs), each with
/// its own fixed seed, so a failing property reproduces when run alone with
/// `--name`. glados 1.1.7 takes the seed through `ExploreConfig.random`.
ExploreConfig explore() => ExploreConfig(numRuns: 1000, random: Random(42));

/// The int64 maximum (Dart VM / AOT).
const int int64Max = 0x7FFFFFFFFFFFFFFF;

/// Allocation weight edge cases: a single weight, all-equal weights,
/// weights of maxMinor, and int64-scale weights whose sum exceeds 2^63.
List<int> edgeWeights(Random random) {
  final length = 1 + random.nextInt(20);
  switch (random.nextInt(5)) {
    case 0:
      return [1 + random.nextInt(1000000)];
    case 1:
      return List<int>.filled(length, 1 + random.nextInt(1000));
    case 2:
      return List<int>.filled(length, maxMinor);
    case 3:
      return [int64Max, int64Max, 1];
    default:
      return [1 << 62, 1 << 62, 0, 1 << 62, 3];
  }
}

final List<Currency> _exp0 = _withExponent(0);
final List<Currency> _exp2 = _withExponent(2);
final List<Currency> _exp3 = _withExponent(3);
final List<Currency> _all = Currency.all.toList();

List<Currency> _withExponent(int exponent) {
  return Currency.all.where((c) => c.exponent == exponent).toList();
}

/// Edge values for minor amounts.
const List<int> minorEdges = [
  0,
  1,
  -1,
  9,
  -9,
  10,
  -10,
  999,
  -999,
  1000,
  -1000,
  maxMinor - 1,
  -(maxMinor - 1),
  maxMinor,
  -maxMinor,
];

/// Uniform-ish int in [0, 2^53 - 1], built from two `nextInt` calls because
/// `Random.nextInt` is limited to 2^32.
int wideNonNegative(Random random) {
  final high = random.nextInt(1 << 21);
  final low = random.nextInt(1 << 32);
  return high * (1 << 32) + low;
}

Iterable<int> _shrinkInt(int value) {
  if (value == 0) {
    return const [];
  }
  return {0, value ~/ 2}.where((v) => v != value);
}

extension MoneyAnys on Any {
  /// A currency from the table; exponents 0, 2 and 3 each at least 25%.
  Generator<Currency> get currency {
    return simple(
      generate: (random, size) {
        final bucket = random.nextInt(100);
        final List<Currency> pool;
        if (bucket < 28) {
          pool = _exp0;
        } else if (bucket < 56) {
          pool = _exp2;
        } else if (bucket < 84) {
          pool = _exp3;
        } else {
          pool = _all;
        }
        return pool[random.nextInt(pool.length)];
      },
      shrink: (c) => c.code == 'EGP' ? const [] : [Currency.of('EGP')],
    );
  }

  /// Minor amounts covering the whole range +-maxMinor: the edge pool,
  /// `any.intInRange` near zero, and wide uniform values.
  Generator<int> get minor {
    return simple(
      generate: (random, size) {
        final bucket = random.nextInt(4);
        if (bucket == 0) {
          return minorEdges[random.nextInt(minorEdges.length)];
        }
        if (bucket == 1) {
          return any.intInRange(-1000000, 1000001)(random, size).value;
        }
        final magnitude = wideNonNegative(random);
        return random.nextBool() ? magnitude : -magnitude;
      },
      shrink: _shrinkInt,
    );
  }

  /// Minor amounts small enough that 64 of them can be summed safely.
  Generator<int> get smallMinor {
    return simple(
      generate: (random, size) {
        final int value;
        if (random.nextBool()) {
          value = wideNonNegative(random) ~/ 64;
        } else {
          value = random.nextInt(1000001);
        }
        return random.nextBool() ? value : -value;
      },
      shrink: _shrinkInt,
    );
  }

  Generator<Money> get money {
    return combine2(currency, minor, (Currency c, int m) => Money(c, m));
  }

  /// Two amounts in the same currency.
  Generator<(Money, Money)> get samePair {
    return combine2(
      currency,
      combine2(minor, minor, (int a, int b) => (a, b)),
      (Currency c, (int, int) m) => (Money(c, m.$1), Money(c, m.$2)),
    );
  }

  /// Three amounts in the same currency.
  Generator<(Money, Money, Money)> get sameTriple {
    return combine2(
      samePair,
      minor,
      (pair, int m) => (pair.$1, pair.$2, Money(pair.$1.currency, m)),
    );
  }

  /// Two different currencies.
  Generator<(Currency, Currency)> get differentCurrencies {
    return simple(
      generate: (random, size) {
        final a = _all[random.nextInt(_all.length)];
        var b = _all[random.nextInt(_all.length)];
        while (b == a) {
          b = _all[random.nextInt(_all.length)];
        }
        return (a, b);
      },
      shrink: (pair) => const [],
    );
  }

  /// Non-empty weights (length 1-50), entries 0..10^6, at least one > 0.
  Generator<List<int>> get weights {
    return _weights((random) {
      return random.nextInt(5) == 0 ? 0 : random.nextInt(1000001);
    });
  }

  /// Weights up to maxMinor, to exercise the BigInt path.
  Generator<List<int>> get bigWeights {
    return _weights((random) {
      return random.nextInt(5) == 0 ? 0 : wideNonNegative(random);
    });
  }

  Generator<List<int>> _weights(int Function(Random random) entry) {
    return simple(
      generate: (random, size) {
        if (random.nextInt(4) == 0) {
          return edgeWeights(random);
        }
        final length = 1 + random.nextInt(50);
        final result = [for (var i = 0; i < length; i++) entry(random)];
        if (result.every((w) => w == 0)) {
          result[random.nextInt(length)] = 1 + random.nextInt(1000);
        }
        return result;
      },
      shrink: (list) {
        if (list.length <= 1) {
          return const [];
        }
        final shorter = list.sublist(0, list.length - 1);
        return shorter.any((w) => w > 0) ? [shorter] : const [];
      },
    );
  }

  /// All-equal weights (length 1-50): 1, a random value or maxMinor.
  Generator<List<int>> get equalWeights {
    return simple(
      generate: (random, size) {
        final length = 1 + random.nextInt(50);
        final values = [1, 1 + random.nextInt(1000000), maxMinor];
        final value = values[random.nextInt(values.length)];
        return List<int>.filled(length, value);
      },
      shrink: (list) => list.length <= 1 ? const [] : [list.sublist(1)],
    );
  }

  /// Lists of 0-30 full-range amounts in two currencies, so per-currency
  /// totals often leave the range.
  Generator<List<Money>> get fullRangeMoneyList {
    return simple(
      generate: (random, size) {
        const codes = ['EGP', 'KWD'];
        final length = random.nextInt(31);
        final result = <Money>[];
        for (var i = 0; i < length; i++) {
          final currency = Currency.of(codes[random.nextInt(codes.length)]);
          result.add(Money(currency, minor(random, size).value));
        }
        return result;
      },
      shrink: (list) => list.isEmpty ? const [] : [list.sublist(1)],
    );
  }

  /// Lists of 0-30 amounts in a small set of currencies, so totals collide.
  Generator<List<Money>> get moneyList {
    return simple(
      generate: (random, size) {
        const codes = ['EGP', 'USD', 'KWD', 'JPY', 'CLF'];
        final length = random.nextInt(31);
        final result = <Money>[];
        for (var i = 0; i < length; i++) {
          final currency = Currency.of(codes[random.nextInt(codes.length)]);
          result.add(Money(currency, smallMinor(random, size).value));
        }
        return result;
      },
      shrink: (list) => list.isEmpty ? const [] : [list.sublist(1)],
    );
  }
}
