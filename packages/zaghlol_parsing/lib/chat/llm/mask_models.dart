/// Value types of the client scrub and the reference masker (T-328,
/// FR-LLM-03, FR-LLM-18..20, D-92). Pure Dart. Every type that can hold the
/// user's own names, digits or question has a redacted `toString`.
library;

// ---------------------------------------------------------------- scrub

/// What the client scrub replaced; the UI renders these as "hidden" chips.
enum ScrubKind { phone, email, ipa, number }

/// One scrub token left in the text, e.g. `⟦PHONE⟧`.
final class ScrubToken {
  const ScrubToken(this.kind, this.token);

  final ScrubKind kind;
  final String token;

  @override
  String toString() => 'ScrubToken(${kind.name})';
}

final class ScrubResult {
  const ScrubResult(this.text, this.tokens);

  /// The text with phones, e-mails, InstaPay addresses and long digit runs
  /// replaced by tokens.
  final String text;

  /// The tokens in order of appearance.
  final List<ScrubToken> tokens;

  @override
  String toString() => 'ScrubResult(<redacted>, tokens: ${tokens.length})';
}

// -------------------------------------------------------------- sources

/// One name that can refer to an institution (bank, wallet, BNPL).
final class MaskAlias {
  const MaskAlias(this.text, {this.ordinaryWord = false});

  final String text;

  /// An everyday word («مصر», «الأهلي», "Liv"): masked only when a bank,
  /// account or card word is next to it (FR-LLM-18).
  final bool ordinaryWord;

  @override
  String toString() => 'MaskAlias(<redacted>)';
}

/// A registry institution with its Arabic and English aliases.
final class MaskInstitution {
  const MaskInstitution(this.id, this.aliases);

  final String id;
  final List<MaskAlias> aliases;

  @override
  String toString() => 'MaskInstitution(<redacted>)';
}

enum MaskAccountType {
  creditCard,
  debitCard,
  prepaidCard,
  current,
  savings,
  wallet,
  cash,
  other;

  bool get isCard =>
      this == creditCard || this == debitCard || this == prepaidCard;
}

/// One of the user's accounts or cards.
final class MaskAccount {
  const MaskAccount({
    required this.id,
    required this.label,
    this.nickname,
    this.extraNames = const [],
    this.institutionId,
    this.type = MaskAccountType.other,
    this.last4,
  });

  final String id;
  final String label;

  /// The name the user gave it («حساب التوفير»).
  final String? nickname;

  /// Other names for it (an English alias of the nickname, "Savings").
  final List<String> extraNames;
  final String? institutionId;
  final MaskAccountType type;

  /// Four digits, ASCII.
  final String? last4;

  @override
  String toString() => 'MaskAccount(<redacted>)';
}

/// A merchant of the user's own transactions with all its known names.
final class MaskMerchant {
  const MaskMerchant(this.id, this.names);

  final String id;
  final List<String> names;

  @override
  String toString() => 'MaskMerchant(<redacted>)';
}

/// What the masker may replace. The Drift adapter is T-343.
abstract interface class MaskSources {
  List<MaskAccount> get accounts;
  List<MaskInstitution> get institutions;
  List<MaskMerchant> get merchants;
}

/// Plain in-memory [MaskSources].
final class StaticMaskSources implements MaskSources {
  const StaticMaskSources({
    this.accounts = const [],
    this.institutions = const [],
    this.merchants = const [],
  });

  @override
  final List<MaskAccount> accounts;
  @override
  final List<MaskInstitution> institutions;
  @override
  final List<MaskMerchant> merchants;
}

// --------------------------------------------------------------- result

enum MaskKind { account, card, bank, merchant }

/// What a placeholder stands for. Held in memory for one question only
/// (FR-LLM-19).
final class MaskTarget {
  const MaskTarget({
    required this.kind,
    this.accountIds = const [],
    this.institutionId,
    this.merchantId,
  });

  final MaskKind kind;

  /// `card` and `account`: that account; `bank`: the user's accounts there.
  final List<String> accountIds;
  final String? institutionId;
  final String? merchantId;

  @override
  String toString() => 'MaskTarget(${kind.name})';
}

/// placeholder -> target. Never sent, stored or logged.
final class MaskMap {
  const MaskMap(this._entries);

  final Map<String, MaskTarget> _entries;

  MaskTarget? operator [](String placeholder) => _entries[placeholder];
  Iterable<String> get placeholders => _entries.keys;
  int get length => _entries.length;

  @override
  String toString() => 'MaskMap(size: ${_entries.length})';
}

/// A placeholder in the sent text.
final class MaskedToken {
  const MaskedToken(this.kind, this.placeholder);

  final MaskKind kind;
  final String placeholder;

  @override
  String toString() => 'MaskedToken(${kind.name})';
}

sealed class MaskOutcome {
  const MaskOutcome();
}

final class MaskResult extends MaskOutcome {
  const MaskResult({
    required this.sentText,
    required this.map,
    required this.tokens,
  });

  final String sentText;
  final MaskMap map;

  /// Placeholders in order of first appearance.
  final List<MaskedToken> tokens;

  @override
  String toString() => 'MaskResult(<redacted>, tokens: ${tokens.length})';
}

enum MaskUnresolvedReason {
  /// A last-4 no card of the user has.
  noSuchCard,

  /// Two cards with the same last-4.
  ambiguousCard,

  /// A registry bank where the user has no account.
  bankWithoutAccount,

  /// «بنك X» / "bank X" with X not in the registry.
  unknownBank,

  /// One name for two accounts or two institutions.
  ambiguousName,

  /// Unexpected error: nothing is sent.
  failed,
}

/// A reference could not be resolved locally: answer with a clarification
/// and chips of [candidates]; send nothing, use no quota (FR-LLM-20).
final class MaskUnresolved extends MaskOutcome {
  const MaskUnresolved(this.reason, this.candidates);

  final MaskUnresolvedReason reason;

  /// The user's matching cards/accounts (the whole list when none match).
  final List<MaskAccount> candidates;

  @override
  String toString() =>
      'MaskUnresolved(${reason.name}, candidates: ${candidates.length})';
}
