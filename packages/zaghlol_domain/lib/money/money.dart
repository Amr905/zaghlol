import 'allocation.dart';
import 'currency.dart';
import 'money_errors.dart';
import 'rounding.dart';

/// An exact amount of money: integer minor units plus an ISO 4217 currency
/// (BR-MON-01..03).
///
/// Invariant: `|minor| <= maxMinor` (2^53 - 1). Every operation checks its
/// result and throws [MoneyOverflow] instead of wrapping or clamping.
/// Arithmetic and ordering across currencies throw [CurrencyMismatch]; `==`
/// across currencies is simply false.
final class Money implements Comparable<Money> {
  /// Creates an amount of [minor] minor units of [currency].
  ///
  /// Throws [MoneyOverflow] when `|minor| > maxMinor`. Untrusted values go
  /// through [tryMinor].
  Money(this.currency, int minor) : minor = _check(currency, minor, 'new');

  /// Zero in [currency].
  Money.zero(this.currency) : minor = 0;

  const Money._(this.currency, this.minor);

  /// 2^53 - 1: exact in JSON and for any reader that uses binary floating
  /// point, and far beyond any personal balance.
  static const int maxMinor = 9007199254740991;

  /// Amount in minor units of [currency] (e.g. fils for KWD, piastres for
  /// EGP).
  final int minor;

  final Currency currency;

  /// Boundary constructor: null instead of throwing when out of range.
  static Money? tryMinor(Currency currency, int minor) {
    return _inRange(minor) ? Money._(currency, minor) : null;
  }

  static final RegExp _canonical = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$');
  static final RegExp _leadingZeros = RegExp('^0+');

  /// Parses the canonical ASCII form `-?[0-9]+(\.[0-9]{1,e})?` where `e` is
  /// the currency exponent (no `.` when `e` is 0).
  ///
  /// No `+`, grouping, whitespace, exponent notation or non-ASCII digits:
  /// callers normalize first (T-013). More fraction digits than `e` is an
  /// error, never rounded. Fewer digits are padded (EGP `1.5` is 150).
  /// Throws [FormatException], also when the amount is out of range. The
  /// exception never contains the input.
  static Money parse(String canonical, Currency currency) {
    final result = _parse(canonical, currency);
    if (result == null) {
      throw FormatException('not a canonical ${currency.code} amount');
    }
    return result;
  }

  /// Like [parse] but returns null on any malformed or out-of-range input.
  static Money? tryParse(String canonical, Currency currency) {
    return _parse(canonical, currency);
  }

  static Money? _parse(String text, Currency currency) {
    final match = _canonical.firstMatch(text);
    if (match == null) {
      return null;
    }
    final sign = match.group(1)!;
    final whole = match.group(2)!;
    final fraction = match.group(3) ?? '';
    final exponent = currency.exponent;
    final hasPoint = match.group(3) != null;
    if (hasPoint && (exponent == 0 || fraction.length > exponent)) {
      return null;
    }
    // Leading zeros are allowed. maxMinor has 16 digits, so anything longer
    // is out of range and int.parse below cannot overflow.
    final padded = whole + fraction.padRight(exponent, '0');
    final digits = padded.replaceFirst(_leadingZeros, '');
    if (digits.length > 16) {
      return null;
    }
    final magnitude = digits.isEmpty ? 0 : int.parse(digits);
    if (magnitude > maxMinor) {
      return null;
    }
    return Money._(currency, sign == '-' ? -magnitude : magnitude);
  }

  /// Canonical ASCII form, e.g. `1.250` (KWD), `1500` (JPY), `-0.05` (EGP).
  /// Also the CSV export format (BR-EXP-01).
  String toCanonicalString() {
    final exponent = currency.exponent;
    final digits = minor.abs().toString();
    final sign = minor < 0 ? '-' : '';
    if (exponent == 0) {
      return '$sign$digits';
    }
    final padded = digits.padLeft(exponent + 1, '0');
    final cut = padded.length - exponent;
    return '$sign${padded.substring(0, cut)}.${padded.substring(cut)}';
  }

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  bool get isPositive => minor > 0;

  Money operator +(Money other) {
    _requireSame(other);
    final result = minor + other.minor;
    return Money._(currency, _check(currency, result, 'add'));
  }

  Money operator -(Money other) {
    _requireSame(other);
    final result = minor - other.minor;
    return Money._(currency, _check(currency, result, 'subtract'));
  }

