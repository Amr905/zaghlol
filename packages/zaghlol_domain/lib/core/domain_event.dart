/// Typed events published on the in-process `DomainEventBus`
/// (architecture §Domain events). Events carry identifiers and enums only,
/// never amounts or message text.
sealed class DomainEvent {
  const DomainEvent();
}

/// Transactions were added, edited or removed for the given accounts and
/// payday cycles.
final class TransactionsChanged extends DomainEvent {
  const TransactionsChanged({
    required this.accountIds,
    required this.cycleKeys,
  });

  final Set<String> accountIds;

  /// Payday-cycle keys, for example `2026-11`.
  final Set<String> cycleKeys;
}

/// Spending in a budget crossed a threshold.
final class BudgetThresholdCrossed extends DomainEvent {
  const BudgetThresholdCrossed({
    required this.budgetId,
    required this.thresholdPercent,
  });

  final String budgetId;

  /// The threshold that was crossed, e.g. 80 or 100.
  final int thresholdPercent;
}

/// Captain Zaghlol should react (for example `detective` / `self_transfer`).
final class MascotTrigger extends DomainEvent {
  const MascotTrigger({required this.pose, required this.reason});

  final String pose;
  final String reason;
}

/// The merchant/category catalog changed to a new version.
final class CatalogUpdated extends DomainEvent {
  const CatalogUpdated({required this.version});

  final int version;
}
