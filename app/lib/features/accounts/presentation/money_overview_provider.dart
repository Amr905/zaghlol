// T-083: read model for the Money tab (S-40). Reads the accounts repository
// only; per-currency totals are never summed across currencies.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../data/accounts_providers.dart';
import '../domain/account.dart';

/// What S-40 shows. [visible] leaves out hidden accounts; [hiddenCount] feeds
/// the "Hidden accounts" entry row. [totals] counts hidden accounts too (D-69).
final class MoneyOverview {
  const MoneyOverview({
    required this.visible,
    required this.hiddenCount,
    required this.totals,
  });

  final List<AccountWithBalances> visible;
  final int hiddenCount;

  /// Net worth per currency from the accounts only (asset accounts).
  final MultiCurrencyTotal totals;

  bool get isEmpty => visible.isEmpty && hiddenCount == 0;
}

final moneyOverviewProvider = FutureProvider<MoneyOverview>((ref) async {
  final repo = await ref.watch(accountsRepositoryProvider.future);
  final all = await repo.listWithBalances(includeHidden: true);
  final totals = await repo.totalsByCurrency();
  return MoneyOverview(
    visible: [
      for (final a in all)
        if (!a.account.isHidden) a,
    ],
    hiddenCount: all.where((a) => a.account.isHidden).length,
    totals: MultiCurrencyTotal.of(totals.values),
  );
}, name: 'moneyOverviewProvider');
