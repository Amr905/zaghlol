import 'money_errors.dart';
import 'src/iso4217_table.g.dart';

/// Whether a code is on the current ISO 4217 List One snapshot.
///
/// The table is append-only: a code removed from List One in a later refresh
/// stays as [historic] so stored rows and backups that use it still load.
enum CurrencyStatus { active, historic }

/// An ISO 4217 currency with its minor-unit exponent (BR-MON-03).
///
/// Only canonical instances exist (private constructor); obtain them with
/// [Currency.of] or [Currency.tryOf]. Equality and hashing use [code] only.
final class Currency {
  const Currency._(
    this.code,
    this.numeric,
    this.exponent,
    this.status,
    this.isFund,
  );

  /// Alphabetic ISO 4217 code, three uppercase ASCII letters, e.g. `EGP`.
  final String code;

  /// Numeric ISO 4217 code, e.g. 818 for EGP.
  final int numeric;

  /// Number of minor-unit digits (ISO "minor unit"), 0..4.
  final int exponent;

  /// [CurrencyStatus.active] when the code is on the bundled List One.
  final CurrencyStatus status;

  /// True for ISO 4217 funds codes (BOV, CLF, UYW, ...). Pickers list them
  /// last (FR-CUR-07, D-51).
  final bool isFund;

  /// Featured currencies in A-59 order, shown first in pickers (FR-CUR-01,
  /// FR-CUR-07): the D-22 eight plus GBP and INR.
  static const List<String> featuredCodes = [
    'EGP',
    'USD',
    'SAR',
    'EUR',
    'AED',
    'QAR',
    'KWD',
    'BHD',
    'GBP',
    'INR',
  ];

  static final Map<String, Currency> _byCode = _buildTable();

  static Map<String, Currency> _buildTable() {
    final table = <String, Currency>{};
    for (final (code, numeric, exponent, active, fund) in iso4217Table) {
      final status = active ? CurrencyStatus.active : CurrencyStatus.historic;
      table[code] = Currency._(code, numeric, exponent, status, fund);
    }
    return table;
  }

  /// The canonical currency for [code]; throws [UnknownCurrency] otherwise.
  ///
  /// Use this only for codes that are known to be valid (constants, values
  /// read back through [tryOf]). Untrusted input goes through [tryOf].
  static Currency of(String code) {
    final currency = _byCode[code];
    if (currency == null) {
      throw UnknownCurrency(code);
    }
    return currency;
  }

  /// The canonical currency for [code], or null.
  ///
  /// Strict: uppercase ASCII only, no trimming or case folding.
  static Currency? tryOf(String code) => _byCode[code];

  /// Every currency in the table (active and historic), sorted by code.
  static Iterable<Currency> get all => _byCode.values;

  /// Active currencies, sorted by code. Historic codes are excluded, so this
  /// is what pickers offer.
  static Iterable<Currency> get active {
    return _byCode.values.where((c) => c.status == CurrencyStatus.active);
  }

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}
