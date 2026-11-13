// T-093: what the S-15 / S-16 sheets read and write. Widgets only see this
// port (Riverpod provider in `transfers_providers.dart`); the Drift-backed
// implementation lives in `data/`. Money is `Money` (integer minor units),
// never converted between currencies.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// One repayment already attributed to a person (a `reimbursement` link).
final class SplitRepayment {
  const SplitRepayment({
    required this.linkId,
    required this.sourceId,
    required this.amount,
    required this.sourceLabel,
    required this.date,
  });

  final String linkId;

  /// The incoming transfer this repayment came from (for Undo).
  final String sourceId;
  final Money amount;

  /// The incoming transfer's channel, already a display string (for example
  /// the account name).
  final String sourceLabel;

  /// Local civil time of the repayment (shifted by its own offset).
  final DateTime date;
}

final class SplitPerson {
  const SplitPerson({
    required this.id,
    required this.name,
    required this.share,
    this.repayments = const [],
  });

  final String id;
  final String name;
  final Money share;
  final List<SplitRepayment> repayments;

  int get repaidMinor => repayments.fold(0, (s, r) => s + r.amount.minor);

  /// FR-XFR-05: paid back once the repayments cover the share.
  bool get paidBack => share.minor > 0 && repaidMinor >= share.minor;
}

/// An unassigned incoming transfer that may belong to this bill
/// (FR-XFR-08). Never linked automatically.
final class SplitSuggestion {
  const SplitSuggestion({
    required this.sourceId,
    required this.person,
    required this.amount,
    required this.date,
    this.participantId,
  });

  final String sourceId;
  final String person;
  final Money amount;
  final DateTime date;

  /// The person whose name matched, when one did.
  final String? participantId;
}

final class SplitData {
  const SplitData({
    required this.expenseId,
    required this.merchant,
    required this.amount,
    required this.people,
    this.suggestions = const [],
  });

  final String expenseId;
  final String merchant;
  final Money amount;
  final List<SplitPerson> people;
  final List<SplitSuggestion> suggestions;

  Money get reimbursed =>
      Money(amount.currency, people.fold(0, (s, p) => s + p.repaidMinor));
}

/// One row the user edited in Mode A. [id] is null for a new person.
final class SplitEdit {
  const SplitEdit({this.id, required this.name, required this.shareMinor});

  final String? id;
  final String name;
  final int shareMinor;
}

final class AssignCandidate {
  const AssignCandidate({
    required this.expenseId,
    required this.merchant,
    required this.date,
    required this.amount,
    required this.room,
  });

  final String expenseId;
  final String merchant;
  final DateTime date;
  final Money amount;

  /// What the expense can still take (amount minus its links).
  final Money room;
}

final class AssignData {
  const AssignData({
    required this.sourceId,
    required this.person,
    required this.amount,
    required this.left,
    required this.candidates,
    required this.windowDays,
    required this.searchedAll,
  });

  final String sourceId;

  /// Who sent it (counterparty), display string.
  final String person;
  final Money amount;

  /// The incoming amount minus what is already assigned.
  final Money left;
  final List<AssignCandidate> candidates;
  final int windowDays;
  final bool searchedAll;
}

final class AssignLine {
  const AssignLine({required this.expenseId, required this.amountMinor});
  final String expenseId;
  final int amountMinor;
}

final class LinkCandidate {
  const LinkCandidate({
    required this.id,
    required this.amount,
    required this.accountLabel,
    required this.when,
    required this.gapMinutes,
  });

  final String id;
  final Money amount;
  final String accountLabel;
  final DateTime when;

  /// Candidate time minus source time, in minutes (negative = earlier).
  final int gapMinutes;
}

final class LinkData {
  const LinkData({
    required this.id,
    required this.amount,
    required this.accountLabel,
    required this.when,
    required this.isOut,
    required this.candidates,
  });

  final String id;
  final Money amount;
  final String accountLabel;
  final DateTime when;

  /// True for a transfer-out source: candidates are incoming legs.
  final bool isOut;

  /// Best matches first.
  final List<LinkCandidate> candidates;
}

/// Reads and writes for both sheets. Failures are `SafeException`s with
/// codes only.
abstract interface class TransfersSheetPort {
  Future<SplitData?> loadSplit(String expenseId);

  /// Persists the edited people in one go: new, changed and removed.
  Future<void> saveSplit(
    String expenseId,
    List<SplitEdit> edits,
    Set<String> removedIds,
  );

  Future<AssignData?> loadAssign(String sourceId, {bool searchAll = false});

  /// Returns the amount actually granted (clamped by the plan).
  Future<Money> assign(
    String sourceId,
    List<AssignLine> lines, {
    String? participantId,
  });

  Future<void> unassign(String linkId);

  Future<LinkData?> loadLink(String txnId);

  Future<void> link(String outId, String inId);

  /// Undo of [link]: unpairs the pair [txnId] belongs to.
  Future<void> unlink(String txnId);

  /// One-sided internal transfer (EC-15). False when not supported yet.
  bool get supportsMarkAnyway;
  Future<void> markAnyway(String txnId);
}
