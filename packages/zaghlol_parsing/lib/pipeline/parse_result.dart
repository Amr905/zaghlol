import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../registry/registry_models.dart';

/// Confidence at or above this value is saved without review (A-12, in
/// thousandths: 850 is 0.85). Below it the transaction is still saved, with a
/// `low_confidence` review item (parsing-engine §4.5).
const int kAutoAcceptThresholdPermille = 850;

/// Longest body the pipeline reads. A longer body is not matched at all
/// (untrusted input cap); a concatenated SMS is well under it.
const int maxParseBodyLength = 4000;

/// One message to parse.
final class ParseRequest {
  const ParseRequest({
    required this.body,
    required this.source,
    required this.channel,
    required this.receivedAt,
  });

  final String body;

  /// SMS sender id, or the app package for a notification.
  final String source;
  final RegistryChannel channel;

  /// Device wall clock at receipt as a UTC-flagged `DateTime` (EC-10: the
  /// zone is the device's, so the value carries y/m/d h:m:s only).
  final DateTime receivedAt;
}

/// Why a parsed message lost confidence. Codes only; each has a fixed factor.
enum ParseReason {
  /// The date is more than 3 days ahead of, or 2 years before, receipt.
  dateOutOfRange(700),
  dateInvalid(700),
  timeInvalid(700),
  originalAmountInvalid(700),
  balanceInvalid(800),
  availableInvalid(800),
  last4Invalid(800),

  /// A merchant group matched but nothing was left after cleaning.
  merchantEmpty(800),

  /// Neither an account (last4) nor any party (merchant, counterparty, IPA,
  /// phone, reference) was found.
  sparseFields(900),

  /// Amounts in two currencies and no keyword says which is the charge (a
  /// bracketed foreign amount); the pick is a guess and never converted.
  currencyAmbiguous(700),

  /// Informational (FU-078): the balance or available amount is negative
  /// (an overdrawn account). Stored as a negative amount; no penalty.
  balanceNegative(1000);

  const ParseReason(this.factorPermille);

  /// Multiplier in thousandths applied to the confidence.
  final int factorPermille;
}

/// How `occurredAt` was resolved (parsing-engine §4.4).
enum OccurredAtSource {
  /// Date and time both came from the message.
  messageDateTime,

  /// Date from the message, time of day from `receivedAt`.
  messageDate,

  /// Time from the message, calendar date from `receivedAt`.
  messageTime,

  /// Nothing usable in the message: `receivedAt`.
  receivedAt,
}

/// Wall-clock time of day read from a message.
final class WallTime {
  const WallTime(this.hour, this.minute, [this.second = 0]);

  final int hour;
  final int minute;
  final int second;

  @override
  bool operator ==(Object other) =>
      other is WallTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);

  @override
  String toString() => 'WallTime($hour:$minute:$second)';
}

/// What kind of party the other side of a transfer is. IPA and phone
/// counterparties are people: they skip the catalog (BR-CAT-03).
enum CounterpartyKind { ipaAddress, phone, name }

final class Counterparty {
  const Counterparty({
    required this.kind,
    this.name,
    this.ipa,
    this.phone,
    this.ownAccount = false,
  });

  /// The template declared this counterparty is the user's own account.
  final bool ownAccount;

  /// `ipaAddress` when an IPA was found, else `phone`, else `name`.
  final CounterpartyKind kind;
  final String? name;
  final String? ipa;
  final String? phone;
}

/// Typed fields of one parsed message. A field the message does not carry is
/// null (never guessed); only [occurredAt] is always set, by policy.
final class ParsedFields {
  const ParsedFields({
    required this.amount,
    required this.originalAmount,
    required this.balance,
    required this.available,
    required this.balanceIsAvailableLimit,
    required this.last4,
    required this.merchant,
    required this.counterparty,
    required this.ref,
    required this.date,
    required this.time,
    required this.occurredAt,
    required this.occurredAtSource,
  });

  /// Amount in the account currency (the billed amount for a foreign-currency
  /// purchase). Null only for balance-only notices.
  final Money? amount;

  /// Amount in the original currency of a foreign purchase.
  final Money? originalAmount;
  final Money? balance;
  final Money? available;

  /// Template flag: [balance] is a card's available limit, not an account
  /// balance.
  final bool balanceIsAvailableLimit;
  final String? last4;
  final CleanedMerchant? merchant;
  final Counterparty? counterparty;
  final String? ref;

  /// Calendar date as written in the message (UTC midnight carries y/m/d).
  final DateTime? date;
  final WallTime? time;

  /// When the event happened, as a UTC-flagged device wall clock.
  final DateTime occurredAt;
  final OccurredAtSource occurredAtSource;
}

/// Result of [ParsingPipeline.parse]. Sealed: handle every case.
sealed class ParseResult {
  const ParseResult();
}

