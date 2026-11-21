// FU-158a: the EC-40 repair runs inside the edit's own transaction, so its
// `TransactionsChanged` must not be published until the edit committed. This
// holds it back and releases it from the repository's after-commit hook.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../application/reimbursements.dart';

final class AmountRepairEvents {
  AmountRepairEvents(this._reimbursements);

  final Reimbursements _reimbursements;
  final List<TransactionsChanged> _pending = [];

  /// The repository's `onAmountChange`: repairs the links, keeps the event.
  Future<List<String>> onAmountChange(String id, int minor) async {
    final r = await _reimbursements.repairForNewAmount(id, minor);
    final e = r.event;
    if (e != null) _pending.add(e);
    return r.removedLinkIds;
  }

  /// The edit rolled back: its repair never happened, so drop the event.
  void discard() => _pending.clear();

  /// After the edit committed: publishes what the repair changed (the cycles
  /// and accounts of the removed links), so budgets and Home refresh.
  void flush(DomainEventBus bus) {
    final events = List.of(_pending);
    _pending.clear();
    events.forEach(bus.publish);
  }
}
