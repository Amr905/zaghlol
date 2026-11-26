// T-046: the Drift implementation of IngestStorePort. Drift's transaction is
// `BEGIN IMMEDIATE` (sqlite3 executor), and a nested `transaction` is a
// SAVEPOINT that drift rolls back on a throw while the outer transaction
// continues (design note §2, §10). Every value is bound as a parameter;
// failures are code-only (guardRead / guardWrite). Nothing here logs.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/capture_controls_dao.dart';
import '../../../core/db/daos/raw_messages_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/transactions_dao.dart';
import '../../../core/db/daos/transfers_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../../core/db/db_errors.dart';
import '../../transactions/domain/transaction.dart';
import '../application/ingest_store_port.dart';
import '../domain/ingest_records.dart';

/// Settings keys ingest reads (database-schema §2.8).
const String kSettingPaydayDay = 'payday_day';
const String kSettingPaydayEras = 'payday_eras';
const String kSettingLanguage = 'language';

/// Most candidates one dedupe or merge read returns.
const int _maxCandidates = 100;

final class DriftIngestStore implements IngestStorePort {
  DriftIngestStore(this._db)
    : _raw = RawMessagesDao(_db),
      _txns = TransactionsDao(_db),
      _reviews = ReviewItemsDao(_db),
      _controls = CaptureControlsDao(_db);

  final AppDatabase _db;
  final RawMessagesDao _raw;
  final TransactionsDao _txns;
  final ReviewItemsDao _reviews;
  final CaptureControlsDao _controls;

  @override
  Future<T> inWriteTransaction<T>(Future<T> Function() body) =>
      guardWrite(() => _db.transaction(body));

  @override
  Future<T> inSavepoint<T>(Future<T> Function() body) => _db.transaction(body);

  @override
  Future<BatchContext> readContext() => guardRead(() async {
    final rules = await _db.select(_db.ignoreRules).get();
    final senders = await _db.select(_db.captureSenders).get();
    final templates = await _db
        .customSelect(
          'SELECT DISTINCT sender, channel FROM custom_templates',
          readsFrom: {_db.customTemplates},
        )
        .get();
    final settings =
        await (_db.select(_db.settings)..where(
              (s) => s.key.isIn([
                kSettingPaydayDay,
                kSettingPaydayEras,
                kSettingLanguage,
              ]),
            ))
            .get();
    String? setting(String key) {
      for (final s in settings) {
        if (s.key == key) return s.value;
      }
      return null;
    }

    return BatchContext(
      ignoreRules: [
        for (final r in rules)
          IgnoreRuleState(r.institutionCode, r.last4, r.channel),
      ],
      captureSenders: [
        for (final s in senders)
          CaptureSenderState(
            sender: s.sender,
            channel: s.channel,
            confirmedCount: s.confirmedCount,
            alwaysCapture: s.alwaysCapture != 0,
          ),
      ],
      customTemplateSenders: [
        for (final t in templates)
          (t.read<String>('sender'), t.read<String>('channel')),
      ],
      paydayDay: setting(kSettingPaydayDay),
      paydayEras: setting(kSettingPaydayEras),
      language: setting(kSettingLanguage),
    );
  });

  @override
  Future<bool> isIgnored({
    required String institutionCode,
    required String? last4,
    required String channel,
  }) => _controls.isIgnored(
    institutionCode: institutionCode,
    last4: last4,
    channel: channel,
  );

  @override
  Future<bool> hashExists(String bodyHash) =>
      guardRead(() => _raw.hashExists(bodyHash));

  @override
  Future<bool> insertRaw(RawInsert r) => _raw.insertIfNew(
    RawMessagesCompanion.insert(
      id: r.id,
      channel: r.channel,
      sender: Value(r.sender),
      institutionCode: Value(r.institutionCode),
      body: r.body,
      bodyHash: r.bodyHash,
      receivedAt: r.receivedAtMs,
      simSlot: Value(r.simSlot),
      parseStatus: r.parseStatus,
      templateId: Value(r.templateId),
      templateVersion: Value(r.templateVersion),
      registryVersion: r.registryVersion,
      createdAt: r.createdAtMs,
    ),
  );

