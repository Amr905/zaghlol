// T-050: the Drift-backed [TransactionRepository]. Maps rows to domain
// records, validates input before it reaches SQL, runs multi-row writes in
// one database transaction, and surfaces failures as code-only exceptions
// ([TransactionsException], DbWriteException, DbReadException). Nothing here
// logs, and no exception carries a value from a row.

import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/money_columns.dart';
import '../domain/transaction.dart';
import '../domain/transaction_repository.dart';

/// Most ids in one filter set or one bulk call (an untrusted-input cap).
const int maxIdsPerCall = 1000;

/// Longest stored merchant text and note, in code points.
const int maxMerchantRunes = 200;
const int maxNoteRunes = 1000;

typedef Clock = DateTime Function();
typedef IdGenerator = String Function();

/// A random (version 4) UUID.
String newUuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${[for (var i = 0; i < 4; i++) h(i)].join()}-'
      '${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-'
      '${[for (var i = 10; i < 16; i++) h(i)].join()}';
}

class DriftTransactionRepository implements TransactionRepository {
  DriftTransactionRepository(this._dao, {Clock? clock, IdGenerator? newId})
    : _now = clock ?? DateTime.now,
      _newId = newId ?? newUuidV4;

  final TransactionsDao _dao;
  final Clock _now;
  final IdGenerator _newId;

