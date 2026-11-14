// T-163: read models for S-63/S-64. Widgets read these; the database is only
// reached through the repositories behind them.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/categories_admin.dart';
import '../data/rules_providers.dart';
import '../domain/merchant_rule.dart';

final categoryItemsProvider = FutureProvider.autoDispose<List<CategoryItem>>(
  (ref) async => (await ref.watch(categoriesAdminProvider.future)).list(),
);

final rulesListProvider = FutureProvider.autoDispose<List<MerchantRule>>(
  (ref) async => (await ref.watch(rulesRepositoryProvider.future)).list(),
);
