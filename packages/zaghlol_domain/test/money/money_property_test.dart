// Property tests for the money value types (T-012 design note, 1-10).
import 'dart:math';

import 'package:glados/glados.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'generators.dart';

final BigInt _max = BigInt.from(maxMinor);

final List<int> _int64Edges = [1 << 62, -(1 << 62), 1 << 63, (1 << 63) - 1];

bool _inRange(BigInt value) => value.abs() <= _max;

Money? _tryAdd(Money? a, Money? b) {
  if (a == null || b == null) {
    return null;
  }
  try {
    return a + b;
  } on MoneyOverflow {
    return null;
  }
}

BigInt _sumMinor(Iterable<Money> items) {
  return items.fold(BigInt.zero, (sum, m) => sum + BigInt.from(m.minor));
}

/// Independent rational oracle for [roundDiv]: floor division via the
/// non-negative modulo, then the rounding decision from 2*m vs d.
BigInt _oracle(BigInt n, BigInt d, MoneyRounding mode) {
  if (d.isNegative) {
    n = -n;
    d = -d;
  }
  final m = n % d; // 0 <= m < d
  final fl = (n - m) ~/ d; // exact floor
  final ce = m == BigInt.zero ? fl : fl + BigInt.one;
  if (m == BigInt.zero) {
    return fl;
  }
  final twice = m * BigInt.two;
  switch (mode) {
    case MoneyRounding.floor:
      return fl;
    case MoneyRounding.ceil:
      return ce;
    case MoneyRounding.towardZero:
      return n.isNegative ? ce : fl;
    case MoneyRounding.halfAwayFromZero:
      if (twice == d) {
        return n.isNegative ? fl : ce;
      }
      return twice < d ? fl : ce;
    case MoneyRounding.halfEven:
      if (twice == d) {
        return fl.isEven ? fl : ce;
      }
      return twice < d ? fl : ce;
  }
}

extension _PropertyAnys on Any {
  Generator<int> get factor {
    return simple(
      generate: (random, size) {
        switch (random.nextInt(5)) {
          case 0:
            return random.nextInt(21) - 10;
          case 1:
            return random.nextInt(2000001) - 1000000;
          case 2:
            return random.nextBool() ? maxMinor : -maxMinor - 1;
          case 3:
            // int64 extremes: 1 << 63 wraps to the minimum on the VM.
            return _int64Edges[random.nextInt(_int64Edges.length)];
          default:
            final magnitude = wideNonNegative(random);
            return random.nextBool() ? magnitude : -magnitude;
        }
      },
      shrink: (f) => f == 0 ? const [] : [0],
    );
  }

  Generator<MoneyRounding> get rounding {
    return simple(
      generate: (random, size) => MoneyRounding.values[random.nextInt(5)],
      shrink: (mode) => const [],
    );
  }

  /// (n, d, mode) with d != 0; one third are exact .5 ties.
  Generator<(BigInt, BigInt, MoneyRounding)> get division {
    return simple(
      generate: (random, size) {
        final mode = MoneyRounding.values[random.nextInt(5)];
        var d = BigInt.from(1 + random.nextInt(1000));
        if (random.nextInt(3) == 0) {
          d = BigInt.from(wideNonNegative(random) + 1);
        }
        BigInt n;
        if (random.nextInt(3) == 0) {
          // Tie: n = k*d + d/2 with d even.
          d = d * BigInt.two;
          final k = BigInt.from(random.nextInt(2001) - 1000);
          n = k * d + d ~/ BigInt.two;
        } else {
          final wide = BigInt.from(wideNonNegative(random));
          n = wide * BigInt.from(random.nextInt(1000) + 1);
        }
        if (random.nextBool()) {
          n = -n;
        }
        if (random.nextBool()) {
          d = -d;
        }
        return (n, d, mode);
      },
      shrink: (input) => const [],
    );
  }
}

Generator<(Money, int)> get _moneyFactor {
  return any.combine2(any.money, any.factor, (Money m, int f) => (m, f));
}

Generator<(int, MoneyRounding)> get _divisor {
  return any.combine2(
    any.intInRange(1, 1000000),
    any.rounding,
    (int d, MoneyRounding r) => (d, r),
  );
}

