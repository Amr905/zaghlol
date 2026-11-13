// T-078: ignore rules (FR-CAP-01..07, EC-59, EC-63). One write path for
// "stop tracking this card / institution on this channel".
//
// Design note:
// - A rule is (institution, optional last-4, channel). A NULL last-4 is an
//   institution-level rule. A "before-seen" card is simply a rule for a
//   last-4 that has no account yet; nothing here needs the account.
// - Order on add: validate, commit the rule, rewrite the Guard config at
//   once (`onRuleChanged`, the caller's `await flush()`), then, only if the
//   user asked for it, delete. A failed config write leaves the rule in
//   place and is reported in the result; it is never rolled back.
// - Existing transactions are KEPT by default. Delete is a typed opt-in:
//   [DeleteExisting] carries the ids the user saw in [previewMatches] and
//   confirmed. Only ids that still match the rule and are still live are
//   deleted, so a row that arrived after the preview is never removed
//   unseen. The delete is a soft delete through [BulkEditUseCase] (30-day
//   restore, one Undo batch per chunk), and every paired transfer leg goes
//   through `TransferPairing.onRemoved` afterwards (FU-127).
// - Un-ignore only removes the rule and rewrites the config. Transactions,
//   offset links and pairs are not touched (EC-63). On Android SMS it offers
//   a re-scan of that institution; the caller runs
//   `InboxScanService.rescanInstitution` only on the user's yes.
// - Errors are code-only; nothing here logs, and no code carries an
//   institution, last-4 or id.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/capture_controls_dao.dart';
import '../../transactions/application/bulk_edit.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show maxIdsPerCall, newUuidV4;
import 'guard_config_writer.dart' show GuardWriteResult;

/// Failure codes. `IGNORE_INVALID`: malformed institution, last-4 or
/// channel. `IGNORE_NOT_FOUND`: unknown rule id.
final class IgnoreRuleException extends SafeException {
  IgnoreRuleException(super.code);

  static const String invalid = 'IGNORE_INVALID';
  static const String notFound = 'IGNORE_NOT_FOUND';
}

/// What a rule covers.
final class IgnoreTarget {
  const IgnoreTarget({
    required this.institutionCode,
    this.last4,
    required this.channel,
  });

  /// Registry institution code (lowercase `a-z0-9_`, 2..32).
  final String institutionCode;

  /// Card last digits (2..4); null = the whole institution.
  final String? last4;

  /// One of [IgnoreChannel].
  final String channel;
}

/// What happens to transactions already stored for the target.
sealed class ExistingAction {
  const ExistingAction();
}

/// The default: nothing existing is touched.
final class KeepExisting extends ExistingAction {
  const KeepExisting();
}

/// Delete after the user confirmed exactly these [confirmedIds] (from
/// [IgnoreRulesService.previewMatches]). An empty set deletes nothing.
final class DeleteExisting extends ExistingAction {
  const DeleteExisting({required this.confirmedIds});

  final Set<String> confirmedIds;
}

final class IgnorePreview {
  const IgnorePreview(this.ids);

  /// Live transactions the rule would cover, newest first.
  final List<String> ids;
  int get count => ids.length;
}

final class AddIgnoreResult {
  const AddIgnoreResult({
    required this.ruleId,
    required this.created,
    required this.guard,
    required this.deleted,
    required this.undoBatchIds,
  });

  /// The id of the rule (the existing one when [created] is false).
  final String ruleId;

  /// False when an equal rule already existed (double tap, two engines).
  final bool created;

  /// Null when no config write was wired; check it before telling the user
  /// the rule is in force.
  final GuardWriteResult? guard;

  /// Transactions soft-deleted.
  final int deleted;

  /// Undo batches of the delete (one per chunk of [maxIdsPerCall]).
  final List<String> undoBatchIds;
}

/// Offer shown after un-ignore: scan the inbox again for [institutionCode].
final class RescanOffer {
  const RescanOffer(this.institutionCode);

  final String institutionCode;
}

final class RemoveIgnoreResult {
  const RemoveIgnoreResult({
    required this.removed,
    required this.guard,
    required this.rescanOffer,
  });

  final bool removed;
  final GuardWriteResult? guard;

  /// Non-null only for an SMS rule on Android (FR-CAP-07).
  final RescanOffer? rescanOffer;
}

final RegExp _institutionRe = RegExp(r'^[a-z0-9_]{2,32}$');
final RegExp _last4Re = RegExp(r'^[0-9]{2,4}$');
const Set<String> _channels = {
  IgnoreChannel.sms,
  IgnoreChannel.notification,
  IgnoreChannel.applePay,
};

/// `transactions.source` for each rule channel.
const Map<String, String> _sourceOfChannel = {
  IgnoreChannel.sms: 'sms',
  IgnoreChannel.notification: 'notification',
  IgnoreChannel.applePay: 'apple_pay',
};

/// Arabic-Indic and Persian digits to Latin (input normalization).
String _latinDigits(String s) {
  final b = StringBuffer();
  for (final u in s.runes) {
    if (u >= 0x0660 && u <= 0x0669) {
      b.writeCharCode(u - 0x0660 + 0x30);
    } else if (u >= 0x06F0 && u <= 0x06F9) {
      b.writeCharCode(u - 0x06F0 + 0x30);
    } else {
      b.writeCharCode(u);
    }
  }
  return b.toString();
}

