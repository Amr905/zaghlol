import 'currency.dart';
import 'money_errors.dart';
import 'rounding.dart';
import 'src/allocation.dart';

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
  Money(this.currency, int minor) : minor = _check(currency, minor, _create);

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

  /// Longest input [parse] looks at; anything longer is rejected before any
  /// matching or copying (a sign, 16 digits, a point and 4 decimals fit
  /// with room for leading zeros).
  static const int maxParseLength = 64;

  /// Parses the accepted ASCII form `-?[0-9]+(\.[0-9]{1,e})?` where `e` is
  /// the currency exponent (no `.` when `e` is 0).
  ///
  /// No `+`, grouping, whitespace, exponent notation or non-ASCII digits:
  /// callers normalize first (T-013). More fraction digits than `e` is an
  /// error, never rounded. Fewer digits are padded (EGP `1.5` is 150).
  /// Throws [FormatException], also when the amount is out of range or the
  /// text is longer than [maxParseLength]. The exception never contains the
  /// input.
  ///
  /// Parsing normalizes: `01.5`, `1.50` and `1.5` give the same value, and
  /// `-0` gives zero, so `toCanonicalString(parse(s)) == s` does not hold in
  /// general. Duplicate detection must key on [toStorage], never on the
  /// source text.
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
    if (text.length > maxParseLength) {
      return null;
    }
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
    return Money._(currency, _check(currency, result, MoneyOp.add));
  }

  Money operator -(Money other) {
    _requireSame(other);
    final result = minor - other.minor;
    return Money._(currency, _check(currency, result, _subtract));
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
      throw MoneyOverflow(currency, MoneyOp.times);
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
      throw MoneyOverflow(currency, MoneyOp.mulDiv);
    }
    return Money._(currency, exact.toInt());
  }

  /// Splits this amount in proportion to [weights] with the largest
  /// remainder (Hamilton) method.
  ///
  /// The shares always sum to exactly this amount, zero weights get zero,
  /// each share is within one minor unit of its exact quota, leftover units
  /// go to the largest remainders (ties: lower index first, never a zero
  /// weight), and `(-x).allocate(w)` is `x.allocate(w)` negated.
  /// Throws [ArgumentError] when [weights] is empty, longer than
  /// [maxAllocationParts], has a negative entry or sums to zero.
  List<Money> allocate(List<int> weights) {
    final shares = largestRemainderSplit(minor, weights);
    return [for (final share in shares) Money._(currency, share)];
  }

  /// Splits this amount into [parts] shares that differ by at most one
  /// minor unit; lower indices receive the extra unit.
  ///
  /// Throws [ArgumentError] unless `1 <= parts <= maxAllocationParts`; the
  /// bound is checked before anything is allocated.
  List<Money> allocateEven(int parts) {
    if (parts <= 0 || parts > maxAllocationParts) {
      throw ArgumentError('parts must be in 1..$maxAllocationParts');
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
  ///
  /// WARNING: contains the amount; never log it, interpolate it into a
  /// message or attach it to an error (NFR-SEC-03).
  ({int minor, String currency}) toStorage() {
    return (minor: minor, currency: currency.code);
  }

  /// Loads a stored pair; throws [CorruptMoney] for an unknown currency code
  /// or an out-of-range value. Untrusted rows go through [tryFromStorage].
  static Money fromStorage(int minor, String currencyCode) {
    final result = tryFromStorage(minor, currencyCode);
    if (result != null) {
      return result;
    }
    if (Currency.tryOf(currencyCode) == null) {
      throw CorruptMoney(currencyCode, CorruptMoneyReason.unknownCurrency);
    }
    throw CorruptMoney(currencyCode, CorruptMoneyReason.outOfRange);
  }

  /// Boundary loader: null for an unknown (or lowercase) currency code or an
  /// out-of-range value, instead of throwing.
  static Money? tryFromStorage(int minor, String currencyCode) {
    final currency = Currency.tryOf(currencyCode);
    if (currency == null || !_inRange(minor)) {
      return null;
    }
    return Money._(currency, minor);
  }

  /// `{'minor': 1250, 'currency': 'KWD'}`; `minor` is always a JSON integer.
  ///
  /// WARNING: contains the amount; never log it, interpolate it into a
  /// message or attach it to an error (NFR-SEC-03).
  Map<String, Object> toJson() => {'minor': minor, 'currency': currency.code};

  /// Inverse of [toJson]; throws [CorruptMoney] for a missing or non-integer
  /// `minor`, a missing or unknown `currency`, or an out-of-range value.
  /// Extra keys are ignored. Untrusted input goes through [tryFromJson].
  static Money fromJson(Map<String, Object?> json) {
    final code = json['currency'];
    final minor = json['minor'];
    if (code is! String) {
      throw CorruptMoney('', CorruptMoneyReason.missingCurrency);
    }
    if (minor is! int) {
      throw CorruptMoney(code, CorruptMoneyReason.nonIntegerMinor);
    }
    return fromStorage(minor, code);
  }

  /// Boundary loader for untrusted JSON (backups, imports): null for a
  /// missing key, a wrong type, an unknown or lowercase code or an
  /// out-of-range value. Extra keys are ignored, as in [fromJson].
  static Money? tryFromJson(Map<String, Object?> json) {
    final code = json['currency'];
    final minor = json['minor'];
    if (code is! String || minor is! int) {
      return null;
    }
    return tryFromStorage(minor, code);
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

  static const MoneyOp _create = MoneyOp.create;
  static const MoneyOp _subtract = MoneyOp.subtract;

  static int _check(Currency currency, int minor, MoneyOp op) {
    if (!_inRange(minor)) {
      throw MoneyOverflow(currency, op);
    }
    return minor;
  }
}
