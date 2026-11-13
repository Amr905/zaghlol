/// Value types of the voice-phrase parser (T-109, FR-VOI-02/05,
/// domain-algorithms §9). Pure Dart. Nothing here is ever logged: the
/// `toString` of every type is redacted.
library;

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// Why an item needs the user's attention before saving (FR-VOI-03).
enum VoiceIssue {
  /// Text without an amount (EC-30). `amount` is null.
  missingAmount,

  /// An amount without an item text (EC-30).
  missingItemText,

  /// The spoken amount is zero or too large to store. `amount` is null.
  invalidAmount,

  /// The currency word is ambiguous (`دينار`), or the phrase names another
  /// currency elsewhere and this amount names none. The default currency
  /// is used and nothing is converted.
  ambiguousCurrency,
}

/// One item of a spoken phrase, before categorization.
final class VoiceItem {
  const VoiceItem({
    required this.amount,
    required this.text,
    required this.matchText,
    required this.currencySpoken,
    required this.issues,
    required this.confidencePermille,
  });

  /// Integer minor units in [Money.currency]; null when [issues] holds
  /// [VoiceIssue.missingAmount] or [VoiceIssue.invalidAmount].
  final Money? amount;

  /// Display text: the item words without verbs, fillers and currency.
  final String text;

  /// [text] plus the words that carry a glued leading `و`, stripped. Input
  /// for categorization only.
  final String matchText;

  /// Whether the speaker named the currency.
  final bool currencySpoken;

  final Set<VoiceIssue> issues;

  /// Parse confidence in thousandths (digits 1000, spoken number words 950,
  /// a fraction word 900, no amount 0, each issue lowers it).
  final int confidencePermille;

  @override
  String toString() => 'VoiceItem(<redacted>)';
}

/// Why nothing could be parsed.
enum VoiceUnrecognizedReason {
  /// Empty or blank input.
  empty,

  /// Longer than [maxVoiceTextLength]; not parsed.
  tooLong,

  /// Only verbs and fillers: no item and no amount.
  noContent,
}

/// Result of [parseVoicePhrase]. Never thrown: unparseable input is
/// [VoiceUnrecognized].
sealed class VoiceParseResult {
  const VoiceParseResult();
}

final class VoiceParsed extends VoiceParseResult {
  const VoiceParsed(this.items);

  /// At least one item, in spoken order.
  final List<VoiceItem> items;

  @override
  String toString() => 'VoiceParsed(${items.length} items)';
}

final class VoiceUnrecognized extends VoiceParseResult {
  const VoiceUnrecognized(this.reason);

  final VoiceUnrecognizedReason reason;

  @override
  String toString() => 'VoiceUnrecognized(${reason.name})';
}

/// Longest phrase read (untrusted input cap; 30 s of speech is far below).
const int maxVoiceTextLength = 1000;
