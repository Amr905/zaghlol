// T-199: the balances the user typed, one per (account, currency) pair, each
// with the instant it is true for (design note section 2). Stored as the
// `balance.opening` setting, so it travels with backup and restore and needs
// no schema change. Pure Dart; amounts are never logged.
//
// Text form (canonical: sorted keys, no spaces):
//   {"<accountId>":{"<CUR>":[<minor>,<asOfEpochMs>]}}

import 'dart:convert';

import '../money/money.dart';

/// At most this many entries (pairs): the setting is capped at 16 KiB.
const int maxOpeningBalanceEntries = 200;

final class OpeningBalance {
  const OpeningBalance(this.amount, this.asOf);

  /// The balance (asset account) or amount owed (credit, BNPL).
  final Money amount;

  /// UTC instant the figure is true for.
  final DateTime asOf;

  @override
  bool operator ==(Object other) =>
      other is OpeningBalance &&
      other.amount == amount &&
      other.asOf.isAtSameMomentAs(asOf);

  @override
  int get hashCode => Object.hash(amount, asOf.millisecondsSinceEpoch);
}

final class OpeningBalances {
  const OpeningBalances._(this._byAccount);

  static const OpeningBalances empty = OpeningBalances._({});

  // accountId -> currency code -> entry
  final Map<String, Map<String, OpeningBalance>> _byAccount;

  @override
  bool operator ==(Object other) =>
      other is OpeningBalances && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;

  int get length => _byAccount.values.fold(0, (n, m) => n + m.length);

  OpeningBalance? of(String accountId, String currency) =>
      _byAccount[accountId]?[currency];

  /// Every entry of [accountId], by currency code.
  Map<String, OpeningBalance> forAccount(String accountId) =>
      Map.unmodifiable(_byAccount[accountId] ?? const {});

  /// A copy with the entry of (accountId, amount's currency) set. Throws
  /// [ArgumentError] (no value in the message) past
  /// [maxOpeningBalanceEntries] or for an empty id.
  OpeningBalances withEntry(String accountId, Money amount, DateTime asOf) {
    if (accountId.isEmpty) throw ArgumentError('empty account id');
    final next = _copy();
    (next[accountId] ??= {})[amount.currency.code] = OpeningBalance(
      amount,
      asOf.toUtc(),
    );
    final out = OpeningBalances._(next);
    if (out.length > maxOpeningBalanceEntries) {
      throw ArgumentError('too many entries');
    }
    return out;
  }

  /// A copy without the entry of (accountId, currency).
  OpeningBalances without(String accountId, String currency) {
    final next = _copy();
    next[accountId]?.remove(currency);
    if (next[accountId]?.isEmpty ?? false) next.remove(accountId);
    return OpeningBalances._(next);
  }

  /// A copy where the entries of [from] moved to [to] (an account merge): per
  /// currency the newer instant wins, a tie keeps the target's.
  OpeningBalances moveAccount(String from, String to) {
    final src = _byAccount[from];
    if (src == null || from == to) return this;
    final next = _copy();
    final dst = next[to] ??= {};
    for (final e in src.entries) {
      final mine = dst[e.key];
      if (mine == null || e.value.asOf.isAfter(mine.asOf)) dst[e.key] = e.value;
    }
    next.remove(from);
    return OpeningBalances._(next);
  }

  Map<String, Map<String, OpeningBalance>> _copy() => {
    for (final e in _byAccount.entries) e.key: {...e.value},
  };

  String toJson() {
    final ids = _byAccount.keys.toList()..sort();
    final out = <String, Object?>{};
    for (final id in ids) {
      final curs = _byAccount[id]!.keys.toList()..sort();
      out[id] = {
        for (final c in curs)
          c: [
            _byAccount[id]![c]!.amount.minor,
            _byAccount[id]![c]!.asOf.millisecondsSinceEpoch,
          ],
      };
    }
    return jsonEncode(out);
  }

  /// Null for text that is not this form (never thrown, never echoed).
  static OpeningBalances? fromJson(String text) {
    try {
      if (text.length > 16 * 1024) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final out = <String, Map<String, OpeningBalance>>{};
      var n = 0;
      for (final e in decoded.entries) {
        final id = e.key;
        final curs = e.value;
        if (id is! String || id.isEmpty || curs is! Map || curs.isEmpty) {
          return null;
        }
        for (final c in curs.entries) {
          final code = c.key;
          final v = c.value;
          if (code is! String ||
              v is! List ||
              v.length != 2 ||
              v[0] is! int ||
              v[1] is! int) {
            return null;
          }
          final money = Money.tryFromStorage(v[0] as int, code);
          if (money == null) return null;
          (out[id] ??= {})[code] = OpeningBalance(
            money,
            DateTime.fromMillisecondsSinceEpoch(v[1] as int, isUtc: true),
          );
          if (++n > maxOpeningBalanceEntries) return null;
        }
      }
      return OpeningBalances._(out);
    } on Object {
      return null;
    }
  }
}