  static const String _candidateColumns =
      't.id, t.account_id, a.last4 AS acc_last4, '
      'a.institution_code AS acc_inst, t.source, t.status, t.direction, '
      't.amount_minor, t.currency, t.original_amount_minor, '
      't.original_currency, t.occurred_at, t.occurred_tz_offset_min, '
      'r.received_at AS raw_rx, t.is_user_verified, t.deleted_at, '
      't.category_source, t.merchant_raw, t.merchant_norm, '
      't.counterparty_kind, t.counterparty_value, t.reference_no, '
      't.balance_after_minor, t.parse_confidence';

  static const String _candidateFrom =
      'FROM transactions t JOIN accounts a ON a.id = t.account_id '
      'LEFT JOIN raw_messages r ON r.id = t.raw_message_id';

  @override
  Future<List<TxnCandidate>> crossChannelCandidates({
    required String dedupeKey,
    required int fromMs,
    required int toMs,
  }) => guardRead(() async {
    final rows = await _db
        .customSelect(
          'SELECT $_candidateColumns $_candidateFrom '
          'WHERE t.dedupe_key = ?1 AND t.occurred_at BETWEEN ?2 AND ?3 '
          'ORDER BY t.occurred_at, t.id LIMIT $_maxCandidates',
          variables: [
            Variable.withString(dedupeKey),
            Variable.withInt(fromMs),
            Variable.withInt(toMs),
          ],
          readsFrom: {_db.transactions, _db.accounts, _db.rawMessages},
        )
        .get();
    return [for (final r in rows) _candidate(r)];
  });

  @override
  Future<List<TxnCandidate>> statusCandidates({
    required String institution,
    required String currency,
    required String status,
    required int fromMs,
    required int toMs,
  }) => guardRead(() async {
    final rows = await _db
        .customSelect(
          'SELECT $_candidateColumns $_candidateFrom '
          'WHERE a.institution_code = ?1 AND t.currency = ?2 '
          "AND t.status = ?3 AND t.direction = 'expense' "
          'AND t.deleted_at IS NULL AND t.occurred_at BETWEEN ?4 AND ?5 '
          'ORDER BY t.occurred_at, t.id LIMIT $_maxCandidates',
          variables: [
            Variable.withString(institution),
            Variable.withString(currency),
            Variable.withString(status),
            Variable.withInt(fromMs),
            Variable.withInt(toMs),
          ],
          readsFrom: {_db.transactions, _db.accounts, _db.rawMessages},
        )
        .get();
    return [for (final r in rows) _candidate(r)];
  });

  TxnCandidate _candidate(QueryRow r) {
    final currency = r.read<String>('currency');
    final originalMinor = r.readNullable<int>('original_amount_minor');
    final originalCurrency = r.readNullable<String>('original_currency');
    final confidence = r.readNullable<double>('parse_confidence');
    return TxnCandidate(
      id: r.read<String>('id'),
      accountId: r.read<String>('account_id'),
      accountLast4: r.readNullable<String>('acc_last4'),
      accountInstitution: r.readNullable<String>('acc_inst'),
      source: r.read<String>('source'),
      status: TxnStatus.fromCode(r.read<String>('status')),
      direction: TxnDirection.fromCode(r.read<String>('direction')),
      amount: Money.fromStorage(r.read<int>('amount_minor'), currency),
      originalAmount: originalMinor == null || originalCurrency == null
          ? null
          : Money.fromStorage(originalMinor, originalCurrency),
      occurredAtMs: r.read<int>('occurred_at'),
      tzOffsetMin: r.read<int>('occurred_tz_offset_min'),
      rawReceivedAtMs: r.readNullable<int>('raw_rx'),
      isUserVerified: r.read<int>('is_user_verified') != 0,
      isDeleted: r.readNullable<int>('deleted_at') != null,
      categorySource: CategorySource.fromCode(
        r.read<String>('category_source'),
      ),
      merchantRaw: r.readNullable<String>('merchant_raw'),
      merchantNorm: r.readNullable<String>('merchant_norm'),
      counterpartyKind: r.readNullable<String>('counterparty_kind'),
      counterpartyValue: r.readNullable<String>('counterparty_value'),
      referenceNo: r.readNullable<String>('reference_no'),
      balanceAfterMinor: r.readNullable<int>('balance_after_minor'),
      // ignore: no_double_money (a confidence, 0..1, not money)
      parseConfidencePermille: confidence == null
          ? null
          : (confidence * 1000).round(),
    );
  }

