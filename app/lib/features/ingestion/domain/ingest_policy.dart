// T-046: the open PO questions of the design note, each at one decision
// point. Every value here is PROVISIONAL — PO to confirm (Q1–Q3). Changing a
// decision means changing that one constant and the tests that pin it.

/// PO Q1 (provisional — PO to confirm): a bank app notification without a
/// card number merges with an SMS of the same bank, amount and direction
/// within the window when that SMS names a card, provided exactly one such
/// candidate exists. False: last-4 must be equal on both sides. Read by
/// `last4Compatible`.
const bool kMergeWhenLast4MissingOnOneSide = true;

/// Marker only, not read by code. PO Q2 (provisional — PO to confirm):
/// BR-ING-02 rule 1 is kept as written: an identical message from the same
/// sender is stored once, whenever it arrives (the receive time is not in
/// `body_hash`). Two real equal payments whose SMS carry no time or
/// reference become one; the user adds the second by hand. The decision
/// point is `bodyHashV1` (body_hash.dart), which a change would need a
/// re-hash migration for.
const bool kIdenticalMessageStoredOnce = true;

/// Which account an auto-saved generic message (A-66, "always capture"
/// after 3 confirmations) is stored on.
enum GenericAutoSaveAccount {
  /// A new account named after the sender (one per sender).
  senderAccount,

  /// Never auto-save: every message goes to review like before A-66.
  askEachTime,
}

/// PO Q3 (provisional — PO to confirm): a new account named after the
/// sender. (The third option of the question, the default cash account, is
/// not built; it would be one more enum value here.)
const GenericAutoSaveAccount kGenericAutoSaveAccount =
    GenericAutoSaveAccount.senderAccount;
