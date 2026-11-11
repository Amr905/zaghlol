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
  sparseFields(900);

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
  const Counterparty({required this.kind, this.name, this.ipa, this.phone});

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

  /// No institution for the sender or package (the generic parser, T-073,
  /// picks these up).
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
}

/// Nothing could be parsed. The caller keeps the raw message as an
/// `unrecognized` review item. Carries codes only, never message text.
final class ParseUnrecognized extends ParseResult {
  const ParseUnrecognized(this.reason, {this.institutionCode, this.templateId});

  final UnrecognizedReason reason;
  final String? institutionCode;
  final String? templateId;
}
