// T-199: the balance of one (account, currency) pair and the net worth
// breakdown (D-75, FR-WLT-01, BR-WLT-01). Pure Dart. The rules are written
// out in docs/03-technical/design-notes/T-199.md; in short:
//
//   balance now = newest known anchor (reported or user-entered)
//                 + the counted transactions dated strictly after it.
//
// - A pair is one account in one currency; nothing here converts or sums
//   across currencies.
// - A pair with no anchor is `unknown`: it is left out of every total and
//   listed, never guessed and never zero.
// - Credit and BNPL accounts are liabilities: the figure is the amount owed,
//   and a transaction moves it the other way from a cash account.
// - Amounts and labels are financial data: nothing here logs them, and
//   failures are codes only ([NetWorthOverflow]).

import '../money/currency.dart';
import '../money/money.dart';
import '../money/money_errors.dart';
import 'net_worth.dart';

/// Where a line's figure comes from (design note section 1).
enum BalanceSource {
  /// The balance a bank message reported; nothing counted after it.
  reported,

  /// The balance the user typed; nothing counted after it.
  userEntered,

  /// An anchor plus the counted transactions dated after it.
  computed,

  /// No usable anchor: excluded from every total.
  unknown,

  /// A live asset's own value (manual value, certificate principal, gold).
  asset,

  /// Remaining installments: (total - paid) x amount.
  installments,
}

/// A reported or user-entered balance is stale when it is older than this
/// and nothing was counted after it (design note section 4).
const int balanceStaleAfterDays = 30;

/// +1, -1 or 0: the effect of a transaction direction on the cash side of
/// its account. An unknown direction code counts as 0 (fail closed: it moves
/// nothing).
int cashSignOfDirection(String direction) => switch (direction) {
  'income' || 'refund' || 'transfer_in' => 1,
  'expense' || 'fee' || 'transfer_out' => -1,
  _ => 0,
};

/// Which figure an anchor was taken from (shown in the line's source text).
enum AnchorBasis {
  /// The bank message's balance (for a card: the amount owed).
  reportedBalance,

  /// An asset account's available balance (no balance in the message).
  reportedAvailable,

  /// A card's owed amount derived as limit minus available.
  limitMinusAvailable,

  /// The figure the user typed.
  userEntered,
}

/// A known balance a computation starts from.
final class BalanceAnchor {
  const BalanceAnchor({
    required this.amount,
    required this.asOf,
    required this.userEntered,
    this.basis,
  });

  /// The figure used; defaults to the balance (or the user's entry).
  final AnchorBasis? basis;

  AnchorBasis get effectiveBasis =>
      basis ??
      (userEntered ? AnchorBasis.userEntered : AnchorBasis.reportedBalance);

  /// The balance (asset accounts) or the amount owed (liabilities).
  final Money amount;

  /// UTC instant the figure is true for.
  final DateTime asOf;
  final bool userEntered;
}

/// The anchor of a pair, or null when there is none ([BalanceSource.unknown]).
///
/// Reported (an `account_balances` row), asset account: [reportedBalance],
/// else [reportedAvailable] (own basis). Liability (credit, BNPL): the stored
/// balance is NEVER the owed amount (card messages put "available balance"
/// wording there); owed = limit - (balance ?? available) in the same
/// currency, floored at 0, and without a limit there is no reported anchor.
/// The user's entry (the owed amount for a card) competes by instant: the
/// newer wins, a tie goes to the reported one; an entry dated after [now] is
/// treated as dated [now] (it never beats a later bank message). Any figure
/// in another currency is ignored (never converted).
BalanceAnchor? pickAnchor({
  required Currency currency,
  required bool isLiability,
  Money? reportedBalance,
  Money? reportedAvailable,
  Money? creditLimit,
  DateTime? reportedAsOf,
  Money? userBalance,
  DateTime? userAsOf,
  DateTime? now,
}) {
  BalanceAnchor? reported;
  if (reportedAsOf != null) {
    if (!isLiability) {
      final b = reportedBalance;
      final av = reportedAvailable;
      if (b != null && b.currency == currency) {
        reported = BalanceAnchor(
          amount: b,
          asOf: reportedAsOf.toUtc(),
          userEntered: false,
          basis: AnchorBasis.reportedBalance,
        );
      } else if (b == null && av != null && av.currency == currency) {
        reported = BalanceAnchor(
          amount: av,
          asOf: reportedAsOf.toUtc(),
          userEntered: false,
          basis: AnchorBasis.reportedAvailable,
        );
      }
    } else {
      final avail = reportedBalance ?? reportedAvailable;
      if (avail != null &&
          creditLimit != null &&
          avail.currency == currency &&
          creditLimit.currency == currency) {
        final used = creditLimit - avail;
        reported = BalanceAnchor(
          amount: used.isNegative ? Money(currency, 0) : used,
          asOf: reportedAsOf.toUtc(),
          userEntered: false,
          basis: AnchorBasis.limitMinusAvailable,
        );
      }
    }
  }
  BalanceAnchor? user;
  if (userBalance != null &&
      userAsOf != null &&
      userBalance.currency == currency) {
    final when = userAsOf.toUtc();
    user = BalanceAnchor(
      amount: userBalance,
      asOf: now != null && when.isAfter(now.toUtc()) ? now.toUtc() : when,
      userEntered: true,
    );
  }
  if (reported == null) return user;
  if (user == null) return reported;
  return user.asOf.isAfter(reported.asOf) ? user : reported;
}