Generator<(Money, int, int, MoneyRounding)> get _mulDivInput {
  return any.combine2(
    _moneyFactor,
    _divisor,
    ((Money, int) a, (int, MoneyRounding) b) => (a.$1, a.$2, b.$1, b.$2),
  );
}

Generator<(Money, Money)> get _mismatched {
  return any.combine2(
    any.differentCurrencies,
    any.combine2(any.minor, any.minor, (int a, int b) => (a, b)),
    ((Currency, Currency) c, (int, int) m) =>
        (Money(c.$1, m.$1), Money(c.$2, m.$2)),
  );
}

Generator<(Money, List<int>)> get _allocSmall {
  return any.combine2(any.money, any.weights, (Money m, List<int> w) => (m, w));
}

Generator<(Money, List<int>)> get _allocBig {
  return any.combine2(
    any.money,
    any.bigWeights,
    (Money m, List<int> w) => (m, w),
  );
}

Generator<(Money, int)> get _allocEven {
  return any.combine2(
    any.money,
    any.intInRange(1, 51),
    (Money m, int parts) => (m, parts),
  );
}

/// Reference Hamilton split: floor quotas, then one extra unit each to the
/// R largest remainders (ties: lower index), never to a zero weight.
List<BigInt> _hamilton(int amount, List<int> weights) {
  final a = BigInt.from(amount).abs();
  var total = BigInt.zero;
  for (final w in weights) {
    total += BigInt.from(w);
  }
  final shares = <BigInt>[];
  final rests = <BigInt>[];
  final positive = <int>[];
  for (var i = 0; i < weights.length; i++) {
    final quota = a * BigInt.from(weights[i]);
    final floor = quota ~/ total;
    shares.add(floor);
    rests.add(quota - floor * total);
    if (weights[i] > 0) {
      positive.add(i);
    }
  }
  final assigned = shares.fold(BigInt.zero, (s, x) => s + x);
  final leftover = (a - assigned).toInt();
  positive.sort((i, j) {
    final byRest = rests[j].compareTo(rests[i]);
    return byRest != 0 ? byRest : i - j;
  });
  for (final i in positive.take(leftover)) {
    shares[i] += BigInt.one;
  }
  return [for (final s in shares) amount < 0 ? -s : s];
}

Generator<(Money, List<int>)> get _allocEqual {
  return any.combine2(
    any.money,
    any.equalWeights,
    (Money m, List<int> w) => (m, w),
  );
}

