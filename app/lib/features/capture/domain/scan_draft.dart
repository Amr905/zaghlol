// T-161 (S-32): what the parser read from an image or shared text, reduced to
// the fields the confirmation screen shows. Pure; no text of the image or
// message is kept beyond these typed fields. Nothing here is saved.

import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../transactions/domain/transaction.dart';

/// Where the text came from.
enum ScanOrigin { image, text }

final class ScanDraft {
  const ScanDraft({
    required this.amount,
    required this.direction,
    required this.origin,
    this.party,
    this.date,
    this.last4,
    this.reference,
    this.templateId,
  });

  /// Positive, in its own currency (never converted).
  final Money amount;
  final TxnDirection direction;
  final ScanOrigin origin;

  /// Merchant, IPA, phone or person: the "To / From" field.
  final String? party;

  /// The date written in the image, when there was one.
  final CivilDate? date;
  final String? last4;
  final String? reference;
  final String? templateId;

  @override
  String toString() => 'ScanDraft(<redacted>)';
}

/// The draft for [result], or null when the text holds no payment (anything
/// but a parsed expense or income).
ScanDraft? scanDraftFromParse(ParseResult result, ScanOrigin origin) {
  if (result is! ParseParsed) return null;
  final amount = result.fields.amount;
  if (amount == null || !amount.isPositive) return null;
  final direction = switch (result.direction) {
    TemplateDirection.expense => TxnDirection.expense,
    TemplateDirection.income => TxnDirection.income,
    TemplateDirection.neutral => null,
  };
  if (direction == null) return null;
  final cp = result.fields.counterparty;
  final party =
      result.fields.merchant?.display ?? cp?.name ?? cp?.ipa ?? cp?.phone;
  final d = result.fields.date;
  return ScanDraft(
    amount: amount,
    direction: direction,
    origin: origin,
    party: party == null || party.isEmpty ? null : party,
    date: d == null ? null : CivilDate(d.year, d.month, d.day),
    last4: result.fields.last4,
    reference: result.fields.ref,
    templateId: result.templateId,
  );
}
