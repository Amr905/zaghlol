// T-147: what a sign-in attempt can end as. Nothing here carries a token,
// an account ID, an e-mail or a key (EC-65).

/// What to offer when the server says Gold may be restorable here (R5-3(b)).
enum RestoreHint {
  /// Nothing to offer.
  none,

  /// `restoreSuggested` and this device's Apple ID has a StoreKit transaction:
  /// show the Restore action.
  offerRestore,

  /// `restoreSuggested` without a StoreKit transaction (Play purchase, other
  /// Apple ID): no Restore button; show `nextMoveAt` and the support path.
  supportPath,
}

sealed class SignInOutcome {
  const SignInOutcome();
}

/// The account token is stored and bound to this install.
final class SignedIn extends SignInOutcome {
  const SignedIn({
    this.movedFromOtherPhone = false,
    this.moveRefused = false,
    this.nextMoveAt,
    this.restoreHint = RestoreHint.none,
  });

  /// Gold moved to this phone with the sign-in.
  final bool movedFromOtherPhone;

  /// R3-5: linked, but the cooldown kept Gold off this phone for now.
  final bool moveRefused;
  final DateTime? nextMoveAt;
  final RestoreHint restoreHint;

  /// Linked, and Gold is not here (yet): the "linked but not on this phone"
  /// message applies.
  bool get linkedWithoutGold => moveRefused || restoreHint != RestoreHint.none;
}

/// The user closed the provider's sheet.
final class SignInCancelled extends SignInOutcome {
  const SignInCancelled();
}

/// EC-46: this install is linked to another account. Ask, then call
/// `signIn(replaceLink: true)` (a fresh token and nonce are drawn then).
final class SignInNeedsReplaceConfirm extends SignInOutcome {
  const SignInNeedsReplaceConfirm();
}

/// Offline, timeout, 429 or 5xx: nothing was stored; try again later.
final class SignInTryLater extends SignInOutcome {
  const SignInTryLater({this.retryAfter});
  final Duration? retryAfter;
}

/// Anything else (provider not configured, invalid token, answer that did
/// not pass the install-binding check).
final class SignInFailed extends SignInOutcome {
  const SignInFailed();
}

sealed class SignOutOutcome {
  const SignOutOutcome();
}

/// Tokens dropped. [serverConfirmed] is false when the call failed (offline):
/// the local state is signed out all the same (D-61(c)).
final class SignedOut extends SignOutOutcome {
  const SignedOut({required this.serverConfirmed});
  final bool serverConfirmed;
}

sealed class DeleteAccountOutcome {
  const DeleteAccountOutcome();
}

final class AccountDeleted extends DeleteAccountOutcome {
  const AccountDeleted();
}

/// Nothing was deleted; try again (offline, 5xx).
final class DeleteAccountTryLater extends DeleteAccountOutcome {
  const DeleteAccountTryLater();
}

/// The account token is gone or refused (`401 ACCOUNT_TOKEN_EXPIRED`, or no
/// token): sign in again, then delete.
final class DeleteAccountNeedsSignIn extends DeleteAccountOutcome {
  const DeleteAccountNeedsSignIn();
}

final class DeleteAccountFailed extends DeleteAccountOutcome {
  const DeleteAccountFailed();
}