class IgnoreRulesService {
  IgnoreRulesService(
    this._db, {
    required BulkEditUseCase bulkEdit,
    required this._onRemoved,
    this._onRuleChanged,
    this.rescanAvailable = false,
    int Function()? nowMs,
    String Function()? newId,
  }) : _dao = CaptureControlsDao(_db),
       _bulk = bulkEdit,
       _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch),
       _newId = newId ?? newUuidV4;

  final AppDatabase _db;
  final CaptureControlsDao _dao;
  final BulkEditUseCase _bulk;

  /// `TransferPairing.onRemoved` of the pairing use case; called for every
  /// deleted transaction that was a paired leg (FU-127).
  final Future<void> Function(String txnId) _onRemoved;
  final Future<GuardWriteResult> Function()? _onRuleChanged;

  /// True on Android with SMS live capture, where a re-scan can be offered.
  final bool rescanAvailable;
  final int Function() _nowMs;
  final String Function() _newId;

  IgnoreTarget _normalize(IgnoreTarget t) {
    final inst = t.institutionCode.trim();
    final last4 = t.last4 == null ? null : _latinDigits(t.last4!.trim());
    if (!_institutionRe.hasMatch(inst) ||
        !_channels.contains(t.channel) ||
        (last4 != null && !_last4Re.hasMatch(last4))) {
      throw IgnoreRuleException(IgnoreRuleException.invalid);
    }
    return IgnoreTarget(
      institutionCode: inst,
      last4: last4,
      channel: t.channel,
    );
  }

  /// Live transactions of [target] (its channel's source, accounts of the
  /// institution, that last-4 or all). Read-only; use it for the "delete N
  /// transactions?" confirmation.
  Future<IgnorePreview> previewMatches(IgnoreTarget target) async {
    final t = _normalize(target);
    return IgnorePreview(await _matching(t));
  }

  Future<List<String>> _matching(IgnoreTarget t) async {
    final rows = await _db
        .customSelect(
          'SELECT t.id AS id FROM transactions t '
          'JOIN accounts a ON a.id = t.account_id '
          'WHERE t.deleted_at IS NULL AND t.source = ?1 '
          'AND lower(a.institution_code) = ?2 '
          'AND (?3 IS NULL OR a.last4 = ?3) '
          'ORDER BY t.occurred_at DESC, t.id',
          variables: [
            Variable.withString(_sourceOfChannel[t.channel]!),
            Variable.withString(t.institutionCode),
            Variable<String>(t.last4),
          ],
          readsFrom: {_db.transactions, _db.accounts},
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  /// Adds the rule, rewrites the Guard config, then applies [existing].
  Future<AddIgnoreResult> add(
    IgnoreTarget target, {
    ExistingAction existing = const KeepExisting(),
  }) async {
    final t = _normalize(target);
    final newId = _newId();
    final created = await _dao.addIgnoreRule(
      id: newId,
      institutionCode: t.institutionCode,
      last4: t.last4,
      channel: t.channel,
      createdAt: _nowMs(),
    );
    final ruleId = created ? newId : await _existingRuleId(t) ?? newId;
    final guard = await _onRuleChanged?.call();

    var deleted = 0;
    final batches = <String>[];
    if (existing is DeleteExisting && existing.confirmedIds.isNotEmpty) {
      // Intersection with what still matches: never delete unseen rows.
      final now = (await _matching(t)).toSet();
      final ids = [
        for (final id in existing.confirmedIds)
          if (now.contains(id)) id,
      ]..sort();
      for (var i = 0; i < ids.length; i += maxIdsPerCall) {
        final chunk = ids.sublist(
          i,
          i + maxIdsPerCall > ids.length ? ids.length : i + maxIdsPerCall,
        );
        final paired = await _pairedAmong(chunk);
        final r = await _bulk.apply(chunk, const DeleteTransactions());
        batches.add(r.batchId);
        deleted += r.changed;
        for (final id in paired) {
          await _onRemoved(id);
        }
      }
    }
    return AddIgnoreResult(
      ruleId: ruleId,
      created: created,
      guard: guard,
      deleted: deleted,
      undoBatchIds: batches,
    );
  }

  Future<String?> _existingRuleId(IgnoreTarget t) async {
    for (final r in await _dao.ignoreRules()) {
      if (r.institutionCode == t.institutionCode &&
          r.last4 == t.last4 &&
          r.channel == t.channel) {
        return r.id;
      }
    }
    return null;
  }

  Future<List<String>> _pairedAmong(List<String> ids) async {
    final out = <String>[];
    for (final id in ids) {
      final row = await (_db.select(
        _db.transactions,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (row?.transferPairId != null) out.add(id);
    }
    return out;
  }

  /// Removes rule [ruleId] (un-ignore) and rewrites the Guard config. Stored
  /// transactions, links and pairs are untouched (EC-63). An unknown id is
  /// `IGNORE_NOT_FOUND` (a second tap or another engine already removed it).
  Future<RemoveIgnoreResult> remove(String ruleId) async {
    if (ruleId.isEmpty) throw IgnoreRuleException(IgnoreRuleException.invalid);
    IgnoreRuleRow? rule;
    for (final r in await _dao.ignoreRules()) {
      if (r.id == ruleId) rule = r;
    }
    if (rule == null) throw IgnoreRuleException(IgnoreRuleException.notFound);
    final n = await _dao.removeIgnoreRule(ruleId);
    final guard = await _onRuleChanged?.call();
    return RemoveIgnoreResult(
      removed: n == 1,
      guard: guard,
      rescanOffer: rescanAvailable && rule.channel == IgnoreChannel.sms
          ? RescanOffer(rule.institutionCode)
          : null,
    );
  }

  /// Every rule, by institution, card, channel (FR-CAP-06).
  Future<List<IgnoreRuleRow>> rules() => _dao.ignoreRules();
}