/// A template matched and the required fields were read.
final class ParseParsed extends ParseResult {
  const ParseParsed({
    required this.institutionCode,
    required this.templateId,
    required this.templateVersion,
    required this.language,
    required this.event,
    required this.direction,
    required this.fields,
    required this.confidencePermille,
    required this.reasons,
  });

  final String institutionCode;
  final String templateId;
  final int templateVersion;

  /// Detected language of the message, `ar` or `en`.
  final String language;
  final TemplateEvent event;
  final TemplateDirection direction;
  final ParsedFields fields;

  /// 0..1000; `base x product(penalties)` in integer arithmetic.
  final int confidencePermille;
  final List<ParseReason> reasons;

  /// Saved, but with a `low_confidence` review item.
  bool get needsReview => confidencePermille < kAutoAcceptThresholdPermille;
}

/// Which card notice a [ParseNotice] is.
enum NoticeKind {
  /// A reminder that the card payment is due or will be debited.
  ccDue,

  /// A statement (total due, minimum due, due date).
  ccStatement,
}

/// T-241 (D-83): a card due reminder or statement. **Never a transaction**:
/// it is not [ParseParsed] or [ParseGeneric], so no code path that saves a
/// parse can save it. The ingest layer stores the raw message and hands the
/// typed fields to the dues hook. Every field a message does not carry is
/// null. Carries typed fields only, never message text.
final class ParseNotice extends ParseResult {
  const ParseNotice({
    required this.kind,
    required this.language,
    required this.confidencePermille,
    this.institutionCode,
    this.templateId,
    this.templateVersion,
    this.last4,
    this.amountDue,
    this.minDue,
    this.dueDate,
    this.statementDate,
  });

  final NoticeKind kind;
  final String language;

  /// Null for an unknown sender (generic gate).
  final String? institutionCode;

  /// Set when a registry template read it; null for the generic gate.
  final String? templateId;
  final int? templateVersion;
  final String? last4;

  /// Total amount due (the amount that will be debited for a reminder).
  final Money? amountDue;
  final Money? minDue;

  /// Calendar dates (UTC midnight carries y/m/d). An undated due date is the
  /// nearest future one.
  final DateTime? dueDate;
  final DateTime? statementDate;
  final int confidencePermille;

  /// True when a template read it (fields are reliable) rather than the
  /// generic gate (best effort).
  bool get fromTemplate => templateId != null;
}

enum DropReason { globalPattern, institutionPattern }

/// A drop pattern fired (OTP, promotion): nothing is stored.
final class ParseDropped extends ParseResult {
  const ParseDropped(this.reason, [this.institutionCode]);

  final DropReason reason;
  final String? institutionCode;
}

enum UnrecognizedReason {
  emptyBody,
  bodyTooLong,

  /// No institution for the sender or package, and the message does not
  /// qualify for the generic parser (not from an always-capture source, no
  /// sender-and-body hint match, not a shortcut, Apple Pay or share input).
  unknownSource,

  /// The institution is known but no template matched.
  noTemplateMatched,

  /// A template matched but the amount could not be read (not a positive
  /// number, or more decimals than the currency allows).
  invalidAmount,

  /// A template matched but the currency marker is unknown.
  invalidCurrency,

  /// Unexpected internal failure; the message goes to review.
  internalError,

  /// Generic parser: the message qualified but no amount with an adjacent
  /// currency could be read.
  genericNoAmount,

  /// Generic parser: the message says the attempt failed or was declined,
  /// which is not a transaction.
  genericDeclined,

  /// Generic parser: promotion wording (offer, win, `عرض خاص`) and no word
  /// saying money moved. Not a transaction; still a review item.
  genericPromotion,

  /// Generic parser (T-241): the message reads like a due reminder or
  /// statement and also like a completed purchase. Neither is trusted: it
  /// goes to review, never to a transaction.
  genericNoticeConflict,
}

/// Nothing could be parsed. The caller keeps the raw message as an
/// `unrecognized` review item. Carries codes only, never message text.
final class ParseUnrecognized extends ParseResult {
  const ParseUnrecognized(this.reason, {this.institutionCode, this.templateId});

  final UnrecognizedReason reason;
  final String? institutionCode;
  final String? templateId;
}

/// Why a generic suggestion lost confidence. Codes only.
enum GenericReason {
  /// Two or more different amounts and no keyword singled one out.
  amountAmbiguous(700),

  /// Expense and income keywords sit within 20 characters of each other, so
  /// the direction is left unset.
  directionConflict(800),

  /// No direction keyword: the direction is left unset, never defaulted.
  directionUnknown(800),

  /// Neither a last-4 nor a merchant was found.
  sparseFields(900),

