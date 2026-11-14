// T-145: the typed results T-146 renders (FR-GOLD-02/03, BR-GOLD-05/06,
// D-59, D-61(a), R4-4). No value here carries a token, key or transaction.

/// What a purchase attempt ended as. T-146 owns the wording.
sealed class PurchaseOutcome {
  const PurchaseOutcome();
}

/// The backend verified the payment and the signed entitlement now makes this
/// install Gold (EntitlementService applied it).
final class PurchaseGold extends PurchaseOutcome {
  const PurchaseGold();
}

/// Paid and verified, but the seat is on another phone (D-59, D-61(a)).
/// [accountRequired] is R4-4: sign in with the owning account to move it.
final class PurchaseSeatHeldElsewhere extends PurchaseOutcome {
  const PurchaseSeatHeldElsewhere({
    required this.accountRequired,
    this.nextMoveAt,
  });
  final bool accountRequired;
  final DateTime? nextMoveAt;
}

/// The store (cash payment, Ask to Buy) or the backend reports the purchase
/// as pending. No Gold; BR-GOLD-05.
final class PurchasePending extends PurchaseOutcome {
  const PurchasePending();
}

/// The backend could not be reached or answered with an outage. The purchase
/// stays in the outbox and is retried (BR-GOLD-06); it is not acknowledged.
final class PurchaseQueued extends PurchaseOutcome {
  const PurchaseQueued({this.retryAt});
  final DateTime? retryAt;
}

/// The backend refused the purchase for good (invalid, wrong app, expired,
/// refunded). No Gold.
final class PurchaseInvalid extends PurchaseOutcome {
  const PurchaseInvalid();
}

/// `422 PURCHASE_NOT_OWNED`: the store account paid, but not through this
/// install. T-146 offers Restore.
final class PurchaseNotOwned extends PurchaseOutcome {
  const PurchaseNotOwned();
}

/// The user closed the store sheet, or the store reported an error before any
/// payment. Nothing to verify.
final class PurchaseCancelled extends PurchaseOutcome {
  const PurchaseCancelled();
}
