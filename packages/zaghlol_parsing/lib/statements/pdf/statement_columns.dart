// T-156: what each column of a statement table means, and the per-bank
// template that remembers it. Pure Dart. A template holds geometry and
// choices only: never text from a statement.

import 'dart:convert';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../normalize/amount_parser.dart';

enum StatementColumnRole {
  date,
  description,
  debit,
  credit,

  /// One signed column (negative or `DR` = money out).
  amount,
  balance,
  ignore,
}

/// The user's (or the header's) answer to "which column is what", plus the
/// statement-wide choices that are not visible in a column.
final class StatementMapping {
  const StatementMapping({
    required this.roles,
    required this.currency,
    this.dayFirst = true,
    this.numberLocale = NumberLocale.standard,
  });

  final List<StatementColumnRole> roles;
  final Currency currency;

  /// `05/01/2026` is 5 January when true.
  final bool dayFirst;
  final NumberLocale numberLocale;

  int _count(StatementColumnRole r) => roles.where((x) => x == r).length;

  int indexOf(StatementColumnRole r) => roles.indexOf(r);

  /// A mapping the row parser can use: one date, one description, at most
  /// one balance, and money either in one signed column or in debit and/or
  /// credit columns (not both styles).
  bool get isValid {
    if (_count(StatementColumnRole.date) != 1 ||
        _count(StatementColumnRole.description) != 1 ||
        _count(StatementColumnRole.balance) > 1 ||
        _count(StatementColumnRole.debit) > 1 ||
        _count(StatementColumnRole.credit) > 1 ||
        _count(StatementColumnRole.amount) > 1) {
      return false;
    }
    final signed = _count(StatementColumnRole.amount) == 1;
    final split =
        _count(StatementColumnRole.debit) + _count(StatementColumnRole.credit);
    return signed ? split == 0 : split > 0;
  }

  StatementMapping copyWith({
    List<StatementColumnRole>? roles,
    Currency? currency,
    bool? dayFirst,
    NumberLocale? numberLocale,
  }) => StatementMapping(
    roles: roles ?? this.roles,
    currency: currency ?? this.currency,
    dayFirst: dayFirst ?? this.dayFirst,
    numberLocale: numberLocale ?? this.numberLocale,
  );

  @override
  String toString() => 'StatementMapping';
}

/// Per-bank saved layout: where the column edges are and what the columns
/// mean. Stored in the encrypted database, never uploaded.
final class StatementTemplate {
  const StatementTemplate({
    required this.bankKey,
    required this.cutPoints,
    required this.mapping,
  });

  /// Stable key of the bank source (`cib`, `nbe`, ...), `[a-z0-9_]{1,32}`.
  final String bankKey;

  /// Column edges in permille of the page width, ascending; one fewer than
  /// the number of columns.
  final List<double> cutPoints;
  final StatementMapping mapping;

  static final RegExp _key = RegExp(r'^[a-z0-9_]{1,32}$');
  static const int _maxColumns = 16;

  String toJson() => jsonEncode({
    'v': 1,
    'bank': bankKey,
    'cuts': cutPoints,
    'roles': [for (final r in mapping.roles) r.name],
    'currency': mapping.currency.code,
    'dayFirst': mapping.dayFirst,
    'locale': mapping.numberLocale.name,
  });

  /// Null for anything that is not a valid template (corrupt or old data is
  /// ignored, the user just maps again).
  static StatementTemplate? tryFromJson(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['v'] != 1) return null;
      final bank = j['bank'];
      final cuts = j['cuts'];
      final roles = j['roles'];
      final currency = j['currency'];
      final dayFirst = j['dayFirst'];
      final locale = j['locale'];
      if (bank is! String ||
          !_key.hasMatch(bank) ||
          cuts is! List ||
          roles is! List ||
          currency is! String ||
          dayFirst is! bool ||
          locale is! String ||
          roles.length < 2 ||
          roles.length > _maxColumns ||
          cuts.length != roles.length - 1) {
        return null;
      }
      final cutValues = <double>[];
      for (final c in cuts) {
        if (c is! num) return null;
        final d = c.toDouble();
        if (d < 0 || d > 1000) return null;
        if (cutValues.isNotEmpty && d <= cutValues.last) return null;
        cutValues.add(d);
      }
      final roleValues = <StatementColumnRole>[];
      for (final r in roles) {
        final v = StatementColumnRole.values.where((x) => x.name == r);
        if (v.isEmpty) return null;
        roleValues.add(v.single);
      }
      final cur = Currency.tryOf(currency);
      final nl = NumberLocale.values.where((x) => x.name == locale);
      if (cur == null || nl.isEmpty) return null;
      final mapping = StatementMapping(
        roles: roleValues,
        currency: cur,
        dayFirst: dayFirst,
        numberLocale: nl.single,
      );
      return mapping.isValid
          ? StatementTemplate(
              bankKey: bank,
              cutPoints: cutValues,
              mapping: mapping,
            )
          : null;
    } on Object {
      return null;
    }
  }

  @override
  String toString() => 'StatementTemplate($bankKey)';
}
