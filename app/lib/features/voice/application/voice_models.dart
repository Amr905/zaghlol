// T-120: value types of the voice logger. toString is redacted everywhere:
// transcripts and item texts are user financial data and are never printed.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show VoiceIssue;

/// One parsed item the user can edit before saving (FR-VOI-03).
final class VoiceDraft {
  const VoiceDraft({
    required this.key,
    required this.text,
    required this.amount,
    required this.categoryId,
    this.issues = const {},
  });

  /// Stable identity inside one session (list position changes on removal).
  final int key;
  final String text;

  /// Integer minor units; null while the amount is missing (EC-30).
  final Money? amount;
  final String? categoryId;
  final Set<VoiceIssue> issues;

  bool get hasAmount => amount != null && amount!.minor > 0;
  bool get ready => hasAmount;

  VoiceDraft copyWith({
    String? text,
    Money? amount,
    bool clearAmount = false,
    String? categoryId,
    bool clearCategory = false,
  }) => VoiceDraft(
    key: key,
    text: text ?? this.text,
    amount: clearAmount ? null : (amount ?? this.amount),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    issues: amount != null ? const {} : issues,
  );

  @override
  String toString() => 'VoiceDraft(<redacted>)';
}

/// Where the logger is (S-31 states).
enum VoicePhase {
  /// Reading the monthly counter.
  checking,

  /// Free user used all logs this month (A-15), before listening.
  limit,

  /// Mic open.
  listening,

  /// The phone has no on-device Arabic: ask before using the online
  /// recognizer (D-42).
  needConsent,

  /// "Understanding..." (at most 2 s).
  understanding,

  /// Items shown for confirmation.
  parsed,

  /// Nothing with an amount was heard.
  empty,

  /// No recognizer for this language on this phone (EC-32).
  unavailable,

  /// Microphone permission denied.
  micDenied,

  /// Writing the transactions.
  saving,

  /// Saved and closed.
  saved,
}
