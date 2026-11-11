// T-074: Riverpod wiring (ADR-001) for the rules repository.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../../../core/db/daos/merchant_rules_dao.dart' show MerchantRulesDao;
import '../../transactions/data/transactions_providers.dart';
import '../domain/merchant_rule.dart';
import 'rules_repository.dart';

final rulesRepositoryProvider = FutureProvider<RulesRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftRulesRepository(
    MerchantRulesDao(db),
    CategoriesDao(db),
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  );
}, name: 'rulesRepositoryProvider');
