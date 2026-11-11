import '../normalize/text_normalizer.dart';
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
