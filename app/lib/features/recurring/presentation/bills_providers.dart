// T-102: providers and actions for S-24 / S-25. Widgets read these; none
// touches the DB. Accept / dismiss of a detected subscription goes through
// RecurringRepository.confirm / dismiss, which also resolve the review item
// (FU-143).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../budget/application/budget_providers.dart' show todayProvider;
import '../../transactions/data/transactions_providers.dart'
    show idGeneratorProvider;
import '../data/recurring_repository.dart';
import 'bills_view.dart';

/// Bumped after any write so the list reloads.
final billsVersionProvider = NotifierProvider<_Version, int>(
  _Version.new,
  name: 'billsVersionProvider',
);

class _Version extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final billsDataProvider = FutureProvider<BillsViewData>((ref) async {
  ref.watch(billsVersionProvider);
  final today = ref.watch(todayProvider);
  final repo = await ref.watch(recurringRepositoryProvider.future);
  return buildBillsView(await repo.list(), today);
}, name: 'billsDataProvider');

/// One stored item, for the edit screen.
final billItemProvider = FutureProvider.family<RecurringItemRow?, String>((
  ref,
  id,
) async {
  final repo = await ref.watch(recurringRepositoryProvider.future);
  final all = await repo.list();
  for (final r in all) {
    if (r.id == id) return r;
  }
  return null;
}, name: 'billItemProvider');

/// The fields S-25 saves.
class BillDraft {
  const BillDraft({
    required this.kind,
    required this.name,
    required this.amount,
    required this.cadence,
    required this.nextDue,
    this.cadenceDays,
    this.totalCount,
    this.paidCount = 0,
    this.reminderDays = defaultReminderDays,
    this.accountId,
  });

  final String kind;
  final String name;
  final Money amount;
  final RecurrenceCadence cadence;
  final int? cadenceDays;
  final CivilDate nextDue;
  final int? totalCount;
  final int paidCount;
  final int reminderDays;
  final String? accountId;
}

/// A storable merchant key for a hand-typed item: the Latin letters and
/// digits of [name], or a key made from [fallbackId] (Arabic names have none).
String billMerchantKey(String name, String fallbackId) {
  final base = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();
  if (base.isNotEmpty) {
    return base.length > 40 ? base.substring(0, 40).trim() : base;
  }
  final id = fallbackId.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return 'bill ${id.length > 12 ? id.substring(0, 12) : id}';
}

class BillsActions {
  BillsActions(this._ref);
  final Ref _ref;

  Future<RecurringRepository> get _repo =>
      _ref.read(recurringRepositoryProvider.future);

  void _changed() => _ref.read(billsVersionProvider.notifier).bump();

  Future<void> accept(String id) async {
    await (await _repo).confirm(id);
    _changed();
  }

  Future<void> dismiss(String id) async {
    await (await _repo).dismiss(id);
    _changed();
  }

  Future<bool> markPaid(String id) async {
    final ok = await (await _repo).markPaidManual(id);
    _changed();
    return ok;
  }

  Future<void> delete(String id) async {
    await (await _repo).deleteItem(id);
    _changed();
  }

  /// Adds ([id] null) or edits. Throws [RecurringException] when invalid.
  Future<void> save(BillDraft d, {String? id, String? merchantNorm}) async {
    final repo = await _repo;
    final dueDay = d.nextDue.day;
    if (id == null) {
      final key = billMerchantKey(d.name, _ref.read(idGeneratorProvider)());
      await repo.addManual(
        kind: d.kind,
        name: d.name,
        amount: d.amount,
        dueDay: dueDay,
        cadence: d.cadence,
        cadenceDays: d.cadenceDays,
        totalCount: d.totalCount,
        paidCount: d.paidCount,
        merchantNorm: key,
        accountId: d.accountId,
        nextDue: d.nextDue,
        reminderDays: d.reminderDays,
      );
    } else {
      await repo.updateManual(
        id,
        kind: d.kind,
        name: d.name,
        amount: d.amount,
        dueDay: dueDay,
        nextDue: d.nextDue,
        cadence: d.cadence,
        cadenceDays: d.cadenceDays,
        totalCount: d.totalCount,
        paidCount: d.paidCount,
        accountId: d.accountId,
        reminderDays: d.reminderDays,
      );
    }
    _changed();
  }
}

final billsActionsProvider = Provider<BillsActions>(
  BillsActions.new,
  name: 'billsActionsProvider',
);
