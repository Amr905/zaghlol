// T-356: AI merchant suggestions as domain values (LLM-CATEGORISE, D-94;
// pure Dart: no Flutter, no Drift). Nothing here is ever logged.

/// The state of a merchant's AI suggestion. [code] is the stored
/// `ai_merchant_suggestions.state`.
enum AiSuggestionState {
  /// Applied with the AI mark, waiting for the user's Right/Wrong.
  unconfirmed('unconfirmed'),

  /// The user said Right (it is now also a user rule).
  confirmed('confirmed'),

  /// The user said Wrong and picked another category (a user rule).
  corrected('corrected'),

  /// The backend had no usable answer; never re-sent.
  noAnswer('no_answer');

  const AiSuggestionState(this.code);
  final String code;

  /// Null for an unknown code (callers treat it as not confirmed).
  static AiSuggestionState? tryFromCode(String code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Reads the suggestion state of merchants (export, FR-LCAT-25).
abstract interface class AiSuggestionStates {
  /// The state of each of [merchantNorms] that has a suggestion.
  Future<Map<String, AiSuggestionState>> statesOf(
    Iterable<String> merchantNorms,
  );
}
