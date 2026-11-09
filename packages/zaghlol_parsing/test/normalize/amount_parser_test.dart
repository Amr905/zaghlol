import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/money_format.dart';

/// Expected outcome: an int is minor units, a [ParseFailureReason] a failure.
typedef _Row = (
  String name,
  String input,
  String? currency,
  NumberLocale locale,
  Object expected,
);

const _std = NumberLocale.standard;
const _eu = NumberLocale.eu;
const _malformed = ParseFailureReason.malformedAmount;
const _excess = ParseFailureReason.excessPrecision;

Currency _c(String code) => Currency.of(code);

void _expectRow(Result<Money, ParseFailure> result, Object expected) {
  if (expected is int) {
    expect(result.isOk, isTrue, reason: 'expected success');
    expect(result.valueOrNull!.minor, expected);
  } else {
    expect(result.isErr, isTrue, reason: 'expected failure');
    expect(result.failureOrNull!.reason, expected);
  }
}

void main() {
  group('acceptance criteria', () {
    test('Arabic-Indic 1,250.00 is 1250.00 EGP', () {
      final result = parseMoneyText('١٬٢٥٠٫٠٠', fallback: _c('EGP'));
      final money = result.valueOrNull!;
      expect(money.currency.code, 'EGP');
      expect(money.minor, 125000);
      expect(money.toCanonicalString(), '1250.00');
    });

    test('KWD 12.345 is 12345 minor', () {
      final money = parseMoneyText('KWD 12.345').valueOrNull!;
      expect(money.currency.code, 'KWD');
      expect(money.minor, 12345);
    });

    test('too many decimals fails and does not round', () {
      expect(
        parseMoneyText('EGP 12.345').failureOrNull!.reason,
        _excess,
      );
      expect(
        parseMoneyText('KWD 12.3456').failureOrNull!.reason,
        _excess,
      );
      expect(parseMoneyText('JPY 15.5').failureOrNull!.reason, _excess);
      expect(parseMoneyText('EGP 0.001').failureOrNull!.reason, _excess);
    });
  });

  group('parseAmount table', () {
    final rows = <_Row>[
      ('plain integer', '150', 'EGP', _std, 15000),
      ('western grouping and decimal', '1,234.56', 'EGP', _std, 123456),
      ('eu grouping and decimal', '1.234,56', 'EGP', _eu, 123456),
      ('indian grouping', '1,23,456.78', 'INR', _std, 12345678),
      ('indian grouping, 8 digits', '12,34,567', 'INR', _std, 123456700),
      ('western 7 digits', '1,234,567', 'EGP', _std, 123456700),
      ('arabic-indic', '١٬٢٥٠٫٥٠', 'EGP', _std, 125050),
      ('extended digits', '۱۲۳٫۴۵', 'EGP', _std, 12345),
      ('mixed arabic and ascii digits', '١2', 'EGP', _std, 1200),
      ('rtl-mark wrapped', '‏١٢٣‎', 'EGP', _std, 12300),
      ('exponent 0', '1500', 'JPY', _std, 1500),
      ('exponent 0 trailing zeros', '1500.00', 'JPY', _std, 1500),
      ('exponent 3', '12.345', 'KWD', _std, 12345),
      ('exponent 3 short fraction pads', '12.3', 'KWD', _std, 12300),
      ('exponent 2 trailing zero dropped', '12.500', 'EGP', _std, 1250),
      ('short fraction pads', '12.5', 'EGP', _std, 1250),
      ('zero', '0', 'EGP', _std, 0),
      ('zero with fraction', '0.00', 'EGP', _std, 0),
      ('leading zeros', '007.50', 'EGP', _std, 750),
      ('max minor', '9007199254740991', 'JPY', _std, 9007199254740991),
      // Ambiguity matrix: the locale flag decides, never digit count.
      ('std 1,234 EGP is a thousand', '1,234', 'EGP', _std, 123400),
      ('std 1,234 KWD is a thousand', '1,234', 'KWD', _std, 1234000),
      ('std 1,234 JPY is a thousand', '1,234', 'JPY', _std, 1234),
      ('std 1.234 KWD is a decimal', '1.234', 'KWD', _std, 1234),
      ('std 1.234 EGP fails', '1.234', 'EGP', _std, _excess),
      ('std 1.234 JPY fails', '1.234', 'JPY', _std, _excess),
      ('eu 1.234 EGP is a thousand', '1.234', 'EGP', _eu, 123400),
      ('eu 1.234 KWD is a thousand', '1.234', 'KWD', _eu, 1234000),
      ('eu 1.234 JPY is a thousand', '1.234', 'JPY', _eu, 1234),
      ('eu 1,234 KWD is a decimal', '1,234', 'KWD', _eu, 1234),
      ('eu 1,234 EGP fails', '1,234', 'EGP', _eu, _excess),
      ('eu 1,234 JPY fails', '1,234', 'JPY', _eu, _excess),
      ('eu indian grouping', '1.23.456,78', 'EGP', _eu, 12345678),
      // Failures.
      ('eu text under standard', '1.234,56', 'EGP', _std, _malformed),
      ('standard text under eu', '1,234.56', 'EGP', _eu, _malformed),
      ('repeated decimal', '1.234.567', 'EGP', _std, _malformed),
      ('repeated decimal after group', '1,234.567.8', 'EGP', _std, _malformed),
      ('group too long', '1,2345', 'EGP', _std, _malformed),
      ('group too short', '12,34', 'EGP', _std, _malformed),
      ('out-of-pattern groups', '12,34,5', 'EGP', _std, _malformed),
      ('group after decimal', '1,234.567,8', 'EGP', _std, _malformed),
      ('empty group', '1,,234', 'EGP', _std, _malformed),
      ('empty', '', 'EGP', _std, _malformed),
      ('digits and letters', '12abc', 'EGP', _std, _malformed),
      ('no leading digit', '٫٥٠', 'EGP', _std, _malformed),
      ('leading separator', ',500', 'EGP', _std, _malformed),
      ('trailing separator', '150.', 'EGP', _std, _malformed),
      ('minus sign', '-5', 'EGP', _std, _malformed),
      ('plus sign', '+5', 'EGP', _std, _malformed),
      ('space as thousands', '1 234', 'EGP', _std, _malformed),
      ('over max minor', '9007199254740992', 'JPY', _std, _malformed),
      ('too long', '1' * 70, 'JPY', _std, _malformed),
    ];
    for (final (name, input, code, locale, expected) in rows) {
      test(name, () {
        final result = parseAmount(
          input,
          currency: _c(code!),
          locale: locale,
        );
        _expectRow(result, expected);
      });
    }
  });

  group('parseMoneyText table', () {
    final rows = <_Row>[
      ('iso code before', 'EGP 150.50', null, _std, 15050),
      ('iso code after', '150.50 EGP', null, _std, 15050),
      ('iso code glued', 'EGP150.50', null, _std, 15050),
      ('iso code lowercase', 'kwd 1.5', null, _std, 1500),
      ('arabic digits with code', 'EGP ١٢٫٥', null, _std, 1250),
      ('dollar', r'$ 1,234.56', null, _std, 123456),
      ('dollar glued after', r'12.50$', null, _std, 1250),
      ('pound', '£99.99', null, _std, 9999),
      ('euro eu', '€ 1.234,56', null, _eu, 123456),
      ('rupee indian', '₹ 1,23,456.78', null, _std, 12345678),
      ('lira', '₺5', null, _std, 500),
      ('exponent 0 code', 'JPY 1500', null, _std, 1500),
      ('exponent 3 code', 'BHD 0.005', null, _std, 5),
      ('fallback used without marker', '150', 'EGP', _std, 15000),
      ('unambiguous symbol beats fallback', '£5', 'EGP', _std, 500),
      ('code beats fallback', 'KWD 1.5', 'EGP', _std, 1500),
      ('rial with agreeing fallback', '﷼ 10', 'SAR', _std, 1000),
      ('rial without fallback', '﷼ 10', null, _std, _malformed),
      ('rial with other fallback', '﷼ 10', 'EGP', _std, _malformed),
      ('dollar with agreeing fallback', r'$ 10', 'CAD', _std, 1000),
      ('dollar with other fallback', r'$ 10', 'EGP', _std, _malformed),
      ('no marker no fallback', '150', null, _std, _malformed),
      ('unknown marker', 'XYZ 150', null, _std, _malformed),
      ('marker on both sides', 'EGP 150 EGP', null, _std, _malformed),
      ('two numbers', 'EGP 150 and 20', null, _std, _malformed),
      ('no number', 'EGP', null, _std, _malformed),
      ('digits and letters', '12abc', 'EGP', _std, _malformed),
      ('sentence full stop', 'EGP 150.', null, _std, _malformed),
      ('excess precision', 'EGP 12.345', null, _std, _excess),
      ('empty', '', 'EGP', _std, _malformed),
    ];
    for (final (name, input, fallback, locale, expected) in rows) {
      test(name, () {
        final result = parseMoneyText(
          input,
          fallback: fallback == null ? null : _c(fallback),
          locale: locale,
        );
        _expectRow(result, expected);
      });
    }
  });

  group('round trip property', () {
    test('parseMoneyText(format(m)) == m', () {
      final random = Random(2026);
      final currencies = Currency.all.toList();
      for (var i = 0; i < 2000; i++) {
        final currency = currencies[random.nextInt(currencies.length)];
        final minor = _randomMinor(random);
        final money = Money(currency, minor);
        final style = FormatStyle.values[random.nextInt(
          FormatStyle.values.length,
        )];
        final formatted = formatMoney(
          money,
          style,
          markerAfter: random.nextBool(),
          useSymbol: random.nextBool(),
        );
        final result = parseMoneyText(
          formatted.text,
          locale: formatted.locale,
        );
        expect(
          result.valueOrNull,
          money,
          reason: '${currency.code} ${style.name}',
        );
      }
    });

    test('exponent+1 digits with non-zero last digit never parse', () {
      final random = Random(7);
      final currencies = Currency.all.toList();
      for (var i = 0; i < 2000; i++) {
        final currency = currencies[random.nextInt(currencies.length)];
        final whole = random.nextInt(1000000);
        final fraction = StringBuffer();
        for (var d = 0; d < currency.exponent; d++) {
          fraction.write(random.nextInt(10));
        }
        fraction.write(1 + random.nextInt(9));
        final result = parseAmount('$whole.$fraction', currency: currency);
        expect(
          result.failureOrNull?.reason,
          _excess,
          reason: '${currency.code} exponent ${currency.exponent}',
        );
      }
    });
  });

  group('fuzz', () {
    test('random text never throws and failures never echo the input', () {
      final random = Random(99);
      const alphabet = '0123456789,.٫٬ ١٢٣۴€\$£﷼EGPKWDJ-+abc‏';
      for (var i = 0; i < 5000; i++) {
        final length = random.nextInt(20);
        final text = String.fromCharCodes([
          for (var k = 0; k < length; k++)
            alphabet.codeUnitAt(random.nextInt(alphabet.length)),
        ]);
        for (final locale in NumberLocale.values) {
          final result = parseMoneyText(text, locale: locale);
          final failure = result.failureOrNull;
          if (failure != null && text.trim().length >= 3) {
            expect(failure.toString().contains(text.trim()), isFalse);
            expect(failure.code, startsWith('PARSE_'));
          }
          parseAmount(text, currency: _c('EGP'), locale: locale);
        }
      }
    });
  });
}

int _randomMinor(Random random) {
  switch (random.nextInt(4)) {
    case 0:
      return random.nextInt(1000);
    case 1:
      return random.nextInt(1 << 31);
    case 2:
      return Money.maxMinor - random.nextInt(1000);
    default:
      return (random.nextInt(1 << 26) << 26) + random.nextInt(1 << 26);
  }
}
