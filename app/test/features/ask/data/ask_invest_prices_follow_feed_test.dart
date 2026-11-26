// B96-m3: the invest prices follow the price feed (a sync updates them) and
// a quote keeps its own as-of (the stale pill). Synthetic data.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/ask/data/llm_ask_providers.dart';
import 'package:zaghlol/features/wealth/data/prices_providers.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';

Map<String, Object?> _block(DateTime asOf, String gold24) => {
  'asOf': asOf.toIso8601String(),
  'stale': false,
  'gold': [
    {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': gold24},
  ],
  'fx': {
    'base': 'USD',
    'rates': {'EGP': '48.95'},
  },
};

void main() {
  test('after a feed update the provider gives the new quotes', () async {
    final db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 11, 3, 16);
    final repo = PricesRepository(db: db, clock: () => now);
    final c = ProviderContainer(
      overrides: [pricesRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(c.dispose);
    final sub = c.listen(askInvestPricesProvider, (_, _) {});
    addTearDown(sub.close);

    await repo.apply(_block(DateTime.utc(2026, 11, 3, 15), '5000.00'));
    final first = await c.read(askInvestPricesProvider.future);
    expect(first.gold.single.pricePerGram.minor, 500000);

    await repo.apply(_block(DateTime.utc(2026, 11, 3, 15, 30), '5100.00'));
    c.invalidate(askInvestPricesProvider);
    final second = await c.read(askInvestPricesProvider.future);
    expect(second.gold.single.pricePerGram.minor, 510000);
    expect(second.gold.single.asOf, DateTime.utc(2026, 11, 3, 15, 30));
  });
}