/// The counted transactions after an anchor, as one signed cash-side total.
final class TxnTotals {
  const TxnTotals({this.cashEffectMinor = 0, this.count = 0});
  final int cashEffectMinor;
  final int count;
}

/// One account balance line of the breakdown.
final class BreakdownLine {
  const BreakdownLine({
    required this.group,
    required this.unit,
    required this.label,
    required this.source,
    this.refId,
    this.institutionCode,
    this.accountKind,
    this.isHidden = false,
    this.amount,
    this.quantityMilli,
    this.asOf,
    this.sinceCount = 0,
    this.stale = false,
    this.basis,
    this.last4,
  });

  /// The card's last digits (accounts only); display only.
  final String? last4;

  /// The figure the anchor came from (accounts with a figure only).
  final AnchorBasis? basis;

  final BreakdownGroup group;

  /// Currency code or gold symbol.
  final String unit;

  /// The account or asset name. In-memory only: never logged.
  final String label;
  final BalanceSource source;

  /// The account id (accounts) or asset id; null for derived lines.
  final String? refId;
  final String? institutionCode;

  /// The account kind code, when the line is an account.
  final String? accountKind;
  final bool isHidden;

  /// The figure for a currency unit; null when excluded or when the line is
  /// gold in its native unit.
  final Money? amount;

  /// Gold in its own unit (grams x 1000, coins x 1000).
  final int? quantityMilli;

  /// The anchor instant (reported, user-entered, computed).
  final DateTime? asOf;

  /// How many transactions were added to the anchor.
  final int sinceCount;
  final bool stale;

  bool get isLiability => group == BreakdownGroup.liabilities;
  bool get isIncluded => amount != null || quantityMilli != null;
  bool get isExcluded => !isIncluded;
  bool get isAccount => accountKind != null;
}

enum BreakdownGroup { accounts, assets, liabilities }

/// The line of one (account, currency) pair. [anchor] null is the `unknown`
/// line. [totals] are the counted transactions after `anchor.asOf`.
/// [liabilityKind] accounts (credit, BNPL) are liabilities: the owed amount
/// moves opposite to the cash-side effect. [now] decides staleness.
BreakdownLine resolveAccountLine({
  required String accountId,
  required String label,
  required String accountKind,
  required Currency currency,
  required bool isLiability,
  required DateTime now,
  BalanceAnchor? anchor,
  TxnTotals totals = const TxnTotals(),
  String? institutionCode,
  String? last4,
  bool isHidden = false,
}) {
  final group = isLiability
      ? BreakdownGroup.liabilities
      : BreakdownGroup.accounts;
  if (anchor == null) {
    return BreakdownLine(
      group: group,
      unit: currency.code,
      label: label,
      source: BalanceSource.unknown,
      refId: accountId,
      institutionCode: institutionCode,
      accountKind: accountKind,
      isHidden: isHidden,
      last4: last4,
    );
  }
  Money amount;
  try {
    amount = totals.count == 0
        ? anchor.amount
        : Money(
            currency,
            anchor.amount.minor +
                (isLiability
                    ? -totals.cashEffectMinor
                    : totals.cashEffectMinor),
          );
  } on MoneyOverflow {
    throw NetWorthOverflow();
  }
  final age = now.toUtc().difference(anchor.asOf).inDays;
  final computed = totals.count > 0;
  return BreakdownLine(
    group: group,
    unit: currency.code,
    label: label,
    source: computed
        ? BalanceSource.computed
        : (anchor.userEntered
              ? BalanceSource.userEntered
              : BalanceSource.reported),
    refId: accountId,
    institutionCode: institutionCode,
    accountKind: accountKind,
    isHidden: isHidden,
    amount: amount,
    asOf: anchor.asOf,
    sinceCount: totals.count,
    basis: anchor.effectiveBasis,
    last4: last4,
    stale: !computed && age > balanceStaleAfterDays,
  );
}

/// One currency or gold unit of the breakdown.
final class UnitBreakdown {
  const UnitBreakdown({
    required this.unit,
    required this.accounts,
    required this.assets,
    required this.liabilities,
    required this.excluded,
    required this.assetsMinor,
    required this.liabilitiesMinor,
  });

