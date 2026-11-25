import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../registry/registry_models.dart';

/// Confirmed parses a sender needs before "always capture" takes effect
/// (A-66).
const int kGenericConfirmationsRequired = 3;

/// What the ingest layer does with a generic suggestion.
enum GenericDisposition {
  /// Goes to the review queue (`new_sender`); nothing is saved.
  review,

  /// Saved without asking, still flagged `low_confidence` until a template
  /// exists for the sender.
  autoSaveLowConfidence,
}

/// A-66: a generic suggestion is never saved before the user has confirmed
/// [kGenericConfirmationsRequired] parses from the sender **and** turned on
/// "always capture". Anything else, including a negative count, is review.
GenericDisposition genericDisposition({
  required int confirmedCount,
  required bool alwaysCapture,
}) {
  if (alwaysCapture && confirmedCount >= kGenericConfirmationsRequired) {
    return GenericDisposition.autoSaveLowConfidence;
  }
  return GenericDisposition.review;
}

/// Whether a message from an unknown [source] may reach the generic parser
/// (platform-channels: the Guard's generic rule). True when the source is in
/// `generic.alwaysCapture`, when the channel carries no reliable sender
/// (shortcut message, Apple Pay, share), or when `senderHints` match the
/// source and `bodyHints` match the body. [foldedBody] is the `foldKey` text.
bool isGenericCandidate({
  required SharedConfig shared,
  required String source,
  required RegistryChannel channel,
  required String foldedBody,
}) {
  if (channel == RegistryChannel.shortcutMessage ||
      channel == RegistryChannel.applePay ||
      channel == RegistryChannel.share) {
    return true;
  }
  final key = foldKey(source);
  if (key.isEmpty) {
    return false;
  }
  for (final entry in shared.alwaysCapture) {
    if (foldKey(entry) == key) {
      return true;
    }
  }
  return shared.senderHints.any((p) => p.regex.hasMatch(key)) &&
      shared.bodyHints.any((p) => p.regex.hasMatch(foldedBody));
}

/// SMS-AUTO (PO decision): whether a generic result from a bank is saved
/// without review. All of: the sender resolved to a registry institution; a
/// direction or settlement event was read and no direction reason is
/// present; the amount has a currency next to it and no competing reading
/// (amount or currency, D-28); a card last-4 or a merchant was read.
/// Anything else goes to review. Never a function of the 700 confidence
/// ceiling, which stays below the template auto-accept threshold.
///
/// T-241: only a [ParseGeneric] can be eligible. A [ParseNotice] (due
/// reminder or statement), a parsed template result or anything else is not.
bool genericAutoSaveEligible(ParseResult result) {
  if (result is! ParseGeneric) return false;
  final g = result;
  if (g.institutionCode == null || g.direction == null) return false;
  if (!g.amount.isPositive) return false;
  // Money in needs a named event (refund, deposit, settlement ...): promos
  // such as cashback offers read as income but name none, so they go to review.
  if (g.direction == TemplateDirection.income && g.event == null) return false;
  for (final r in const [
    GenericReason.amountAmbiguous,
    GenericReason.currencyAmbiguous,
    GenericReason.directionConflict,
    GenericReason.directionUnknown,
  ]) {
    if (g.reasons.contains(r)) return false;
  }
  if ((g.fieldConfidence[GenericField.amount] ?? 0) < 700 ||
      (g.fieldConfidence[GenericField.currency] ?? 0) < 850) {
    return false;
  }
  return g.last4 != null || g.merchant != null;
}