  int _nowMs() => _now().toUtc().millisecondsSinceEpoch;

  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async {
    final rows = await _dao.list(
      _toQuery(filter, text),
      limit: page.limit,
      offset: page.offset,
    );
    return [for (final r in rows) _toRecord(r)];
  }

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) => _dao.countMatching(_toQuery(filter, text));

  @override
  Future<TransactionRecord?> byId(
    String id, {
    bool includeDeleted = false,
  }) async {
    final row = await _dao.byId(id);
    if (row == null || (row.deletedAt != null && !includeDeleted)) return null;
    return _toRecord(row);
  }

  @override
  Future<TransactionRecord> add(NewTransaction txn) async {
    _requireId(txn.accountId);
    _requireNonNegative(txn.amount);
    if (txn.originalAmount != null) _requireNonNegative(txn.originalAmount!);
    _requireOffset(txn.occurredTzOffsetMin);
    final categoryId = _blankToNull(txn.categoryId);
    final now = _nowMs();
    final id = _newId();
    final amount = txn.amount.toStorage();
    final original = txn.originalAmount?.toStorage();
    final merchant = _text(txn.merchant, maxMerchantRunes);
    final note = _text(txn.note, maxNoteRunes);
    return _dao.inTransaction(() async {
      await _dao.insert(
        TransactionsCompanion.insert(
          id: id,
          accountId: txn.accountId,
          source: txn.source.code,
          direction: txn.direction.code,
          amountMinor: amount.minor,
          currency: amount.currency,
          originalAmountMinor: Value(original?.minor),
          originalCurrency: Value(original?.currency),
          occurredAt: txn.occurredAt.toUtc().millisecondsSinceEpoch,
          occurredTzOffsetMin: txn.occurredTzOffsetMin,
          merchantRaw: Value(merchant),
          categoryId: Value(categoryId),
          categorySource: categoryId == null ? 'none' : 'user',
          isUserVerified: const Value(1),
          note: Value(note),
          createdAt: now,
          updatedAt: now,
        ),
      );
      return _toRecord((await _dao.byId(id))!);
    });
  }

  @override
  Future<TransactionRecord> edit(String id, TransactionEdit edit) async {
    if (edit.accountId != null) _requireId(edit.accountId!);
    if (edit.amount != null) _requireNonNegative(edit.amount!);
    if (edit.occurredTzOffsetMin != null) {
      _requireOffset(edit.occurredTzOffsetMin!);
    }
    final now = _nowMs();
    return _dao.inTransaction(() async {
      final current = await _dao.byId(id);
      if (current == null || current.deletedAt != null) _notFound();
      final category = edit.categoryId;
      final categoryId = category == null ? null : _blankToNull(category.value);
      final merchant = edit.merchant;
      final note = edit.note;
      var patch = TransactionsCompanion(
        accountId: edit.accountId == null
            ? const Value.absent()
            : Value(edit.accountId!),
        direction: edit.direction == null
            ? const Value.absent()
            : Value(edit.direction!.code),
        status: edit.status == null
            ? const Value.absent()
            : Value(edit.status!.code),
        occurredAt: edit.occurredAt == null
            ? const Value.absent()
            : Value(edit.occurredAt!.toUtc().millisecondsSinceEpoch),
        occurredTzOffsetMin: edit.occurredTzOffsetMin == null
            ? const Value.absent()
            : Value(edit.occurredTzOffsetMin!),
        categoryId: category == null ? const Value.absent() : Value(categoryId),
        categorySource: category == null
            ? const Value.absent()
            : Value(categoryId == null ? 'none' : 'user'),
        // The derived name is stale once the user retypes the merchant;
        // categorisation recomputes it.
        merchantRaw: merchant == null
            ? const Value.absent()
            : Value(_text(merchant.value, maxMerchantRunes)),
        merchantNorm: merchant == null
            ? const Value.absent()
            : const Value(null),
        note: note == null
            ? const Value.absent()
            : Value(_text(note.value, maxNoteRunes)),
        // FR-TXN-02: any edit of a stored (e.g. auto-captured) row.
        isUserVerified: const Value(1),
        updatedAt: Value(now),
      );
      if (edit.amount != null) patch = patch.withAmount(edit.amount!);
      if ((await _dao.updateById(id, patch)) != 1) _notFound();
      return _toRecord((await _dao.byId(id))!);
    });
  }

  @override
  Future<void> softDelete(Iterable<String> ids) async {
    final unique = _uniqueIds(ids);
    final now = _nowMs();
    await _dao.inTransaction(() async {
      for (final id in unique) {
        if (await _dao.softDelete(id, at: now) != 1) _notFound();
      }
    });
  }

  @override
  Future<void> restore(Iterable<String> ids) async {
    final unique = _uniqueIds(ids);
    final now = _nowMs();
    await _dao.inTransaction(() async {
      for (final id in unique) {
        if (await _dao.restore(id, at: now) == 1) continue;
        throw TransactionsException(
          await _dao.byId(id) == null
              ? TransactionsException.notFound
              : TransactionsException.notDeleted,
        );
      }
    });
  }

  @override
  Future<int> purgeExpired() {
    // Evidence is the stored deleted_at only. A device clock set far ahead
    // would purge early: accepted residual (no trusted time source here).
    final cutoff = _now()
        .toUtc()
        .subtract(const Duration(days: softDeleteRetentionDays))
        .millisecondsSinceEpoch;
    return _dao.purgeDeletedAtOrBefore(cutoff);
  }

  TxnQuery _toQuery(TransactionFilter f, String? text) {
    for (final n in [
      f.accountIds.length,
      f.categoryIds.length,
      f.directions.length,
      f.sources.length,
      f.currencies.length,
      f.statuses.length,
    ]) {
      if (n > maxIdsPerCall) _invalid();
    }
    return TxnQuery(
      from: f.from?.toUtc().millisecondsSinceEpoch,
      to: f.to?.toUtc().millisecondsSinceEpoch,
      accountIds: f.accountIds,
      categoryIds: f.categoryIds,
      directions: {for (final d in f.directions) d.code},
      sources: {for (final s in f.sources) s.code},
      currencies: {for (final c in f.currencies) c.code},
      statuses: {for (final s in f.statuses) s.code},
      text: text,
    );
  }

  TransactionRecord _toRecord(TransactionRow r) => TransactionRecord(
    id: r.id,
    accountId: r.accountId,
    source: TxnSource.fromCode(r.source),
    direction: TxnDirection.fromCode(r.direction),
    status: TxnStatus.fromCode(r.status),
    amount: r.amount,
    originalAmount: r.originalAmount,
    occurredAt: DateTime.fromMillisecondsSinceEpoch(r.occurredAt, isUtc: true),
    occurredTzOffsetMin: r.occurredTzOffsetMin,
    merchantRaw: r.merchantRaw,
    merchantNorm: r.merchantNorm,
    categoryId: r.categoryId,
    categorySource: CategorySource.fromCode(r.categorySource),
    isUserVerified: r.isUserVerified == 1,
    isInternal: r.isInternal == 1,
    note: r.note,
    deletedAt: r.deletedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.deletedAt!, isUtc: true),
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt, isUtc: true),
  );

  List<String> _uniqueIds(Iterable<String> ids) {
    final unique = ids.toSet();
    if (unique.isEmpty || unique.length > maxIdsPerCall) _invalid();
    return unique.toList();
  }

  static Never _notFound() =>
      throw TransactionsException(TransactionsException.notFound);

  static Never _invalid() =>
      throw TransactionsException(TransactionsException.invalid);

  static void _requireId(String id) {
    if (id.isEmpty) _invalid();
  }

  static void _requireNonNegative(Money m) {
    if (m.isNegative) _invalid();
  }

  static void _requireOffset(int minutes) {
    if (minutes < -1080 || minutes > 1080) _invalid();
  }

  static String? _blankToNull(String? s) => (s == null || s.isEmpty) ? null : s;

  /// Trimmed, empty becomes null, cut to [maxRunes] code points.
  static String? _text(String? s, int maxRunes) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    final runes = t.runes;
    return runes.length <= maxRunes
        ? t
        : String.fromCharCodes(runes.take(maxRunes));
  }
}