  final String unit;

  /// Included account lines (asset-kind accounts), assets side.
  final List<BreakdownLine> accounts;

  /// Included asset lines (live assets, gold).
  final List<BreakdownLine> assets;

  /// Included liability lines (cards, BNPL, installments, liability assets).
  final List<BreakdownLine> liabilities;

  /// Lines with no figure: in no total.
  final List<BreakdownLine> excluded;
  final int assetsMinor;
  final int liabilitiesMinor;
  int get netMinor => assetsMinor - liabilitiesMinor;
  bool get isGold => GoldSymbols.isGold(unit);
}

/// The units of [lines], currencies by code then gold symbols, each with its
/// lines and totals. Unit totals are the sums of exactly the included lines,
/// the same lines [computeNetWorth] is fed ([moneyLinesOf], [goldLinesOf]).
List<UnitBreakdown> buildUnitBreakdowns(Iterable<BreakdownLine> lines) {
  final byUnit = <String, List<BreakdownLine>>{};
  for (final l in lines) {
    byUnit.putIfAbsent(l.unit, () => []).add(l);
  }
  final units = byUnit.keys.toList()
    ..sort((a, b) {
      final ga = GoldSymbols.isGold(a);
      final gb = GoldSymbols.isGold(b);
      if (ga != gb) return ga ? 1 : -1;
      return a.compareTo(b);
    });
  int add(int sum, int v) {
    final s = sum + v;
    if (s > Money.maxMinor || s < -Money.maxMinor) throw NetWorthOverflow();
    return s;
  }

  return [
    for (final u in units)
      () {
        final ls = byUnit[u]!;
        var assets = 0;
        var liabilities = 0;
        for (final l in ls) {
          final v = l.amount?.minor ?? l.quantityMilli;
          if (v == null) continue;
          if (l.isLiability) {
            liabilities = add(liabilities, v);
          } else {
            assets = add(assets, v);
          }
        }
        if ((assets - liabilities).abs() > Money.maxMinor) {
          throw NetWorthOverflow();
        }
        return UnitBreakdown(
          unit: u,
          accounts: [
            for (final l in ls)
              if (l.isIncluded && !l.isLiability && l.isAccount) l,
          ],
          assets: [
            for (final l in ls)
              if (l.isIncluded && !l.isLiability && !l.isAccount) l,
          ],
          liabilities: [
            for (final l in ls)
              if (l.isIncluded && l.isLiability) l,
          ],
          excluded: [
            for (final l in ls)
              if (l.isExcluded) l,
          ],
          assetsMinor: assets,
          liabilitiesMinor: liabilities,
        );
      }(),
  ];
}

/// The included currency lines as [MoneyLine]s for [computeNetWorth].
List<MoneyLine> moneyLinesOf(Iterable<BreakdownLine> lines) => [
  for (final l in lines)
    if (l.amount != null) MoneyLine(l.amount!, isLiability: l.isLiability),
];

/// The included gold lines as [GoldLine]s for [computeNetWorth].
List<GoldLine> goldLinesOf(Iterable<BreakdownLine> lines) => [
  for (final l in lines)
    if (l.quantityMilli != null) GoldLine(l.unit, l.quantityMilli!),
];

/// A bank (institution) with its asset accounts in one unit.
final class BankGroup {
  const BankGroup({
    required this.key,
    required this.institutionCode,
    required this.lines,
    required this.totalMinor,
  });

  /// The institution code, or `acct:<id>` for an account with none.
  final String key;
  final String? institutionCode;
  final List<BreakdownLine> lines;

  /// Sum of the lines' known balances in the unit (never across units).
  final int totalMinor;

  /// True when a member has no known balance: the total is not all accounts.
  bool get isPartial => lines.any((l) => l.isExcluded);
}

/// Groups account lines of ONE unit by bank, in first-seen order. An account
/// without an institution is its own group. Excluded lines are kept in their
/// group but add nothing to its total.
List<BankGroup> groupByBank(Iterable<BreakdownLine> accountLines) {
  final order = <String>[];
  final byKey = <String, List<BreakdownLine>>{};
  for (final l in accountLines) {
    final key = l.institutionCode ?? 'acct:${l.refId ?? l.label}';
    if (!byKey.containsKey(key)) order.add(key);
    byKey.putIfAbsent(key, () => []).add(l);
  }
  return [
    for (final k in order)
      () {
        var total = 0;
        for (final l in byKey[k]!) {
          final v = l.amount?.minor;
          if (v == null) continue;
          total += v;
          if (total > Money.maxMinor || total < -Money.maxMinor) {
            throw NetWorthOverflow();
          }
        }
        return BankGroup(
          key: k,
          institutionCode: byKey[k]!.first.institutionCode,
          lines: byKey[k]!,
          totalMinor: total,
        );
      }(),
  ];
}