  @override
  Future<void> insertTxn(TxnInsert t) {
    final amount = t.amount.toStorage();
    final original = t.originalAmount?.toStorage();
    return _txns.insert(
      TransactionsCompanion.insert(
        id: t.id,
        accountId: t.accountId,
        rawMessageId: Value(t.rawMessageId),
        source: t.source.code,
        direction: t.direction.code,
        status: Value(t.status.code),
        amountMinor: amount.minor,
        currency: amount.currency,
        originalAmountMinor: Value(original?.minor),
        originalCurrency: Value(original?.currency),
        occurredAt: t.occurredAtMs,
        occurredTzOffsetMin: t.tzOffsetMin,
        merchantRaw: Value(t.merchantRaw),
        merchantNorm: Value(t.merchantNorm),
        catalogMerchantId: Value(t.catalogMerchantId),
        counterpartyKind: Value(t.counterpartyKind),
        counterpartyValue: Value(t.counterpartyValue),
        categoryId: Value(t.categoryId),
        categorySource: t.categorySource.code,
        isUserVerified: Value(t.isUserVerified ? 1 : 0),
        referenceNo: Value(t.referenceNo),
        balanceAfterMinor: Value(t.balanceAfterMinor),
        templateId: Value(t.templateId),
        parseConfidence: Value(_confidence(t.parseConfidencePermille)),
        dedupeKey: Value(t.dedupeKey),
        createdAt: t.createdAtMs,
        updatedAt: t.createdAtMs,
      ),
    );
  }

  @override
  Future<void> insertExchangePair({
    required String id,
    required String outTxnId,
    required String inTxnId,
    required int createdAtMs,
  }) async {
    await TransferPairsDao(_db).insert(
      TransferPairsCompanion.insert(
        id: id,
        outTxnId: outTxnId,
        inTxnId: Value(inTxnId),
        kind: TransferPairKind.fxConversion,
        createdAt: createdAtMs,
      ),
    );
    for (final leg in [outTxnId, inTxnId]) {
      final n = await guardWrite(
        () => _db.customUpdate(
          'UPDATE transactions SET is_internal = 1, transfer_pair_id = ?2, '
          'updated_at = ?3 WHERE id = ?1 AND deleted_at IS NULL '
          'AND transfer_pair_id IS NULL',
          variables: [
            Variable.withString(leg),
            Variable.withString(id),
            Variable.withInt(createdAtMs),
          ],
          updates: {_db.transactions},
        ),
      );
      // Exactly one row: the leg this savepoint just inserted.
      if (n != 1) throw DbWriteException(DbWriteException.constraint);
    }
  }

  @override
  Future<String?> exchangeInLegOf(String outTxnId) => guardRead(() async {
    final row = await _db
        .customSelect(
          'SELECT p.in_txn_id AS in_id FROM transfer_pairs p '
          'JOIN transactions o ON o.id = p.out_txn_id '
          'JOIN transactions i ON i.id = p.in_txn_id '
          "WHERE p.out_txn_id = ?1 AND p.kind IN ('fx_conversion', "
          "'cross_currency') AND o.deleted_at IS NULL "
          'AND i.deleted_at IS NULL',
          variables: [Variable.withString(outTxnId)],
          readsFrom: {_db.transferPairs, _db.transactions},
        )
        .getSingleOrNull();
    return row?.read<String>('in_id');
  });

