// T-233: the SMS month-story scenario and the numbers it must produce.
// Pure Dart. The expected numbers are computed ONLY from the scenario's own
// `expect` blocks (never from the app), following the documented counting
// rules (test/fixtures/sms/scenarios/README.md): transfers between own
// accounts are excluded, a cash payment is covered by cash withdrawn earlier
// (the total does not change; the amount moves from Cash to its category),
// declined messages are never counted, currencies are never added together.
// Integer minor units only. Nothing here prints a message body.

import 'dart:convert';

/// One scenario entry (see the README for the format).
final class ScenarioEntry {
  ScenarioEntry._(this.json);

  factory ScenarioEntry.fromJson(Map<String, Object?> j) = ScenarioEntry._;

  final Map<String, Object?> json;

  String get id => json['id']! as String;
  int get monthsAgo => json['monthsAgo']! as int;
  int? get day => json['day'] as int?;
  String? get time => json['time'] as String?;
  String get delivery => json['delivery']! as String;
  String? get sender => json['sender'] as String?;
  String? get rawBody => json['body'] as String?;
  String? get account => json['account'] as String?;
  Map<String, Object?> get _expect => json['expect']! as Map<String, Object?>;

  /// `expense`, `income`, `transfer_out`, `transfer_in`, `refund`, `ignored`.
  String get kind => _expect['kind']! as String;
  bool get ignored => kind == 'ignored';
  int get amountMinor => _expect['amountMinor']! as int;
  String get currency => _expect['currency']! as String;
  String? get merchant => _expect['merchant'] as String?;

  /// Category code without `sys:`; null = uncategorized.
  String? get category => _expect['category'] as String?;
  bool get internal => _expect['internal'] == true;
  String get status => (_expect['status'] as String?) ?? 'posted';
  bool get isLive => delivery == 'live';
  bool get isManual => delivery == 'manual';

  bool get isSpendKind => kind == 'expense' || kind == 'transfer_out';
  bool get isIncomeKind =>
      kind == 'income' || kind == 'transfer_in' || kind == 'refund';

  /// True when the entry counts in totals at all.
  bool get counts => !ignored && status == 'posted' && !internal;

