// T-083: read model for the Money tab (S-40). Reads the accounts repository
// only; per-currency totals are never summed across currencies.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../recurring/data/recurring_repository.dart';
import '../../wealth/presentation/net_worth_breakdown_providers.dart';
import '../data/accounts_providers.dart';
import '../domain/account.dart';

/// What S-40 shows. [visible] leaves out hidden accounts; [hiddenCount] feeds
/// the "Hidden accounts" entry row. [totals] counts hidden accounts too (D-69).
final class MoneyOverview {
  const MoneyOverview({
    required this.visible,
    required this.hiddenCount,
    required this.totals,
    this.lines = const {},
  });

  final List<AccountWithBalances> visible;
  final int hiddenCount;

  /// Net worth per currency (T-199, D-75): the same figure the breakdown
  /// screen explains. Free: accounts only; Gold: also assets.
  final MultiCurrencyTotal totals;

  /// The balance lines of each account (effective balance and its source),
  /// by account id, ordered by currency code.
  final Map<String, List<BreakdownLine>> lines;

  bool get isEmpty => visible.isEmpty && hiddenCount == 0;
}

final moneyOverviewProvider = FutureProvider<MoneyOverview>((ref) async {
  final repo = await ref.watch(accountsRepositoryProvider.future);
  final all = await repo.listWithBalances(includeHidden: true);
  final worth = await ref.watch(netWorthBreakdownProvider.future);
  final lines = <String, List<BreakdownLine>>{};
  for (final l in worth.lines) {
    final id = l.refId;
    if (l.isAccount && id != null) (lines[id] ??= []).add(l);
  }
  for (final v in lines.values) {
    v.sort((a, b) => a.unit.compareTo(b.unit));
  }
  return MoneyOverview(
    visible: [
      for (final a in all)
        if (!a.account.isHidden) a,
    ],
    hiddenCount: all.where((a) => a.account.isHidden).length,
    totals: MultiCurrencyTotal.of(worth.currencyNets),
    lines: lines,
  );
}, name: 'moneyOverviewProvider');

/// T-197: the next statement due date per credit account (active card-due
/// reminders). Read apart from the overview so a slow or failed lookup only
/// leaves the date out of the row.
final cardDueDatesProvider = FutureProvider<Map<String, CivilDate>>((
  ref,
) async {
  final recurring = await ref.watch(recurringRepositoryProvider.future);
  final out = <String, CivilDate>{};
  for (final r in await recurring.list(status: RecurringStatus.active)) {
    final id = r.accountId;
    if (r.kind != RecurringKind.cardDue || id == null) continue;
    final d = CivilDate.tryParse(r.nextDueDate ?? '');
    if (d == null) continue;
    final cur = out[id];
    if (cur == null || d < cur) out[id] = d;
  }
  return out;
}, name: 'cardDueDatesProvider');