  @override
  Future<void> recordCrossChannelCopy({
    required String id,
    required String rawMessageId,
    required String txnId,
    required String source,
    required int atMs,
  }) => guardWrite(
    () => _db
        .into(_db.reviewItems)
        .insert(
          ReviewItemsCompanion.insert(
            id: id,
            kind: ReviewKind.lowConfidence,
            rawMessageId: Value(rawMessageId),
            txnId: Value(txnId),
            payload: Value(
              jsonEncode({
                'reason': ReviewReason.crossChannelCopy,
                'source': source,
              }),
            ),
            createdAt: atMs,
            resolvedAt: Value(atMs),
            resolution: const Value(ReviewReason.crossChannelCopyResolution),
          ),
        ),
  );

  @override
  Future<bool> hasCrossChannelCopy(String txnId, String source) =>
      guardRead(() async {
        final row = await _db
            .customSelect(
              'SELECT 1 AS x FROM review_items WHERE txn_id = ?1 '
              'AND kind = ?2 AND resolution = ?3 AND json_valid(payload) '
              "AND json_extract(payload, '\$.reason') = ?4 "
              "AND json_extract(payload, '\$.source') = ?5 LIMIT 1",
              variables: [
                Variable.withString(txnId),
                Variable.withString(ReviewKind.lowConfidence),
                Variable.withString(ReviewReason.crossChannelCopyResolution),
                Variable.withString(ReviewReason.crossChannelCopy),
                Variable.withString(source),
              ],
              readsFrom: {_db.reviewItems},
            )
            .getSingleOrNull();
        return row != null;
      });

