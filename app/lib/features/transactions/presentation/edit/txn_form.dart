// T-080: the S-13 form model and its validation (pure Dart, unit-tested).
// Money is parsed exactly from text (any digit script) into integer minor
// units; nothing here uses a double.

import 'package:flutter/services.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/digits_mode.dart';
import '../../../../core/l10n/money_format.dart';

enum TxnEditType { expense, income, transfer }

enum TxnField { amount, category, account, to, date, note }

enum TxnFormError {
  amountRequired,
  amountTooLarge,
  amountDecimals,
  categoryRequired,
  accountRequired,
  toAccountRequired,
  sameAccount,
  dateFuture,
  noteTooLong,
}

/// Keeps only digits (any script), `.`, `,` and the Arabic separators, for
/// the amount field.
final List<TextInputFormatter> amountInputFormatters = [
  FilteringTextInputFormatter.allow(
    RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9.,\u066B\u066C]'),
  ),
];

/// Largest amount accepted from the keyboard, in minor units.
const int maxEntryMinor = 100000000000000;

/// Longest note, in characters.
const int formNoteMaxChars = 1000;

/// Parses [text] for [currency]; null when it is not a positive amount.
/// [decimalsExceeded] is set when only the decimals are wrong.
({Money? money, TxnFormError? error}) parseAmount(
  String text,
  Currency currency,
) {
  // A comma is accepted only as thousands grouping (`1,250.50`). Anything
  // else (`12,5`) is rejected, never read as 125.
  final raw = normalizeDigits(text).trim();
  final grouped = RegExp(r'^[0-9]{1,3}(,[0-9]{3})+(\.[0-9]*)?$').hasMatch(raw);
  final clean = grouped ? raw.replaceAll(',', '') : raw;
  if (clean.isEmpty) return (money: null, error: TxnFormError.amountRequired);
  final m = MoneyFormat.parseInput(clean, currency);
  if (m == null) {
    final looksNumeric = RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(clean);
    return (
      money: null,
      error: looksNumeric
          ? (clean.contains('.') && clean.length < 64
                ? TxnFormError.amountDecimals
                : TxnFormError.amountTooLarge)
          : TxnFormError.amountRequired,
    );
  }
  if (!m.isPositive) {
    return (money: null, error: TxnFormError.amountRequired);
  }
  if (m.minor > maxEntryMinor) {
    return (money: null, error: TxnFormError.amountTooLarge);
  }
  return (money: m, error: null);
}

/// All field errors of the form (empty = valid). [date] and [today] are
/// civil dates.
Map<TxnField, TxnFormError> validateForm({
  required TxnEditType type,
  required String amountText,
  required Currency currency,
  required String? categoryId,
  required String? accountId,
  required String? toAccountId,
  required CivilDate date,
  required CivilDate today,
  required String note,
}) {
  final errors = <TxnField, TxnFormError>{};
  final a = parseAmount(amountText, currency);
  if (a.error != null) errors[TxnField.amount] = a.error!;
  if (type != TxnEditType.transfer && categoryId == null) {
    errors[TxnField.category] = TxnFormError.categoryRequired;
  }
  if (accountId == null) {
    errors[TxnField.account] = TxnFormError.accountRequired;
  }
  if (type == TxnEditType.transfer) {
    if (toAccountId == null) {
      errors[TxnField.to] = TxnFormError.toAccountRequired;
    } else if (toAccountId == accountId) {
      errors[TxnField.to] = TxnFormError.sameAccount;
    }
  }
  if (date.epochDay > today.epochDay) {
    errors[TxnField.date] = TxnFormError.dateFuture;
  }
  if (note.runes.length > formNoteMaxChars) {
    errors[TxnField.note] = TxnFormError.noteTooLong;
  }
  return errors;
}
