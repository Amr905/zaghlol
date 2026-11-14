/// Value types of the Ask Zaghlol grammar (T-110, FR-CHAT-01/03/05). Pure
/// Dart. The parser returns slots and ids, never numbers: the numbers come
/// from the query plans in the app. Nothing here is ever logged: the
/// `toString` of every type that can hold the user's question or names is
/// redacted.
library;

/// What the user is asking (FR-CHAT-01 minimum set, plus roast, FR-CHAT-04).
enum AskIntent {
  /// Spend on a category / merchant / card / everything over a period.
  spend,

  /// Two periods side by side.
  comparePeriods,

  /// The merchants with the most spend.
  topMerchants,

  /// What the user holds in an account (or all asset accounts).
  accountBalance,

  /// What is left of the cycle budget.
  budgetRemaining,

  /// Instalments and bills falling due soon.
  upcomingDues,

  /// The single largest expense in a period.
  biggestExpense,

  /// Income minus spend in a period.
  savings,

  /// Humorous critique of spending (FR-CHAT-04).
  roast,
}

enum AskPeriodKind {
  /// One local day; [AskPeriod.offset] 0 is today, -1 yesterday.
  day,

  /// A calendar week (Saturday start is the app's call); offset 0 is this.
  week,

  /// A calendar month; offset 0 is this month, -1 last month.
  month,

  /// A calendar year.
  year,

  /// The payday cycle; offset 0 is the current one.
  cycle,

  /// The last [AskPeriod.count] days, today included.
  lastDays,

  /// The month number [AskPeriod.month] (1..12) of [AskPeriod.year], or the
  /// latest such month that is not in the future when the year is null.
  monthOfYear,

  /// From the first transaction until today.
  allTime,
}

/// A period as spoken. The app resolves it against today and the payday
/// schedule; the parser does no date math.
final class AskPeriod {
  const AskPeriod(
    this.kind, {
    this.offset = 0,
    this.count = 0,
    this.month = 0,
    this.year,
  });

  final AskPeriodKind kind;

  /// 0 current, -1 previous, -2 the one before.
  final int offset;

  /// Days for [AskPeriodKind.lastDays].
  final int count;

  /// 1..12 for [AskPeriodKind.monthOfYear].
  final int month;
  final int? year;

  /// The period before this one, for "compared with last time". Null when
  /// there is no sensible previous one (all time, last N days returns the N
  /// days before).
  AskPeriod? get previous => switch (kind) {
    AskPeriodKind.allTime => null,
    AskPeriodKind.lastDays => null,
    AskPeriodKind.monthOfYear => AskPeriod(
      kind,
      month: month == 1 ? 12 : month - 1,
      year: year == null ? null : (month == 1 ? year! - 1 : year),
    ),
    _ => AskPeriod(kind, offset: offset - 1),
  };

  @override
  bool operator ==(Object other) =>
      other is AskPeriod &&
      other.kind == kind &&
      other.offset == offset &&
      other.count == count &&
      other.month == month &&
      other.year == year;

  @override
  int get hashCode => Object.hash(kind, offset, count, month, year);

  @override
  String toString() => 'AskPeriod($kind, $offset, $count, $month, $year)';
}

/// A thing the user can name: a category, merchant or card. [names] are the
/// spoken forms (display names, aliases, last-4 text). The app builds the
/// list from the database; the parser matches it.
final class AskEntity {
  const AskEntity(this.id, this.names, {this.partial = false});

  final String id;
  final List<String> names;

  /// When true one distinctive word of a name is enough ("CIB" for
  /// "CIB Debit"); the best-scoring entities win and ties are all kept.
  /// When false every word of a name must be present.
  final bool partial;

  @override
  String toString() => 'AskEntity(<redacted>)';
}

final class AskEntities {
  const AskEntities({
    this.categories = const [],
    this.merchants = const [],
    this.accounts = const [],
  });

  static const AskEntities none = AskEntities();

  final List<AskEntity> categories;
  final List<AskEntity> merchants;
  final List<AskEntity> accounts;
}

/// The filled slots of a question.
final class AskSlots {
  const AskSlots({
    this.period,
    this.compareWith,
    this.periodDefaulted = false,
    this.categoryId,
    this.merchantIds = const {},
    this.accountIds = const {},
    this.currencyCode,
    this.limit,
  });

  /// The period asked about; null for intents that need none.
  final AskPeriod? period;

  /// The second period of a comparison.
  final AskPeriod? compareWith;

  /// The user named no period and [period] is the intent's default.
  final bool periodDefaulted;

  final String? categoryId;
  final Set<String> merchantIds;
  final Set<String> accountIds;

  /// ISO 4217 code the user restricted the answer to; null is every
  /// currency with data (one figure each).
  final String? currencyCode;

  /// "Top N", clamped to 1..50.
  final int? limit;

  bool get hasTarget =>
      categoryId != null || merchantIds.isNotEmpty || accountIds.isNotEmpty;

  @override
  String toString() => 'AskSlots(<redacted>)';
}

/// Why a question was not understood. Never carries the text.
enum AskUnrecognizedReason {
  /// Blank, or only punctuation.
  empty,

  /// Longer than [maxAskChars] after trimming.
  tooLong,

  /// No intent scored high enough.
  noIntent,

  /// Two intents scored too close to call.
  ambiguous,

  /// The user named something ("on X") that matches no category, merchant or
  /// card: the answer would be about something else.
  unknownTarget,
}

/// Longest question the grammar looks at.
const int maxAskChars = 300;

/// Most words the grammar looks at; the rest is ignored.
const int maxAskTokens = 60;

sealed class AskParse {
  const AskParse();
}

final class AskUnderstood extends AskParse {
  const AskUnderstood(this.intent, this.slots, this.scorePermille);

  final AskIntent intent;
  final AskSlots slots;

  /// The winning intent's score, 0..1000.
  final int scorePermille;

  @override
  String toString() => 'AskUnderstood(<redacted>)';
}

final class AskUnrecognized extends AskParse {
  const AskUnrecognized(this.reason);
  final AskUnrecognizedReason reason;

  @override
  String toString() => 'AskUnrecognized($reason)';
}

/// Suggested-question chips (FR-CHAT-05). The app maps each to an ARB key
/// for its label and its question text; no user-facing text lives here.
enum AskChip {
  spendThisMonth,
  spendLastMonth,
  topMerchants,
  biggestExpense,
  budgetLeft,
  balance,
  upcomingDues,
  savings,
  compareMonths,
  roast,
}