  /// Negation never overflows: the range is symmetric.
  Money operator -() => Money._(currency, -minor);

  Money abs() => minor < 0 ? -this : this;

  /// Multiplies by an integer [factor]; throws [MoneyOverflow] when the
  /// exact product is out of range.
  Money times(int factor) {
    if (minor == 0 || factor == 0) {
      return Money._(currency, 0);
    }
    // |minor| >= 1, so any |factor| > maxMinor overflows. Checking that first
    // also keeps factor.abs() away from the int64 minimum.
    final factorTooBig = factor > maxMinor || factor < -maxMinor;
    if (factorTooBig || minor.abs() > maxMinor ~/ factor.abs()) {
      throw MoneyOverflow(currency, 'times');
    }
    return Money._(currency, minor * factor);
  }

  /// Returns `this * numerator / denominator` rounded with [rounding],
  /// computed exactly on [BigInt]. [denominator] must be positive.
  Money mulDiv(int numerator, int denominator, MoneyRounding rounding) {
    if (denominator <= 0) {
      throw ArgumentError('denominator must be positive');
    }
    final product = BigInt.from(minor) * BigInt.from(numerator);
    final exact = roundDiv(product, BigInt.from(denominator), rounding);
    if (exact.abs() > _maxMinorBig) {
      throw MoneyOverflow(currency, 'mulDiv');
    }
    return Money._(currency, exact.toInt());
  }

  /// Splits this amount in proportion to [weights] with the largest
  /// remainder method; see [largestRemainderSplit] for the guarantees.
  /// The shares always sum to exactly this amount.
  List<Money> allocate(List<int> weights) {
    final shares = largestRemainderSplit(minor, weights);
    return [for (final share in shares) Money._(currency, share)];
  }

  /// Splits this amount into [parts] shares that differ by at most one
  /// minor unit; the larger shares come first.
  List<Money> allocateEven(int parts) {
    if (parts <= 0) {
      throw ArgumentError('parts must be positive');
    }
    return allocate(List<int>.filled(parts, 1));
  }

  @override
  int compareTo(Money other) {
    _requireSame(other);
    return minor.compareTo(other.minor);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  /// The DB column pair `<name>_minor INTEGER`, `<name>_currency TEXT`.
  ({int minor, String currency}) toStorage() {
    return (minor: minor, currency: currency.code);
  }

  /// Loads a stored pair; throws [CorruptMoney] for an unknown currency code
  /// or an out-of-range value.
  static Money fromStorage(int minor, String currencyCode) {
    final currency = Currency.tryOf(currencyCode);
    if (currency == null) {
      throw CorruptMoney(currencyCode, 'unknown currency');
    }
    if (!_inRange(minor)) {
      throw CorruptMoney(currencyCode, 'minor out of range');
    }
    return Money._(currency, minor);
  }

  /// `{'minor': 1250, 'currency': 'KWD'}`; `minor` is always a JSON integer.
  Map<String, Object> toJson() => {'minor': minor, 'currency': currency.code};

  /// Inverse of [toJson]; throws [CorruptMoney] for a missing or non-integer
  /// `minor`, a missing or unknown `currency`, or an out-of-range value.
  static Money fromJson(Map<String, Object?> json) {
    final code = json['currency'];
    final minor = json['minor'];
    if (code is! String) {
      throw CorruptMoney('', 'missing currency');
    }
    if (minor is! int) {
      throw CorruptMoney(code, 'minor is not an integer');
    }
    return fromStorage(minor, code);
  }

  @override
  bool operator ==(Object other) {
    return other is Money && other.minor == minor && other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(currency.code, minor);

  /// Currency code only. The amount is deliberately omitted so a stray
  /// interpolation or log line never leaks a balance (NFR-SEC-03).
  @override
  String toString() => 'Money(${currency.code})';

  void _requireSame(Money other) {
    if (other.currency.code != currency.code) {
      throw CurrencyMismatch(currency, other.currency);
    }
  }

  static final BigInt _maxMinorBig = BigInt.from(maxMinor);

  static bool _inRange(int minor) => minor <= maxMinor && minor >= -maxMinor;

  static int _check(Currency currency, int minor, String op) {
    if (!_inRange(minor)) {
      throw MoneyOverflow(currency, op);
    }
    return minor;
  }
}