void main() {
  group('1. addition laws', () {
    Glados(any.samePair, explore()).test('+ is commutative', (p) {
      final (a, b) = p;
      expect(_tryAdd(a, b), _tryAdd(b, a));
    });

    Glados(any.sameTriple, explore()).test('+ is associative', (t) {
      final (a, b, c) = t;
      final left = _tryAdd(_tryAdd(a, b), c);
      final right = _tryAdd(a, _tryAdd(b, c));
      if (left != null && right != null) {
        expect(left, right);
      }
    });

    Glados(any.money, explore()).test('zero is the identity', (a) {
      expect(a + Money.zero(a.currency), a);
      expect(Money.zero(a.currency) + a, a);
    });

    Glados(any.money, explore()).test('a + (-a) == 0', (a) {
      expect((a + -a).isZero, isTrue);
      expect(-(-a), a);
    });

    Glados(any.samePair, explore()).test('a - b == a + (-b)', (p) {
      final (a, b) = p;
      Money? difference;
      try {
        difference = a - b;
      } on MoneyOverflow {
        difference = null;
      }
      expect(difference, _tryAdd(a, -b));
    });
  });

  group('2. overflow is exact', () {
    Glados(any.samePair, explore()).test('+ throws iff out of range', (p) {
      final (a, b) = p;
      final exact = BigInt.from(a.minor) + BigInt.from(b.minor);
      if (_inRange(exact)) {
        expect(BigInt.from((a + b).minor), exact);
      } else {
        expect(() => a + b, throwsA(isA<MoneyOverflow>()));
      }
    });

    Glados(any.samePair, explore()).test('- throws iff out of range', (p) {
      final (a, b) = p;
      final exact = BigInt.from(a.minor) - BigInt.from(b.minor);
      if (_inRange(exact)) {
        expect(BigInt.from((a - b).minor), exact);
      } else {
        expect(() => a - b, throwsA(isA<MoneyOverflow>()));
      }
    });

    Glados(_moneyFactor, explore()).test('times throws iff overflow', (input) {
      final (m, f) = input;
      final exact = BigInt.from(m.minor) * BigInt.from(f);
      if (_inRange(exact)) {
        expect(BigInt.from(m.times(f).minor), exact);
      } else {
        expect(() => m.times(f), throwsA(isA<MoneyOverflow>()));
      }
    });

    Glados(_mulDivInput, explore()).test('mulDiv throws iff overflow', (input) {
      final (m, numerator, denominator, mode) = input;
      final product = BigInt.from(m.minor) * BigInt.from(numerator);
      final exact = _oracle(product, BigInt.from(denominator), mode);
      if (_inRange(exact)) {
        final result = m.mulDiv(numerator, denominator, mode);
        expect(BigInt.from(result.minor), exact);
      } else {
        expect(
          () => m.mulDiv(numerator, denominator, mode),
          throwsA(isA<MoneyOverflow>()),
        );
      }
    });
  });

  group('3. different currencies', () {
    Glados(_mismatched, explore()).test('mismatch throws, == is false', (p) {
      final (a, b) = p;
      expect(() => a + b, throwsA(isA<CurrencyMismatch>()));
      expect(() => a - b, throwsA(isA<CurrencyMismatch>()));
      expect(() => a.compareTo(b), throwsA(isA<CurrencyMismatch>()));
      expect(() => a < b, throwsA(isA<CurrencyMismatch>()));
      expect(a == b, isFalse);
    });
  });

  group('4-7. allocation', () {
    void checkAllocation(Money amount, List<int> weights) {
      final shares = amount.allocate(weights);
      // 4. exact, same length, same currency, zero weights get zero.
      expect(shares.length, weights.length);
      expect(_sumMinor(shares), BigInt.from(amount.minor));
      for (var i = 0; i < weights.length; i++) {
        expect(shares[i].currency, amount.currency);
        if (weights[i] == 0) {
          expect(shares[i].minor, 0);
        }
      }
      // 5. within one minor unit of the quota: |s*W - a*w| < W.
      final total = weights.fold(BigInt.zero, (s, w) => s + BigInt.from(w));
      var withinOne = true;
      for (var i = 0; i < weights.length; i++) {
        final scaled = BigInt.from(shares[i].minor) * total;
        final quota = BigInt.from(amount.minor) * BigInt.from(weights[i]);
        if ((scaled - quota).abs() >= total) {
          withinOne = false;
        }
      }
      expect(withinOne, isTrue);
      // 6. sign symmetry.
      expect((-amount).allocate(weights), [for (final s in shares) -s]);
      // 6. monotonic for non-negative amounts.
      final positive = amount.abs().allocate(weights);
      var monotonic = true;
      for (var i = 0; i < weights.length; i++) {
        for (var j = 0; j < weights.length; j++) {
          if (weights[i] > weights[j] && positive[i] < positive[j]) {
            monotonic = false;
          }
          // Equal weights: shares never increase with the index.
          final equal = weights[i] == weights[j];
          if (equal && i < j && positive[i] < positive[j]) {
            monotonic = false;
          }
        }
      }
      expect(monotonic, isTrue);
      // Hamilton reference: exactly the shares of the BigInt oracle.
      final actual = shares.map((s) => BigInt.from(s.minor)).toList();
      expect(actual, _hamilton(amount.minor, weights));
    }

    Glados(_allocSmall, explore()).test('weights 0..10^6 and edges', (input) {
      checkAllocation(input.$1, input.$2);
    });

    Glados(_allocBig, explore()).test('weights to maxMinor and edges', (input) {
      checkAllocation(input.$1, input.$2);
    });

    Glados(_allocEqual, explore()).test('equal weights', (input) {
      checkAllocation(input.$1, input.$2);
      final shares = input.$1.abs().allocate(input.$2);
      for (var i = 1; i < shares.length; i++) {
        expect(shares[i] <= shares[i - 1], isTrue);
      }
    });

    Glados(_allocEven, explore()).test('7. allocateEven spread <= 1', (input) {
      final (amount, parts) = input;
      final shares = amount.allocateEven(parts);
      expect(shares.length, parts);
      expect(_sumMinor(shares), BigInt.from(amount.minor));
      final minors = shares.map((s) => s.minor).toList();
      expect(minors.reduce(max) - minors.reduce(min) <= 1, isTrue);
    });
  });

  group('8. round trips', () {
    Glados(any.money, explore()).test('canonical string', (m) {
      expect(Money.parse(m.toCanonicalString(), m.currency), m);
      expect(Money.tryParse(m.toCanonicalString(), m.currency), m);
    });

    Glados(any.money, explore()).test('storage', (m) {
      final row = m.toStorage();
      expect(Money.fromStorage(row.minor, row.currency), m);
    });

    Glados(any.money, explore()).test('json', (m) {
      expect(Money.fromJson(m.toJson()), m);
      expect(Money.tryFromJson(m.toJson()), m);
    });
  });

  group('equality and hashing', () {
    Glados(any.money, explore()).test('equal copies hash equally', (m) {
      final copies = [
        Money(m.currency, m.minor),
        Money.parse(m.toCanonicalString(), m.currency),
        Money.fromStorage(m.minor, m.currency.code),
        Money.fromJson(m.toJson()),
      ];
      for (final copy in copies) {
        expect(copy, m);
        expect(copy.hashCode, m.hashCode);
      }
    });

    Glados(any.samePair, explore()).test('a == b iff same minor', (p) {
      final (a, b) = p;
      expect(a == b, a.minor == b.minor);
      if (a == b) {
        expect(a.hashCode, b.hashCode);
      }
    });
  });

  group('9. MultiCurrencyTotal', () {
    Glados(any.moneyList, explore()).test('independent of input order', (xs) {
      final total = MultiCurrencyTotal.of(xs);
      expect(MultiCurrencyTotal.of(xs.reversed), total);
      final shuffled = [...xs]..shuffle(Random(xs.length));
      expect(MultiCurrencyTotal.of(shuffled), total);
    });

    Glados(any.moneyList, explore()).test('of(xs)[c] is the sum in c', (xs) {
      final total = MultiCurrencyTotal.of(xs);
      for (final c in total.currencies) {
        final inC = xs.where((m) => m.currency == c);
        expect(BigInt.from(total[c].minor), _sumMinor(inC));
      }
      expect(total.currencies.toSet(), xs.map((m) => m.currency).toSet());
    });

    Glados(any.fullRangeMoneyList, explore()).test('full range', (xs) {
      // Exact sums, range-checked once: the outcome (value or overflow)
      // depends only on the multiset of items, never on their order.
      MultiCurrencyTotal? tryOf(Iterable<Money> items) {
        try {
          return MultiCurrencyTotal.of(items);
        } on MoneyOverflow {
          return null;
        }
      }

      final total = tryOf(xs);
      expect(tryOf(xs.reversed), total);
      final shuffled = [...xs]..shuffle(Random(xs.length));
      expect(tryOf(shuffled), total);
      final egp = Currency.of('EGP');
      final kwd = Currency.of('KWD');
      final fits = [egp, kwd].every((c) {
        final sum = _sumMinor(xs.where((m) => m.currency == c));
        return _inRange(sum);
      });
      expect(total != null, fits);
    });

    Glados(any.moneyList, explore()).test('+ is associative', (xs) {
      final third = xs.length ~/ 3;
      final a = MultiCurrencyTotal.of(xs.sublist(0, third));
      final b = MultiCurrencyTotal.of(xs.sublist(third, 2 * third));
      final c = MultiCurrencyTotal.of(xs.sublist(2 * third));
      expect((a + b) + c, a + (b + c));
      expect((a + b) + c, MultiCurrencyTotal.of(xs));
    });
  });

  group('10. roundDiv', () {
    Glados(any.division, explore()).test('matches the oracle', (input) {
      final (n, d, mode) = input;
      expect(roundDiv(n, d, mode), _oracle(n, d, mode));
    });
  });
}
