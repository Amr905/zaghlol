import 'currency.dart';

// These are programming or data-integrity bugs, not user errors, so they
// extend Error. Their toString() carries currency codes and enum names only,
// never an amount (NFR-SEC-03: balances are sensitive). The operation and
// reason are enums so no caller can put free text (or an amount) in them.

/// The operation that overflowed, reported by [MoneyOverflow].
enum MoneyOp { create, add, subtract, times, mulDiv, sum }

/// Why a stored or serialized amount could not be loaded.
enum CorruptMoneyReason {
  unknownCurrency,
  outOfRange,
  missingCurrency,
  nonIntegerMinor,
}

/// Arithmetic or ordering across two different currencies (BR-FX-02).
final class CurrencyMismatch extends Error {
  CurrencyMismatch(this.a, this.b);

  final Currency a;
  final Currency b;

  @override
  String toString() => 'CurrencyMismatch: ${a.code} vs ${b.code}';
}

/// A result outside the supported range |minor| <= 2^53 - 1.
final class MoneyOverflow extends Error {
  MoneyOverflow(this.currency, this.op);

  final Currency currency;

  final MoneyOp op;

  @override
  String toString() => 'MoneyOverflow: ${currency.code} in ${op.name}';
}

/// A currency code that is not in the bundled ISO 4217 table.
final class UnknownCurrency extends Error {
  UnknownCurrency(this.code);

  /// The rejected input. Not echoed by [toString] unless it looks like an
  /// ISO code, because callers may pass untrusted text by mistake.
  final String code;

  @override
  String toString() => 'UnknownCurrency: ${_safeCode(code)}';
}

/// A stored or serialized amount that cannot be loaded: unknown currency
/// code, out-of-range minor value or malformed record.
final class CorruptMoney extends Error {
  CorruptMoney(this.code, this.reason);

  /// The stored currency code (may be invalid).
  final String code;

  final CorruptMoneyReason reason;

  @override
  String toString() => 'CorruptMoney: ${_safeCode(code)} (${reason.name})';
}

final RegExp _isoShape = RegExp(r'^[A-Z]{3}$');

// Returns `code` when it has the ISO shape, otherwise a placeholder, so
// error messages never echo arbitrary (possibly sensitive) text.
String _safeCode(String code) {
  return _isoShape.hasMatch(code) ? code : '<invalid code>';
}
