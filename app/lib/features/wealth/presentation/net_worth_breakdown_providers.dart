// T-199 (D-75): read model for the net worth figure and its breakdown, and
// the write of a user-entered balance. The Money tab figure, the breakdown
// screen and the per-bank balances all read this one result, so they agree.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../../core/settings/settings_keys.dart' as keys;
import '../../gold/application/gating.dart';
import '../data/net_worth_providers.dart';
import '../data/net_worth_repository.dart';
import '../data/prices_providers.dart';
import 'assets_providers.dart';

/// The net worth with every line. Free users: accounts only (credit and BNPL
/// accounts as liabilities); Gold: also assets, gold and installments
/// (design note section 5).
final netWorthBreakdownProvider = FutureProvider<NetWorthBreakdown>((
  ref,
) async {
  final repo = await ref.watch(netWorthRepositoryProvider.future);
  final gold = ref.watch(entitlementStateProvider).isGold;
  return repo.breakdown(goldCurrency: goldCurrency, includeAssets: gold);
}, name: 'netWorthBreakdownProvider');

/// Stores the balance the user typed for (account, amount's currency), true
/// as of now, then refreshes the figures. Throws a code-only exception when
/// the setting cannot hold it.
Future<void> setOpeningBalance(
  WidgetRef ref, {
  required String accountId,
  required Money amount,
}) async {
  final db = await ref.read(appDatabaseProvider.future);
  final now = ref.read(pricesClockProvider)().toUtc();
  final dao = SettingsDao(db);
  final key = keys.Settings.openingBalances;
  await db.transaction(() async {
    final current = key.parse(await dao.read(key.name));
    final next = current.withEntry(accountId, amount, now);
    await dao.write(key.name, key.format(next), at: now.millisecondsSinceEpoch);
  });
  ref.invalidate(netWorthBreakdownProvider);
}
