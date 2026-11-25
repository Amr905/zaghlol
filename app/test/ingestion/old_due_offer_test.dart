// T-250 (D-83, FU-295): an old CIB due reminder (PO case 7, synthetic
// digits) that a pre-batch-67 build auto-saved as spending. Re-parse with
// the bundled registry offers it once in review; only the user's Remove
// deletes it (normal delete path with Undo); Keep locks it.
// Negative proofs: (1) a user-edited transaction is never offered; (2) no
// tap, nothing removed; (3) re-parse twice offers once.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/application/old_due_review.dart';
import 'package:zaghlol/features/ingestion/application/reparse.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/data/review_repository.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/transactions/application/bulk_actions.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol/ingestion/spike_registry.dart' show RegistryGuardBase;
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' hide CategorySource;

import '../features/ingestion/support/ingest_harness.dart';

const String _case7 =
    'عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490  '
    'في 25/11, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم قبل '
    'العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط '
    'التالي: https://example.invalid/x1';

final int _rx = DateTime.utc(2026, 11, 20, 8).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IngestWorld w;
  late Registry registry;

  setUp(() async {
    registry = await preloadBundledRegistry();
    w = await IngestWorld.open();
    addTearDown(w.close);
    await AccountsDao(w.db).insert(
      AccountsCompanion.insert(
        id: 'acc_5490',
        kind: 'credit',
        label: 'CIB card',
        institutionCode: const Value('cib'),
        last4: const Value('5490'),
        defaultCurrency: 'EGP',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });

  /// What an old build stored: the raw row `parsed` under registry 1 and an
  /// auto-saved expense of 51.77 linked to it.
  Future<void> oldAutoSaved({
    String txnId = 'old1',
    int verified = 0,
    String? note,
    String categorySource = 'heuristic',
  }) async {
    // A different link per row, so the body hashes differ.
    final body = _case7.replaceAll('x1', txnId);
    await DriftIngestStore(w.db).insertRaw(
      RawInsert(
        id: 'raw_$txnId',
        channel: 'sms',
        sender: 'CIB',
        body: body,
        bodyHash: bodyHashV1(senderKey: senderKeyOf('sms', 'CIB'), body: body),
        receivedAtMs: _rx,
        parseStatus: RawStatus.parsed,
        registryVersion: 1,
        createdAtMs: _rx,
      ),
    );
    await w.db
        .into(w.db.transactions)
        .insert(
          TransactionsCompanion.insert(
            id: txnId,
            accountId: 'acc_5490',
            rawMessageId: Value('raw_$txnId'),
            source: 'sms',
            direction: 'expense',
            amountMinor: 5177,
            currency: 'EGP',
            occurredAt: _rx,
            occurredTzOffsetMin: zoneOffsetMin,
            categorySource: categorySource,
            isUserVerified: Value(verified),
            note: Value(note),
            createdAt: _rx,
            updatedAt: _rx,
          ),
        );
  }

  Future<ReparseSummary> reparse() {
    final ingest = buildIngestRawMessages(
      w.db,
      pipeline: ParsingPipeline(registry),
      guardBase: RegistryGuardBase(registry),
      newId: w.newId,
      clock: () => DateTime.fromMillisecondsSinceEpoch(_rx + 1000, isUtc: true),
      zone: const FixedLocalZone(zoneOffsetMin),
      diag: w.diag,
      events: w.bus,
    );
    return ReparseJob(
      store: DriftIngestStore(w.db),
      ingest: ingest,
      registryVersion: registry.registryVersion,
      diag: w.diag,
    ).run();
  }

  /// Makes the next start look at every raw row again (a later bump).
  Future<void> staleAgain() =>
      w.db.customUpdate('UPDATE raw_messages SET registry_version = 1');

  Future<List<Map<String, Object?>>> offers() => w.rows(
    'SELECT * FROM review_items WHERE kind = ?1 AND '
    "json_extract(payload, '\$.reason') = ?2",
    [ReviewKind.lowConfidence, ReviewReason.oldDueNotice],
  );

  /// Live spending total in EGP minor units (what totals read).
  Future<int> spendingTotal() async =>
      (await w.rows(
            'SELECT coalesce(sum(amount_minor), 0) AS s FROM transactions '
            "WHERE deleted_at IS NULL AND direction = 'expense' "
            "AND currency = 'EGP'",
          )).single['s']!
          as int;

  Future<PaydaySchedule> schedule() async => PaydaySchedule.single(1);

  OldDueReview oldDue() => OldDueReview(
    reviews: ReviewRepository(
      w.db,
      clock: () => DateTime.fromMillisecondsSinceEpoch(_rx + 5000, isUtc: true),
      newId: w.newId,
    ),
    txns: BulkActions(
      bulk: BulkEditUseCase(
        w.db,
        newId: w.newId,
        loadSchedule: schedule,
        events: w.bus,
      ),
      pairing: TransferPairingUseCase(w.db, loadSchedule: schedule),
      refunds: RefundMatching(w.db, loadSchedule: schedule),
    ),
  );

  test('case 7 auto-saved before batch 67: re-parse offers it once, the '
      'transaction stays (no tap, nothing removed)', () async {
    await oldAutoSaved();
    expect(await spendingTotal(), 5177);
    final s = await reparse();
    expect(s.offered, 1);
    final items = await offers();
    expect(items, hasLength(1));
    expect(items.single['txn_id'], 'old1');
    expect(items.single['raw_message_id'], 'raw_old1');
    expect(items.single['resolved_at'], isNull);
    // Negative proof 2: still live, still in the total.
    final t = (await w.txns()).single;
    expect(t['deleted_at'], isNull);
    expect(t['is_user_verified'], 0);
    expect(await spendingTotal(), 5177);
    // The notice reached the card dues (T-245 hook).
    final due = await w.rows('SELECT value FROM settings WHERE key = ?1', [
      cardDueKey('cib', '5490'),
    ]);
    expect(
      CardDue.decode(due.single['value']! as String)!.amountDueMinor,
      5177,
    );
    // The raw row now names the notice template.
    final raw = (await w.raws()).single;
    expect(raw['template_id'], 'cib.cc_due.ar');
    expect(raw['registry_version'], registry.registryVersion);
  });

  test('negative proof 3: re-parse twice offers once', () async {
    await oldAutoSaved();
    await reparse();
    await staleAgain();
    final s = await reparse();
    expect(s.offered, 0);
    expect(await offers(), hasLength(1));
  });

  test(
    'negative proof 1: a user-edited transaction is never offered',
    () async {
      await oldAutoSaved(verified: 1);
      await oldAutoSaved(txnId: 'noted', note: 'my note');
      await oldAutoSaved(txnId: 'cat', categorySource: 'user');
      final s = await reparse();
      expect(s.offered, 0);
      expect(await offers(), isEmpty);
      expect(await spendingTotal(), 3 * 5177);
    },
  );

  test('Remove: gone from totals through the normal delete; Undo puts it '
      'back; never offered again', () async {
    await oldAutoSaved();
    await reparse();
    final itemId = (await offers()).single['id']! as String;
    final changed = <TransactionsChanged>[];
    final sub = w.bus.events.listen((e) {
      if (e is TransactionsChanged) changed.add(e);
    });
    addTearDown(sub.cancel);

    final batchId = await oldDue().remove(itemId);
    expect(batchId, isNotNull);
    expect(await spendingTotal(), 0);
    expect((await w.txns()).single['deleted_at'], isNotNull);
    final item = (await offers()).single;
    expect(item['resolution'], ReviewResolution.removed);
    await Future<void>.delayed(Duration.zero);
    expect(changed.single.accountIds, contains('acc_5490'));

    // A second tap changes nothing.
    expect(await oldDue().remove(itemId), isNull);

    await oldDue().undoRemove(batchId!);
    expect(await spendingTotal(), 5177);
    expect((await w.txns()).single['deleted_at'], isNull);

    await staleAgain();
    expect((await reparse()).offered, 0);
    expect(await offers(), hasLength(1));
  });

  test('Keep: stays, user-verified, never offered again', () async {
    await oldAutoSaved();
    await reparse();
    final itemId = (await offers()).single['id']! as String;
    expect(await oldDue().keep(itemId), isTrue);
    expect(await oldDue().keep(itemId), isFalse);
    final t = (await w.txns()).single;
    expect(t['deleted_at'], isNull);
    expect(t['is_user_verified'], 1);
    expect((await offers()).single['resolution'], ReviewResolution.kept);
    expect(await spendingTotal(), 5177);
    // Remove after Keep does nothing.
    expect(await oldDue().remove(itemId), isNull);
    await staleAgain();
    expect((await reparse()).offered, 0);
    expect(await offers(), hasLength(1));
  });

  test('two actors: a Keep that lands between the check and the delete '
      'wins; the row is put back', () async {
    await oldAutoSaved();
    await reparse();
    final itemId = (await offers()).single['id']! as String;
    final repo = _KeepRaces(
      w.db,
      clock: () => DateTime.fromMillisecondsSinceEpoch(_rx + 5000, isUtc: true),
      newId: w.newId,
    );
    final review = OldDueReview(
      reviews: repo,
      txns: BulkActions(
        bulk: BulkEditUseCase(w.db, newId: w.newId, loadSchedule: schedule),
        pairing: TransferPairingUseCase(w.db, loadSchedule: schedule),
        refunds: RefundMatching(w.db, loadSchedule: schedule),
      ),
    );
    expect(await review.remove(itemId), isNull);
    final t = (await w.txns()).single;
    expect(t['deleted_at'], isNull);
    expect(t['is_user_verified'], 1);
    expect((await offers()).single['resolution'], ReviewResolution.kept);
  });

  test('an edit after the offer locks it: Remove refuses', () async {
    await oldAutoSaved();
    await reparse();
    final itemId = (await offers()).single['id']! as String;
    await w.db.customUpdate(
      "UPDATE transactions SET is_user_verified = 1 WHERE id = 'old1'",
    );
    expect(await oldDue().remove(itemId), isNull);
    expect((await w.txns()).single['deleted_at'], isNull);
    expect((await offers()).single['resolved_at'], isNull);
  });
}

/// Runs a Keep right after Remove's check, like a second screen would.
final class _KeepRaces extends ReviewRepository {
  _KeepRaces(super.db, {required super.clock, required super.newId});

  @override
  Future<String?> oldDueTxnToRemove(String itemId) async {
    final id = await super.oldDueTxnToRemove(itemId);
    await keepOldDue(itemId);
    return id;
  }
}