  /// The local instant of the entry. Live entries have no date of their own:
  /// they are "now" ([now]).
  DateTime localAt(DateTime now) {
    if (isLive) return now;
    final idx = now.year * 12 + now.month - 1 - monthsAgo;
    final parts = time!.split(':');
    return DateTime(
      idx ~/ 12,
      idx % 12 + 1,
      day!,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  /// The message text with the date placeholders filled in for [at].
  String bodyAt(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return rawBody!
        .replaceAll(
          '{DD-MM-YYYY}',
          '${two(at.day)}-${two(at.month)}-${at.year}',
        )
        .replaceAll('{HH:MM}', '${two(at.hour)}:${two(at.minute)}');
  }
}

/// The whole scenario.
final class Scenario {
  Scenario(this.entries);

  factory Scenario.parse(String text) {
    final doc = jsonDecode(text) as Map<String, Object?>;
    return Scenario([
      for (final e in doc['entries']! as List<Object?>)
        ScenarioEntry.fromJson((e! as Map).cast<String, Object?>()),
    ]);
  }

  final List<ScenarioEntry> entries;

  ScenarioEntry byId(String id) => entries.firstWhere((e) => e.id == id);
}

/// The numbers of one currency over one period.
final class ExpectedNumbers {
  ExpectedNumbers({
    required this.currency,
    required this.spend,
    required this.income,
    required this.byCategory,
    required this.byMerchant,
    required this.daily,
  });

  final String currency;
  final int spend;
  final int income;
  int get saved => income - spend;

  /// Category code (`null` = uncategorized) -> net spend; a zero row is kept
  /// out.
  final Map<String?, int> byCategory;

  /// Lower-cased merchant -> net spend (rows that have a merchant).
  final Map<String, int> byMerchant;

  /// Local day (`YYYY-MM-DD`) -> spend.
  final Map<String, int> daily;

  /// Basis-point share of [category] in the period's categorized spend,
  /// largest-remainder rounding as the charts do.
  Map<String?, int> sharesBp() {
    final keys = byCategory.keys.toList();
    final amounts = [for (final k in keys) byCategory[k]!];
    final total = amounts.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return {for (final k in keys) k: 0};
    final floors = <int>[];
    final rems = <BigInt>[];
    for (final a in amounts) {
      final p = BigInt.from(a) * BigInt.from(10000);
      floors.add((p ~/ BigInt.from(total)).toInt());
      rems.add(p % BigInt.from(total));
    }
    var left = 10000 - floors.fold<int>(0, (a, b) => a + b);
    final order = List.generate(keys.length, (i) => i)
      ..sort((x, y) {
        final c = rems[y].compareTo(rems[x]);
        return c != 0 ? c : x.compareTo(y);
      });
    for (final i in order) {
      if (left <= 0) break;
      floors[i]++;
      left--;
    }
    return {for (var i = 0; i < keys.length; i++) keys[i]: floors[i]};
  }

  /// The [n] biggest merchants (ties by name) and the rest as "other".
  ({List<MapEntry<String, int>> top, int other}) topMerchants(int n) {
    final all = byMerchant.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final top = all.take(n).toList();
    final other = all.skip(n).fold<int>(0, (a, e) => a + e.value);
    return (top: top, other: other);
  }
}

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Cash cover of every manual cash payment: min(cash pool, payment), the pool
/// being the cash withdrawn (category `cash`, not a cash account) so far.
/// Per currency, ordered by local time (withdrawals before payments).
Map<String, int> cashCovers(Iterable<ScenarioEntry> all, DateTime now) {
  final ev = [
    for (final e in all)
      if (e.counts &&
          e.kind == 'expense' &&
          ((e.isManual && e.account == 'cash' && e.category != 'cash') ||
              (!e.isManual && e.category == 'cash')))
        e,
  ];
  ev.sort((a, b) {
    final c = a.localAt(now).compareTo(b.localAt(now));
    if (c != 0) return c;
    final pa = a.isManual ? 1 : 0, pb = b.isManual ? 1 : 0;
    return pa != pb ? pa.compareTo(pb) : a.id.compareTo(b.id);
  });
  final pool = <String, int>{};
  final out = <String, int>{};
  for (final e in ev) {
    if (!e.isManual) {
      pool[e.currency] = (pool[e.currency] ?? 0) + e.amountMinor;
    } else {
      final p = pool[e.currency] ?? 0;
      final cover = p < e.amountMinor ? p : e.amountMinor;
      pool[e.currency] = p - cover;
      if (cover > 0) out[e.id] = cover;
    }
  }
  return out;
}

/// The numbers of [currency] for the entries dated from [from] to [to]
/// (both inclusive, local days).
ExpectedNumbers expectedFor(
  Scenario s,
  String currency,
  DateTime now, {
  required DateTime from,
  required DateTime to,
}) {
  final covers = cashCovers(s.entries, now);
  final fromDay = DateTime(from.year, from.month, from.day);
  final toDay = DateTime(to.year, to.month, to.day, 23, 59, 59);
  var spend = 0, income = 0;
  final byCat = <String?, int>{};
  final byMer = <String, int>{};
  final daily = <String, int>{};
  for (final e in s.entries) {
    if (!e.counts || e.currency != currency) continue;
    final at = e.localAt(now);
    if (at.isBefore(fromDay) || at.isAfter(toDay)) continue;
    if (e.isIncomeKind) {
      income += e.amountMinor;
      continue;
    }
    final cover = covers[e.id] ?? 0;
    final net = e.amountMinor - cover;
    spend += net;
    byCat[e.category] = (byCat[e.category] ?? 0) + net + cover;
    if (cover > 0) byCat['cash'] = (byCat['cash'] ?? 0) - cover;
    if (e.merchant != null) {
      final k = e.merchant!.toLowerCase();
      byMer[k] = (byMer[k] ?? 0) + net;
    }
    daily[_dayKey(at)] = (daily[_dayKey(at)] ?? 0) + net;
  }
  byCat.removeWhere((_, v) => v == 0);
  return ExpectedNumbers(
    currency: currency,
    spend: spend,
    income: income,
    byCategory: byCat,
    byMerchant: byMer,
    daily: daily,
  );
}

/// The calendar month [monthsAgo] before [now]: first and last day.
({DateTime from, DateTime to}) monthOf(DateTime now, int monthsAgo) {
  final idx = now.year * 12 + now.month - 1 - monthsAgo;
  final y = idx ~/ 12, m = idx % 12 + 1;
  return (from: DateTime(y, m, 1), to: DateTime(y, m + 1, 0));
}

/// Currencies used by counted entries.
Set<String> currenciesOf(Scenario s) => {
  for (final e in s.entries)
    if (e.counts) e.currency,
};
