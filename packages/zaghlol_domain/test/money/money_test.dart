// Example tests for the money value types (T-012 acceptance criteria and
// design-note examples).
import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');
final Currency kwd = Currency.of('KWD');
final Currency bhd = Currency.of('BHD');
final Currency jpy = Currency.of('JPY');
final Currency clf = Currency.of('CLF');

Money m(Currency c, int minor) => Money(c, minor);

List<int> split(Money amount, List<int> weights) {
  return amount.allocate(weights).map((x) => x.minor).toList();
}

final Matcher throwsMismatch = throwsA(isA<CurrencyMismatch>());
final Matcher throwsOverflow = throwsA(isA<MoneyOverflow>());
final Matcher throwsCorrupt = throwsA(isA<CorruptMoney>());

void main() {
  group('AC: exact round trips', () {
    final cases = [
      (kwd, '1.250', 1250),
      (bhd, '0.375', 375),
      (jpy, '1500', 1500),
      (clf, '1.2345', 12345),
      (egp, '-0.05', -5),
    ];
    for (final (currency, text, minor) in cases) {
      test('${currency.code} $text <-> $minor', () {
        final parsed = Money.parse(text, currency);
        expect(parsed.minor, minor);
        expect(parsed.currency, currency);
        expect(parsed.toCanonicalString(), text);
        final row = parsed.toStorage();
        expect(row.minor, minor);
        expect(row.currency, currency.code);
        expect(Money.fromStorage(row.minor, row.currency), parsed);
        expect(Money.fromJson(parsed.toJson()), parsed);
      });
    }

    test('json shape is an integer minor plus a code', () {
      expect(m(kwd, 1250).toJson(), {'minor': 1250, 'currency': 'KWD'});
    });
  });

  group('AC: currency mismatch', () {
    test('EGP + USD throws CurrencyMismatch', () {
      expect(() => m(egp, 100) + m(usd, 100), throwsMismatch);
    });

    test('EGP - USD and ordering throw; == is false', () {
      expect(() => m(egp, 1) - m(usd, 1), throwsMismatch);
      expect(() => m(egp, 1) < m(usd, 1), throwsMismatch);
      final mixed = [m(egp, 1), m(usd, 2)];
      expect(mixed.sort, throwsMismatch);
      expect(m(egp, 1) == m(usd, 1), isFalse);
    });
  });

  group('parse: canonical form only', () {
    final rejected = <(Currency, String)>[
      (kwd, '1.2345'), // too many fraction digits: rejected, never rounded
      (jpy, '1.5'), // exponent 0 has no fraction
      (jpy, '1.'),
      (kwd, '١٫٢٥٠'), // Arabic-Indic: callers normalize first (T-013)
      (egp, '١٢'),
      (egp, '1,000.00'),
      (egp, '+1.00'),
      (egp, ' 1.00'),
      (egp, '1.00 '),
      (egp, '1e3'),
      (egp, '.5'),
      (egp, '5.'),
      (egp, ''),
      (egp, '-'),
      (egp, '--1'),
      (egp, '90071992547409.92'), // maxMinor + 1
      (egp, '-90071992547409.92'), // -(maxMinor + 1)
      (egp, '100000000000000000000'),
      (egp, '1.00\n'), // `$` must not match before a trailing newline
      (egp, '\n1.00'),
      (egp, '1.00\t'),
      (egp, '1\u00a0000.00'), // NBSP grouping
      (egp, '\uff11\uff12'), // fullwidth digits
      (egp, '\u06f1\u06f2'), // Persian (Extended Arabic-Indic) digits
      (egp, '1\u0662'), // ASCII mixed with Arabic-Indic
      (jpy, '1.0'), // exponent 0: even a zero fraction is rejected
      (egp, '00000000000000000090071992547409.92'), // zeros do not hide range
    ];
    for (var i = 0; i < rejected.length; i++) {
      final (currency, text) = rejected[i];
      test('${currency.code} case $i is rejected', () {
        expect(Money.tryParse(text, currency), isNull);
        expect(() => Money.parse(text, currency), throwsFormatException);
      });
    }

    test('leading zeros do not count toward the 16-digit cap', () {
      final zeros = '0' * 17;
      expect(Money.parse('${zeros}1', jpy).minor, 1);
      expect(Money.parse('${zeros}1.50', egp).minor, 150);
    });

    test('inputs longer than maxParseLength are rejected up front', () {
      final atLimit = '${'0' * (Money.maxParseLength - 4)}1.00';
      expect(atLimit.length, Money.maxParseLength);
      expect(Money.tryParse(atLimit, egp), m(egp, 100));
      expect(Money.tryParse('0$atLimit', egp), isNull);
      final megabyte = 1 << 20;
      expect(Money.tryParse('0' * megabyte, egp), isNull);
      expect(Money.tryParse('7' * megabyte, egp), isNull);
      expect(() => Money.parse('9' * megabyte, egp), throwsFormatException);
    });

    test('fewer fraction digits are padded', () {
      expect(Money.parse('1.5', egp).minor, 150);
      expect(Money.parse('1.2', kwd).minor, 1200);
      expect(Money.parse('007.10', egp).minor, 710);
    });

    test('-0 and -0.00 are zero', () {
      expect(Money.parse('-0', egp), Money.zero(egp));
      expect(Money.parse('-0.00', egp), Money.zero(egp));
      expect(Money.parse('-0.00', egp).toCanonicalString(), '0.00');
    });

    test('the range boundary parses exactly', () {
      expect(Money.parse('90071992547409.91', egp).minor, Money.maxMinor);
      expect(Money.parse('-90071992547409.91', egp).minor, -Money.maxMinor);
      expect(Money.parse('9007199254740991', jpy).minor, Money.maxMinor);
    });

    test('FormatException does not echo the input', () {
      try {
        Money.parse('123456.789', egp);
        fail('expected FormatException');
      } on FormatException catch (e) {
        expect(e.toString(), isNot(contains('123')));
        expect(e.source, isNull);
      }
    });
  });

  group('canonical formatting', () {
    test('per exponent', () {
      expect(m(egp, 5).toCanonicalString(), '0.05');
      expect(m(egp, -5).toCanonicalString(), '-0.05');
      expect(m(egp, 0).toCanonicalString(), '0.00');
      expect(m(kwd, 1).toCanonicalString(), '0.001');
      expect(m(jpy, -7).toCanonicalString(), '-7');
      expect(m(clf, 10000).toCanonicalString(), '1.0000');
      expect(m(egp, Money.maxMinor).toCanonicalString(), '90071992547409.91');
    });
  });

  group('range and overflow', () {
    test('constructor bounds', () {
      expect(m(egp, Money.maxMinor).minor, Money.maxMinor);
      expect(m(egp, -Money.maxMinor).minor, -Money.maxMinor);
      expect(() => m(egp, Money.maxMinor + 1), throwsOverflow);
      expect(() => m(egp, -Money.maxMinor - 1), throwsOverflow);
      expect(Money.tryMinor(egp, Money.maxMinor + 1), isNull);
      expect(Money.tryMinor(egp, 5), m(egp, 5));
    });

    test('add, subtract and times overflow throw instead of wrapping', () {
      final top = m(egp, Money.maxMinor);
      expect(() => top + m(egp, 1), throwsOverflow);
      expect(() => -top - m(egp, 1), throwsOverflow);
      expect(() => top.times(2), throwsOverflow);
      expect(() => m(egp, 2).times(1 << 63), throwsOverflow);
      expect(m(egp, 0).times(1 << 63), Money.zero(egp));
      expect(m(egp, -3).times(-4), m(egp, 12));
    });

    test('mulDiv rounds with the named mode', () {
      int half(int minor, MoneyRounding mode) {
        return m(egp, minor).mulDiv(1, 2, mode).minor;
      }

      // 10.00 EGP * 1 / 3 = 3.333.. EGP
      expect(m(egp, 1000).mulDiv(1, 3, MoneyRounding.floor), m(egp, 333));
      expect(m(egp, 1000).mulDiv(1, 3, MoneyRounding.ceil), m(egp, 334));
      expect(half(5, MoneyRounding.halfEven), 2);
      expect(half(7, MoneyRounding.halfEven), 4);
      expect(half(-5, MoneyRounding.halfAwayFromZero), -3);
      expect(half(-5, MoneyRounding.floor), -3);
      expect(half(-5, MoneyRounding.towardZero), -2);
      const floor = MoneyRounding.floor;
      expect(() => m(egp, 1).mulDiv(1, 0, floor), throwsArgumentError);
      expect(() => m(egp, 1).mulDiv(1, -3, floor), throwsArgumentError);
      expect(m(egp, 6).mulDiv(-1, 3, floor), m(egp, -2));
    });

    test('mulDiv uses exact intermediates beyond int64', () {
      final big = m(egp, Money.maxMinor);
      final result = big.mulDiv(1000000007, 1000000007, MoneyRounding.floor);
      expect(result, big);
    });
  });

  group('allocation', () {
    test('EGP 1.00 split three ways is 0.34, 0.33, 0.33', () {
      final expected = [m(egp, 34), m(egp, 33), m(egp, 33)];
      expect(m(egp, 100).allocate([1, 1, 1]), expected);
      expect(m(egp, 100).allocateEven(3), expected);
      final texts = expected.map((x) => x.toCanonicalString());
      expect(texts, ['0.34', '0.33', '0.33']);
    });

    test('largest remainder wins, ties go to the lower index', () {
      // 10 * [1, 2, 3, 4] / 10 = [1, 2, 3, 4] exactly.
      expect(split(m(egp, 10), [1, 2, 3, 4]), [1, 2, 3, 4]);
      // 5 * [1, 1] / 2: quotas 2.5, 2.5 -> tie -> index 0 gets the unit.
      expect(split(m(egp, 5), [1, 1]), [3, 2]);
      // 7 * [1, 2] / 3: quotas 2.33, 4.67 -> index 1 has the larger rest.
      expect(split(m(egp, 7), [1, 2]), [2, 5]);
      // 10 * [3, 3, 1] / 7: quotas 4.29, 4.29, 1.43 -> the one leftover unit
      // goes to index 2 (largest rest), not to the lower index 0.
      expect(split(m(egp, 10), [3, 3, 1]), [4, 4, 2]);
      // 5 * [1, 1, 1] / 3: equal rests, two leftover units -> indices 0, 1.
      expect(split(m(egp, 5), [1, 1, 1]), [2, 2, 1]);
    });

    test('negative amounts and zero weights', () {
      expect(split(m(egp, -100), [1, 1, 1]), [-34, -33, -33]);
      expect(split(m(egp, 1), [0, 1, 0]), [0, 1, 0]);
      expect(split(m(egp, 2), [0, 1, 1]), [0, 1, 1]);
      expect(split(m(egp, 0), [2, 1]), [0, 0]);
    });

    test('invalid weights throw ArgumentError', () {
      expect(() => m(egp, 1).allocate([]), throwsArgumentError);
      expect(() => m(egp, 1).allocate([0, 0]), throwsArgumentError);
      expect(() => m(egp, 1).allocate([1, -1, 2]), throwsArgumentError);
      final tooMany = List<int>.filled(maxAllocationParts + 1, 1);
      expect(() => m(egp, 1).allocate(tooMany), throwsArgumentError);
      expect(() => m(egp, 1).allocateEven(0), throwsArgumentError);
      expect(() => m(egp, 1).allocateEven(-1), throwsArgumentError);
    });

    test('allocateEven checks the part limit before allocating', () {
      final over = maxAllocationParts + 1;
      expect(() => m(egp, 1).allocateEven(over), throwsArgumentError);
      expect(() => m(egp, 1).allocateEven(1 << 40), throwsArgumentError);
      expect(() => m(egp, 1).allocateEven(1 << 62), throwsArgumentError);
    });

    test('allocation accepts exactly the maximum number of parts', () {
      final shares = m(egp, 7).allocateEven(maxAllocationParts);
      expect(shares.where((s) => s.minor == 1).length, 7);
    });
  });

  group('equality and ordering', () {
    test('== and hashCode use code and minor', () {
      expect(m(egp, 150), Money.parse('1.5', egp));
      expect(m(egp, 150).hashCode, Money.parse('1.50', egp).hashCode);
      expect(m(egp, 150) == m(egp, 151), isFalse);
    });

    test('comparisons within a currency', () {
      expect(m(egp, 1) < m(egp, 2), isTrue);
      expect(m(egp, 2) <= m(egp, 2), isTrue);
      expect(m(egp, 3) > m(egp, 2), isTrue);
      expect(m(egp, 2) >= m(egp, 3), isFalse);
      expect(m(egp, -1).compareTo(m(egp, 1)), lessThan(0));
      expect(m(egp, -1).abs(), m(egp, 1));
      expect(m(egp, -1).isNegative, isTrue);
      expect(m(egp, 1).isPositive, isTrue);
      expect(Money.zero(egp).isZero, isTrue);
    });
  });

  group('storage and json errors', () {
    test('fromStorage rejects unknown codes and out-of-range values', () {
      expect(() => Money.fromStorage(1, 'ZZZ'), throwsCorrupt);
      expect(() => Money.fromStorage(1, 'egp'), throwsCorrupt);
      final tooBig = Money.maxMinor + 1;
      expect(() => Money.fromStorage(tooBig, 'EGP'), throwsCorrupt);
    });

    test('fromJson rejects bad types, missing keys and bad values', () {
      final bad = <Map<String, Object?>>[
        {'minor': 1.5, 'currency': 'EGP'},
        {'minor': 1.0, 'currency': 'EGP'},
        {'minor': '150', 'currency': 'EGP'},
        {'minor': null, 'currency': 'EGP'},
        {'minor': true, 'currency': 'EGP'},
        {'currency': 'EGP'},
        {'minor': 150},
        {'minor': 150, 'currency': null},
        {'minor': 150, 'currency': false},
        {'minor': 150, 'currency': 818},
        {'minor': 150, 'currency': 'XAU'},
        {'minor': 150, 'currency': 'egp'},
        {'minor': Money.maxMinor + 1, 'currency': 'EGP'},
        {'minor': -Money.maxMinor - 1, 'currency': 'EGP'},
        <String, Object?>{},
      ];
      for (var i = 0; i < bad.length; i++) {
        expect(() => Money.fromJson(bad[i]), throwsCorrupt, reason: '$i');
        expect(Money.tryFromJson(bad[i]), isNull, reason: '$i');
      }
    });

    test('fromJson reports a typed reason', () {
      CorruptMoneyReason? reasonOf(Map<String, Object?> json) {
        try {
          Money.fromJson(json);
        } on CorruptMoney catch (e) {
          return e.reason;
        }
        return null;
      }

      final missing = reasonOf({'minor': 1});
      expect(missing, CorruptMoneyReason.missingCurrency);
      final nonInteger = reasonOf({'minor': 1.5, 'currency': 'EGP'});
      expect(nonInteger, CorruptMoneyReason.nonIntegerMinor);
      final unknown = reasonOf({'minor': 1, 'currency': 'ZZZ'});
      expect(unknown, CorruptMoneyReason.unknownCurrency);
      final range = reasonOf({'minor': 1 << 60, 'currency': 'EGP'});
      expect(range, CorruptMoneyReason.outOfRange);
    });

    test('fromJson ignores extra keys (lenient, pinned)', () {
      final json = {'minor': 1250, 'currency': 'KWD', 'note': 'x', 'v': 2};
      expect(Money.fromJson(json), m(kwd, 1250));
      expect(Money.tryFromJson(json), m(kwd, 1250));
    });

    test('tryFromStorage returns null instead of throwing', () {
      expect(Money.tryFromStorage(1250, 'KWD'), m(kwd, 1250));
      expect(Money.tryFromStorage(1, 'ZZZ'), isNull);
      expect(Money.tryFromStorage(1, 'egp'), isNull);
      expect(Money.tryFromStorage(1, ' EGP'), isNull);
      expect(Money.tryFromStorage(1, ''), isNull);
      expect(Money.tryFromStorage(Money.maxMinor + 1, 'EGP'), isNull);
      expect(Money.tryFromStorage(-Money.maxMinor - 1, 'EGP'), isNull);
      expect(Money.tryFromStorage(1 << 63, 'EGP'), isNull);
    });
  });

  group('no amounts in messages (NFR-SEC-03)', () {
    final digits = RegExp('[0-9]');

    test('toString and errors carry codes only', () {
      final big = m(egp, 123456789);
      expect(big.toString(), 'Money(EGP)');
      expect(big.toString(), isNot(matches(digits)));
      final errors = <Object>[
        CurrencyMismatch(egp, usd),
        MoneyOverflow(egp, MoneyOp.add),
        UnknownCurrency('EGP'),
      ];
      for (final reason in CorruptMoneyReason.values) {
        errors.add(CorruptMoney('EGP', reason));
      }
      for (final error in errors) {
        expect(error.toString(), isNot(matches(digits)));
      }
    });

    test('invalid codes are not echoed', () {
      final secret = 'card 1234 balance 5000';
      expect(UnknownCurrency(secret).toString(), isNot(contains('1234')));
      final corrupt = CorruptMoney(secret, CorruptMoneyReason.outOfRange);
      expect(corrupt.toString(), isNot(contains('1234')));
    });

    test('overflow from a real operation has no amount', () {
      try {
        m(egp, Money.maxMinor) + m(egp, 1);
        fail('expected MoneyOverflow');
      } on MoneyOverflow catch (e) {
        expect(e.toString(), 'MoneyOverflow: EGP in add');
      }
    });
  });

  group('MultiCurrencyTotal', () {
    test('sums per currency and never mixes', () {
      final items = [m(egp, 100), m(usd, 5), m(egp, 50), m(kwd, 1250)];
      final total = MultiCurrencyTotal.of(items);
      expect(total[egp], m(egp, 150));
      expect(total[usd], m(usd, 5));
      expect(total[kwd], m(kwd, 1250));
      expect(total[jpy], Money.zero(jpy));
      expect(total.currencies.map((c) => c.code), ['EGP', 'KWD', 'USD']);
      expect(total.isMultiCurrency, isTrue);
    });

    test('empty, single currency and add', () {
      const empty = MultiCurrencyTotal.empty();
      expect(empty.currencies, isEmpty);
      expect(empty.isMultiCurrency, isFalse);
      final one = empty.add(m(egp, 1)).add(m(egp, 2));
      expect(one.isMultiCurrency, isFalse);
      expect(one[egp], m(egp, 3));
      expect(empty.currencies, isEmpty);
    });

    test('nonZero drops zero totals', () {
      final total = MultiCurrencyTotal.of([m(egp, 5), m(egp, -5), m(usd, 1)]);
      expect(total.currencies.length, 2);
      expect(total.nonZero().currencies, [usd]);
    });

    test('orderedFor puts primary, then featured order, then by code', () {
      final codes = ['GBP', 'AED', 'USD', 'EGP', 'CHF', 'SAR'];
      final items = codes.map((code) => Money(Currency.of(code), 1));
      final total = MultiCurrencyTotal.of(items);
      final ordered = total.orderedFor(Currency.of('AED'));
      final orderedCodes = ordered.map((c) => c.code).join(' ');
      expect(orderedCodes, 'AED EGP USD SAR GBP CHF');
    });

    test('empty-total edges', () {
      const empty = MultiCurrencyTotal.empty();
      expect(empty[egp], Money.zero(egp));
      expect(empty + empty, empty);
      expect((empty + empty).currencies, isEmpty);
      expect(empty.nonZero(), empty);
      expect(empty.orderedFor(egp), isEmpty);
      expect(empty.isEmpty, isTrue);
      expect(MultiCurrencyTotal.of(const []), empty);
      expect(MultiCurrencyTotal.of(const []).hashCode, empty.hashCode);
    });

    test('orderedFor with a primary that is not present', () {
      final total = MultiCurrencyTotal.of([m(usd, 1), m(egp, 1)]);
      final ordered = total.orderedFor(kwd).map((c) => c.code);
      expect(ordered, ['EGP', 'USD']);
    });

    test('equal totals have equal hash codes', () {
      final a = MultiCurrencyTotal.of([m(egp, 1), m(usd, 2), m(egp, 3)]);
      final b = MultiCurrencyTotal.of([m(usd, 2), m(egp, 4)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == MultiCurrencyTotal.of([m(egp, 4)]), isFalse);
    });

    test('totals are range-checked once at the end (order-independent)', () {
      final top = m(egp, Money.maxMinor);
      final one = m(egp, 1);
      final minusOne = m(egp, -1);
      expect(MultiCurrencyTotal.of([top, one, minusOne])[egp], top);
      expect(MultiCurrencyTotal.of([top, minusOne, one])[egp], top);
      expect(() => MultiCurrencyTotal.of([top, one]), throwsOverflow);
      final big = MultiCurrencyTotal.of([top]);
      expect(() => big + MultiCurrencyTotal.of([one]), throwsOverflow);
      expect(() => big.add(one), throwsOverflow);
      expect(big.add(minusOne)[egp], m(egp, Money.maxMinor - 1));
    });

    test('toString has codes only', () {
      final total = MultiCurrencyTotal.of([m(egp, 123456), m(usd, 789)]);
      expect(total.toString(), 'MultiCurrencyTotal(EGP, USD)');
    });
  });

  group('roundDiv', () {
    test('ties per mode', () {
      BigInt r(int n, int d, MoneyRounding mode) {
        return roundDiv(BigInt.from(n), BigInt.from(d), mode);
      }

      expect(r(5, 2, MoneyRounding.halfEven), BigInt.two);
      expect(r(-5, 2, MoneyRounding.halfEven), -BigInt.two);
      expect(r(5, 2, MoneyRounding.halfAwayFromZero), BigInt.from(3));
      expect(r(-5, 2, MoneyRounding.halfAwayFromZero), BigInt.from(-3));
      expect(r(5, -2, MoneyRounding.floor), BigInt.from(-3));
      expect(r(5, -2, MoneyRounding.ceil), -BigInt.two);
      expect(r(5, -2, MoneyRounding.towardZero), -BigInt.two);
      expect(r(6, 3, MoneyRounding.ceil), BigInt.two);
      expect(() => r(1, 0, MoneyRounding.floor), throwsArgumentError);
    });
  });
}
