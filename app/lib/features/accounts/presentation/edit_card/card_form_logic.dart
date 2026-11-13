// T-085: validation and the save/merge use cases behind S-43 (flows 07 §B).
// Pure Dart plus the repository ports; no widgets. Nothing here is logged:
// names, last-4 digits and amounts are financial data.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../domain/account.dart';
import '../../domain/accounts_repository.dart';

const int cardNameMax = 30;
const int dueDayMin = 1;
const int dueDayMax = 31;

/// The generic institution for "my bank isn't listed" (parser fallback).
const String genericInstitutionCode = 'generic';

enum NameError { empty, tooLong, taken }

enum Last4Error { invalid }

enum LimitError { negative, invalid }

enum DueDayError { outOfRange }

/// The outcome of validating the form; every field null means valid.
final class CardFormErrors {
  const CardFormErrors({this.name, this.last4, this.limit, this.dueDay});

  final NameError? name;
  final Last4Error? last4;
  final LimitError? limit;
  final DueDayError? dueDay;

  bool get isValid =>
      name == null && last4 == null && limit == null && dueDay == null;
}

/// Kinds where the last 4 digits are required (cards); wallets, multi-
/// currency and BNPL accounts may be institution-only.
bool last4Required(AccountKind kind) =>
    kind == AccountKind.credit || kind == AccountKind.debit;

/// Validates S-43 (name 1-30 and unique; last-4 exactly 4 digits; limit >= 0;
/// due day 1-31). [takenNames] are the other live accounts' labels.
CardFormErrors validateCardForm({
  required String name,
  required String last4,
  required String limit,
  required String dueDay,
  required AccountKind kind,
  required Currency currency,
  required Iterable<String> takenNames,
  bool editingLast4 = true,
}) {
  final n = name.trim();
  NameError? nameError;
  if (n.isEmpty) {
    nameError = NameError.empty;
  } else if (n.runes.length > cardNameMax) {
    nameError = NameError.tooLong;
  } else if (takenNames.any((t) => t.trim().toLowerCase() == n.toLowerCase())) {
    nameError = NameError.taken;
  }

  Last4Error? last4Error;
  final l4 = normalizeDigits(last4.trim());
  if (editingLast4) {
    final ok = RegExp(r'^[0-9]{4}$').hasMatch(l4);
    if (l4.isEmpty ? last4Required(kind) : !ok) {
      last4Error = Last4Error.invalid;
    }
  }

  LimitError? limitError;
  DueDayError? dueError;
  if (kind == AccountKind.credit) {
    final lim = normalizeDigits(limit.trim());
    if (lim.isNotEmpty) {
      if (lim.startsWith('-')) {
        limitError = LimitError.negative;
      } else if (Money.tryParse(lim, currency) == null) {
        limitError = LimitError.invalid;
      }
    }
    final dd = normalizeDigits(dueDay.trim());
    if (dd.isNotEmpty) {
      final v = int.tryParse(dd);
      if (v == null || v < dueDayMin || v > dueDayMax) {
        dueError = DueDayError.outOfRange;
      }
    }
  }
  return CardFormErrors(
    name: nameError,
    last4: last4Error,
    limit: limitError,
    dueDay: dueError,
  );
}

/// An existing live account with the same institution and last-4 (also
/// hidden ones): the manual add must offer to open it instead.
Account? findDuplicate(
  Iterable<Account> accounts, {
  required String institutionCode,
  required String last4,
  String? exceptId,
}) {
  final l4 = normalizeDigits(last4.trim());
  if (l4.isEmpty) return null;
  for (final a in accounts) {
    if (a.id != exceptId &&
        !a.isMerged &&
        a.institutionCode == institutionCode &&
        a.last4 == l4) {
      return a;
    }
  }
  return null;
}

/// Why a merge is not allowed or needs a warning.
enum MergeCheck { ok, self, differentInstitution }

MergeCheck checkMerge(Account source, Account target) {
  if (source.id == target.id) return MergeCheck.self;
  if (source.institutionCode != target.institutionCode) {
    return MergeCheck.differentInstitution;
  }
  return MergeCheck.ok;
}

/// What the caller gets after a save.
final class CardSaveResult {
  const CardSaveResult(this.account, {this.duplicateOf});

  final Account account;

  /// Set when the card already existed (a message created it first): the
  /// caller offers to open it. No changes were made.
  final Account? duplicateOf;
}

/// Creates a manual card (flows 07 §B). Never creates a second account for
/// the same institution + last-4: the repository resolves to the existing
/// one and [CardSaveResult.duplicateOf] is set.
Future<CardSaveResult> createCard(
  AccountsRepository repo, {
  required String institutionCode,
  required String name,
  required String last4,
  required AccountKind kind,
  required Currency currency,
  required String limit,
  required String dueDay,
}) async {
  final l4 = normalizeDigits(last4.trim());
  final existing = findDuplicate(
    await repo.list(includeHidden: true),
    institutionCode: institutionCode,
    last4: l4,
  );
  if (existing != null) {
    return CardSaveResult(existing, duplicateOf: existing);
  }
  final resolved = await repo.resolve(
    AccountHint(
      institutionCode: institutionCode,
      currency: currency,
      label: name.trim(),
      last4: l4.isEmpty ? null : l4,
      kind: kind,
    ),
  );
  if (!resolved.created) {
    return CardSaveResult(resolved.account, duplicateOf: resolved.account);
  }
  final edit = _creditEdit(kind, currency, limit, dueDay);
  final account = edit == null
      ? resolved.account
      : await repo.update(resolved.account.id, edit);
  return CardSaveResult(account);
}

/// Applies the edit form to [account]. Only fields the repository can change
/// are sent.
Future<Account> saveCardEdit(
  AccountsRepository repo,
  Account account, {
  required String name,
  required AccountKind kind,
  required String limit,
  required String dueDay,
}) {
  final credit = _creditEdit(kind, account.defaultCurrency, limit, dueDay);
  return repo.update(
    account.id,
    AccountEdit(
      label: name.trim(),
      kind: kind == account.kind ? null : kind,
      creditLimit: credit?.creditLimit,
      statementDueDay: credit?.statementDueDay,
    ),
  );
}

AccountEdit? _creditEdit(
  AccountKind kind,
  Currency currency,
  String limit,
  String dueDay,
) {
  if (kind != AccountKind.credit) return null;
  final lim = normalizeDigits(limit.trim());
  final dd = int.tryParse(normalizeDigits(dueDay.trim()));
  final money = lim.isEmpty ? null : Money.tryParse(lim, currency);
  if (money == null && dd == null) return null;
  return AccountEdit(creditLimit: money, statementDueDay: dd);
}
