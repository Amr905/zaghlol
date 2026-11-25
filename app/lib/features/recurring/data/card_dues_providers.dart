// T-245: the latest due notice of a card, for its detail screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../accounts/domain/card_due.dart';
import '../../transactions/data/transactions_providers.dart'
    show clockProvider, idGeneratorProvider;
import 'card_dues.dart';

/// The stored due of the credit card [accountId]; null when it has none.
final cardDueProvider = FutureProvider.family<CardDue?, String>((
  ref,
  accountId,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final card = await (db.select(
    db.accounts,
  )..where((a) => a.id.equals(accountId))).getSingleOrNull();
  final inst = card?.institutionCode;
  final last4 = card?.last4;
  if (card == null || card.kind != 'credit' || inst == null || last4 == null) {
    return null;
  }
  final clock = ref.watch(clockProvider);
  return CardDues(
    db,
    nowMs: () => clock().toUtc().millisecondsSinceEpoch,
    newId: ref.watch(idGeneratorProvider),
  ).read(inst, last4);
}, name: 'cardDueProvider');
