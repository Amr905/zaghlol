// T-145: the typed results of a restore (FR-GOLD-02/03/08/09, D-52…D-55,
// EC-64…EC-69) that T-146/T-147 render. No value carries a token or key.

sealed class RestoreOutcome {
  const RestoreOutcome();
}

/// Verified and applied: this install is Gold. [movedFromOtherPhone] is true
/// when the seat came from another install (the app says Gold left it).
final class RestoreGold extends RestoreOutcome {
  const RestoreGold({required this.movedFromOtherPhone});
  final bool movedFromOtherPhone;
}

/// The store lists nothing to restore for this account (nothing was sent).
final class RestoreNothingToRestore extends RestoreOutcome {
  const RestoreNothingToRestore();
}

/// `409 MOVE_COOLDOWN` (EC-68): the seat can move at [nextMoveAt] (whole UTC
/// hour). Never retried automatically.
final class RestoreMoveCooldown extends RestoreOutcome {
  const RestoreMoveCooldown({this.nextMoveAt});
  final DateTime? nextMoveAt;
}

/// The purchase is account-linked: sign in with the account that bought Gold
/// (EC-65; the account is never named).
final class RestoreAccountRequired extends RestoreOutcome {
  const RestoreAccountRequired();
}

final class RestorePending extends RestoreOutcome {
  const RestorePending();
}

/// Expired, refunded or invalid at the store.
final class RestoreNotGold extends RestoreOutcome {
  const RestoreNotGold();
}

/// Transient trouble: network, a platform attestation hiccup, a store or
/// backend outage. Try again later. [playServicesOutdated] offers the Play
/// services update.
final class RestoreTryLater extends RestoreOutcome {
  const RestoreTryLater({this.retryAfter, this.playServicesOutdated = false});
  final Duration? retryAfter;
  final bool playServicesOutdated;
}

/// Attestation failed for good (after the one allowed retry), or the device
/// can't attest: show help and offer sign-in.
final class RestoreAttestationHelp extends RestoreOutcome {
  const RestoreAttestationHelp();
}

/// The request body failed the strict parser (R3-8) or the contract: nothing
/// was sent.
final class RestoreBodyRejected extends RestoreOutcome {
  const RestoreBodyRejected();
}

/// The store could not list the account's purchases.
final class RestoreStoreUnavailable extends RestoreOutcome {
  const RestoreStoreUnavailable();
}

/// Any other refusal (unknown problem).
final class RestoreFailed extends RestoreOutcome {
  const RestoreFailed();
}