  @override
  Future<BalanceJumpFacts?> balanceJumpFacts({
    required String accountId,
    required String currency,
    required int asOfMs,
    required int lookbackMs,
  }) => guardRead(() async {
    final acc = await _db
        .customSelect(
          'SELECT kind, linked_account_id FROM accounts '
          'WHERE id = ?1 AND merged_into_id IS NULL',
          variables: [Variable.withString(accountId)],
          readsFrom: {_db.accounts},
        )
        .getSingleOrNull();
    if (acc == null) return null;
    final kind = acc.read<String>('kind');
    if (kind == 'credit' || kind == 'bnpl') return null;
    final prev = await _db
        .customSelect(
          'SELECT balance_minor, as_of FROM account_balances '
          'WHERE account_id = ?1 AND currency = ?2',
          variables: [
            Variable.withString(accountId),
            Variable.withString(currency),
          ],
          readsFrom: {_db.accountBalances},
        )
        .getSingleOrNull();
    final prevMinor = prev?.readNullable<int>('balance_minor');
    final prevAt = prev?.read<int>('as_of');
    if (prevMinor == null || prevAt == null || prevAt >= asOfMs) return null;
    // The ledger: the account, the account it is linked to, and every
    // live card linked to either (T-266: one ledger, counted once).
    final root = acc.readNullable<String>('linked_account_id') ?? accountId;
    final eff = await _db
        .customSelect(
          'SELECT COALESCE(SUM(CASE '
          "WHEN direction IN ('income','refund','transfer_in') "
          'THEN amount_minor '
          "WHEN direction IN ('expense','fee','transfer_out') "
          'THEN -amount_minor ELSE 0 END), 0) AS eff '
          'FROM transactions WHERE currency = ?1 '
          "AND deleted_at IS NULL AND status = 'posted' "
          'AND occurred_at > ?2 AND occurred_at <= ?3 '
          'AND account_id IN (SELECT id FROM accounts WHERE id = ?4 '
          'OR (linked_account_id = ?4 AND merged_into_id IS NULL))',
          variables: [
            Variable.withString(currency),
            Variable.withInt(prevAt),
            Variable.withInt(asOfMs),
            Variable.withString(root),
          ],
          readsFrom: {_db.transactions, _db.accounts},
        )
        .getSingle();
    final foreign = await _db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM transactions WHERE currency <> ?1 '
          "AND direction IN ('income','transfer_in') AND is_internal = 0 "
          "AND deleted_at IS NULL AND status = 'posted' "
          'AND occurred_at > ?2 AND occurred_at <= ?3) AS f',
          variables: [
            Variable.withString(currency),
            Variable.withInt(asOfMs - lookbackMs),
            Variable.withInt(asOfMs),
          ],
          readsFrom: {_db.transactions},
        )
        .getSingle();
    return BalanceJumpFacts(
      previousMinor: prevMinor,
      countedEffectMinor: eff.read<int>('eff'),
      foreignCredit: foreign.read<int>('f') != 0,
    );
  });

  @override
  Future<int> updateTxn(String txnId, TxnPatch p, {required int atMs}) {
    Value<T> v<T extends Object>(T? x) =>
        x == null ? Value<T>.absent() : Value<T>(x);
    final amount = p.amount?.toStorage();
    final original = p.originalAmount?.toStorage();
    return _txns.updateById(
      txnId,
      TransactionsCompanion(
        accountId: v(p.accountId),
        status: v(p.status?.code),
        amountMinor: v(amount?.minor),
        currency: v(amount?.currency),
        originalAmountMinor: v(original?.minor),
        originalCurrency: v(original?.currency),
        merchantRaw: v(p.merchantRaw),
        merchantNorm: v(p.merchantNorm),
        counterpartyKind: v(p.counterpartyKind),
        counterpartyValue: v(p.counterpartyValue),
        referenceNo: v(p.referenceNo),
        balanceAfterMinor: v(p.balanceAfterMinor),
        parseConfidence: v(_confidence(p.parseConfidencePermille)),
        categoryId: v(p.categoryId),
        categorySource: v(p.categorySource?.code),
        catalogMerchantId: v(p.catalogMerchantId),
        dedupeKey: v(p.dedupeKey),
        updatedAt: Value(atMs),
      ),
    );
  }

  // ignore: no_double_money (a confidence, 0..1, not money)
  static double? _confidence(int? permille) =>
      // ignore: no_double_money (a confidence, 0..1, not money)
      permille == null ? null : permille.clamp(0, 1000) / 1000;

  @override
  Future<void> insertReview({
    required String id,
    required String kind,
    required int createdAtMs,
    String? rawMessageId,
    String? txnId,
    Map<String, Object?>? payload,
  }) => _reviews.insert(
    id: id,
    kind: kind,
    rawMessageId: rawMessageId,
    txnId: txnId,
    payload: payload,
    createdAt: createdAtMs,
  );

  @override
  Future<List<StoredRaw>> rawsToReparse({
    required int registryVersion,
    required String afterId,
    required int limit,
  }) => guardRead(() async {
    final rows = await _db
        .customSelect(
          'SELECT id, channel, sender, body, received_at, sim_slot, '
          'parse_status, template_id, template_version, registry_version '
          'FROM raw_messages WHERE id > ?1 '
          "AND channel IN ('sms', 'notification', 'shortcut_message', "
          "'apple_pay') "
          "AND (parse_status = 'reparse_pending' "
          "OR (parse_status IN ('review', 'parsed') "
          'AND registry_version < ?2)) '
          'ORDER BY id LIMIT ?3',
          variables: [
            Variable.withString(afterId),
            Variable.withInt(registryVersion),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.rawMessages},
        )
        .get();
    return [
      for (final r in rows)
        StoredRaw(
          id: r.read<String>('id'),
          channel: r.read<String>('channel'),
          sender: r.readNullable<String>('sender'),
          body: r.read<String>('body'),
          receivedAtMs: r.read<int>('received_at'),
          simSlot: r.readNullable<int>('sim_slot'),
          parseStatus: r.read<String>('parse_status'),
          templateId: r.readNullable<String>('template_id'),
          templateVersion: r.readNullable<int>('template_version'),
          registryVersion: r.read<int>('registry_version'),
        ),
    ];
  });

  @override
  Future<bool> promoteRaw(PromoteRaw p) => guardWrite(() async {
    final changed = await _db.customUpdate(
      'UPDATE raw_messages SET parse_status = ?3, registry_version = ?4, '
      'institution_code = coalesce(?5, institution_code), '
      'template_id = coalesce(?6, template_id), '
      'template_version = coalesce(?7, template_version) '
      'WHERE id = ?1 AND parse_status = ?2',
      variables: [
        Variable.withString(p.id),
        Variable.withString(p.fromStatus),
        Variable.withString(p.toStatus),
        Variable.withInt(p.registryVersion),
        Variable<String>(p.institutionCode),
        Variable<String>(p.templateId),
        Variable<int>(p.templateVersion),
      ],
      updates: {_db.rawMessages},
    );
    if (changed != 1) return false;
    if (p.fromStatus == 'review' && p.toStatus == 'parsed') {
      await _db.customUpdate(
        "UPDATE review_items SET resolved_at = ?2, resolution = 'reparsed' "
        'WHERE raw_message_id = ?1 AND resolved_at IS NULL',
        variables: [Variable.withString(p.id), Variable.withInt(p.atMs)],
        updates: {_db.reviewItems},
      );
    }
    return true;
  });

  @override
  Future<ReparseTarget?> txnOfRaw(String rawId) => guardRead(() async {
    final rows = await _db
        .customSelect(
          'SELECT $_candidateColumns, '
          '(t.transfer_pair_id IS NOT NULL OR t.is_internal = 1) AS linked '
          '$_candidateFrom WHERE t.raw_message_id = ?1 '
          'ORDER BY t.id LIMIT 1',
          variables: [Variable.withString(rawId)],
          readsFrom: {_db.transactions, _db.accounts, _db.rawMessages},
        )
        .get();
    if (rows.isEmpty) return null;
    return ReparseTarget(
      _candidate(rows.single),
      linked: rows.single.read<int>('linked') != 0,
    );
  });

  @override
  Future<List<String>> oldDueOfferTxns(String rawId) => guardRead(() async {
    final rows = await _db
        .customSelect(
          'SELECT t.id FROM transactions t WHERE t.raw_message_id = ?1 '
          'AND t.deleted_at IS NULL AND t.is_user_verified = 0 '
          "AND t.source IN ('sms', 'notification', 'shortcut', 'apple_pay') "
          "AND t.direction IN ('expense', 'fee') "
          "AND t.category_source <> 'user' AND t.note IS NULL "
          'AND t.transfer_pair_id IS NULL AND t.is_internal = 0 '
          'AND NOT EXISTS (SELECT 1 FROM split_participants s '
          'WHERE s.expense_txn_id = t.id) '
          'AND NOT EXISTS (SELECT 1 FROM recurring_occurrences ro '
          'WHERE ro.txn_id = t.id) '
          'AND NOT EXISTS (SELECT 1 FROM offset_links o '
          'WHERE o.expense_txn_id = t.id OR o.source_txn_id = t.id) '
          'AND NOT EXISTS (SELECT 1 FROM review_items i WHERE i.txn_id = t.id '
          "AND json_valid(i.payload) AND json_extract(i.payload, '\$.reason') "
          '= ?2) '
          'ORDER BY t.id',
          variables: [
            Variable.withString(rawId),
            Variable.withString(ReviewReason.oldDueNotice),
          ],
          readsFrom: {
            _db.transactions,
            _db.splitParticipants,
            _db.offsetLinks,
            _db.recurringOccurrences,
            _db.reviewItems,
          },
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  });
}