  /// Amounts in two currencies and no keyword says which is the charge (a
  /// bracketed foreign amount); the pick is a guess and never converted.
  currencyAmbiguous(700);

  const GenericReason(this.factorPermille);

  /// Multiplier in thousandths applied to the confidence.
  final int factorPermille;
}

/// Highest confidence a generic suggestion can have, in thousandths. It is
/// below [kAutoAcceptThresholdPermille] by construction.
const int kGenericMaxConfidencePermille = 700;

/// The kind of transaction a generic message names, when a keyword says so.
/// A hint for the review card and the stored direction; never a direction
/// by itself.
///
/// [ccPayment] (SMS-AUTO) is a credit-card settlement: a payment towards the
/// card. It is a transfer between the user's own accounts, never an expense
/// or income; the ingest layer stores it as a transfer into the card account
/// (income side) or out of the paying account (expense side).
enum GenericEvent { purchase, withdrawal, transfer, refund, ccPayment }

/// A field the generic parser reads.
enum GenericField {
  amount,
  currency,
  direction,
  last4,
  merchant,
  date,
  reference,
  counterparty,
  balance,
}

/// A span of the original message text, in code units: where a generic field
/// was read. Offsets only, never text (the custom-template builder tags the
/// same spans so a confirmed suggestion can become a template).
final class GenericSpan {
  const GenericSpan(this.start, this.end);

  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is GenericSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'GenericSpan($start, $end)';
}

/// A best-effort suggestion for a message from a source with no template
/// (FR-PAR-13). It always needs review: the amount is a suggestion the user
/// confirms or edits. A field the message does not carry is null (never
/// guessed), including [direction].
final class ParseGeneric extends ParseResult {
  const ParseGeneric({
    required this.language,
    required this.amount,
    required this.direction,
    required this.last4,
    required this.merchant,
    required this.occurredAt,
    required this.confidencePermille,
    required this.reasons,
    this.institutionCode,
    this.originalAmount,
    this.event,
    this.reference,
    this.counterparty,
    this.balance,
    this.available,
    this.dateRead = false,
    this.fieldConfidence = const {},
    this.spans = const {},
  });

  /// The institution the sender resolved to when a registry template did not
  /// match (the generic parser then read the message); null for an unknown
  /// sender.
  final String? institutionCode;

  /// Detected language of the message, `ar` or `en`.
  final String language;

  /// Positive amount in the currency the message names next to it.
  final Money amount;

  /// Foreign amount shown beside the charge (`EGP 3,400.00 (EUR 100.00)`);
  /// [amount] stays the charged account-currency amount.
  final Money? originalAmount;

  /// `expense` or `income`; null when the message gives no clear keyword.
  final TemplateDirection? direction;
  final String? last4;
  final CleanedMerchant? merchant;

  /// The message's own date (at the receipt's time of day) when [dateRead],
  /// otherwise the receipt time.
  final DateTime occurredAt;

  /// True when [occurredAt] carries a date read from the message.
  final bool dateRead;

  /// Purchase, withdrawal, transfer or refund, when a keyword names it.
  final GenericEvent? event;

  /// A reference or transaction id after a `Ref`/`المرجع` cue, as written.
  final String? reference;

  /// T-243: the other party of a transfer (name as written, masks kept),
  /// stored like a templated InstaPay counterparty; never a merchant.
  final Counterparty? counterparty;

  /// Account balance after the transaction (`الرصيد المتوفر`, `avail bal`);
  /// never the amount. Null when not read.
  final Money? balance;

  /// Available limit (`available limit is`); null when not read.
  final Money? available;

  /// 0..[kGenericMaxConfidencePermille].
  final int confidencePermille;
  final List<GenericReason> reasons;

  /// How sure the parser is of each field it read, in thousandths. A field
  /// it did not read is absent (never 0-with-a-value).
  final Map<GenericField, int> fieldConfidence;

  /// Where each field was read in the original text (offsets only).
  final Map<GenericField, GenericSpan> spans;

  /// Always true: a generic result is never accepted without the user.
  bool get needsReview => true;

  /// Every field the review card needs is filled and unambiguous: amount and
  /// currency with no competing reading, a direction, and a last-4 or a
  /// merchant. The card can then offer a one-tap confirm; the result still
  /// goes to review (FR-PAR-13, A-66), it is never saved by this flag.
  bool get prefillComplete =>
      direction != null &&
      (last4 != null || merchant != null || counterparty != null) &&
      !reasons.contains(GenericReason.amountAmbiguous) &&
      !reasons.contains(GenericReason.currencyAmbiguous) &&
      !reasons.contains(GenericReason.directionConflict);

  @override
  String toString() =>
      'ParseGeneric(${amount.currency.code}, ${direction?.name}, '
      'confidence: $confidencePermille)';
}
