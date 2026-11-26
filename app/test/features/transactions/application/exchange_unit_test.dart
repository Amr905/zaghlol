// T-281 (FU-365): an exchange is deleted and undone as one unit, and no
// delete path ever leaves half an exchange counted as income or spending.
// Synthetic data only.

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/transactions/application/bulk_actions.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late TransferPairingUseCase pairing;
  late BulkEditUseCase bulk;
  late BulkActions actions;
  late String outId;
  late String inId;
  late String pairId;
  var nextId = 0;
  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');
  // The current cycle (not cached), 2026-10-01..31.
  final october = Cycle(
    start: CivilDate(2026, 10, 1),
    end: CivilDate(2026, 10, 31),
  );
  final nowMs = DateTime.utc(2026, 10, 28, 9).millisecondsSinceEpoch;
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true);
  Future<PaydaySchedule> schedule() async => PaydaySchedule.single(1);

  CycleRepository cycles() => CycleRepository(
    db,
    nowUtcMs: () => nowMs,
    zone: const FixedLocalZone(120),
  );

  /// Every figure of every currency, as plain ints.
  Future<Map<String, List<int>>> snapshot() async => {
    for (final t in (await cycles().totals(october)).values)
      t.currency.code: [
        t.income.minor,
        t.spend.minor,
        t.exchangedIn.minor,
        t.exchangedOut.minor,
        t.left.minor,
      ],
  };

  Future<int> pairs() async =>
      (await db.customSelect('SELECT id FROM transfer_pairs').get()).length;

  Future<TransactionRow> row(String id) async =>
      (await TransactionsDao(db).byId(id))!;

  setUp(() async {
    nextId = 0;
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('egp'));
    await db
        .into(db.accounts)
        .insert(account('usd', last4: '9945', currency: 'USD'));
    // Something ordinary in both currencies, so totals are not all zero.
    await TransactionsDao(db).insert(
      txn(
        'food',
        accountId: 'egp',
        amountMinor: 50000,
        occurredAt: DateTime.utc(2026, 10, 20, 10).millisecondsSinceEpoch,
      ),
    );
    await TransactionsDao(db).insert(
      txn(
        'salary',
        accountId: 'usd',
        direction: 'income',
        amountMinor: 100000,
        currency: 'USD',
        occurredAt: DateTime.utc(2026, 10, 24, 10).millisecondsSinceEpoch,
      ),
    );
    pairing = TransferPairingUseCase(
      db,
      loadSchedule: schedule,
      clock: clock,
      newId: () => 'p${nextId++}',
    );
    bulk = BulkEditUseCase(
      db,
      clock: clock,
      newId: () => 'b${nextId++}',
      loadSchedule: schedule,
    );
    actions = BulkActions(
      bulk: bulk,
      pairing: pairing,
      refunds: RefundMatching(
        db,
        loadSchedule: schedule,
        clock: clock,
        newId: () => 'r${nextId++}',
      ),
    );
    final r = await pairing.recordExchange(
      fromAccountId: 'usd',
      sent: Money(usd, 60000),
      toAccountId: 'egp',
      received: Money(egp, 2970000),
      occurredAt: DateTime.utc(2026, 10, 26, 10),
      tzOffsetMin: 120,
    );
    pairId = r.pairId!;
    final legs = await db
        .customSelect(
          'SELECT id, direction FROM transactions WHERE transfer_pair_id = ?1',
          variables: [Variable.withString(pairId)],
        )
        .get();
    outId = legs
        .firstWhere((l) => l.read<String>('direction') == 'transfer_out')
        .read<String>('id');
    inId = legs
        .firstWhere((l) => l.read<String>('direction') == 'transfer_in')
        .read<String>('id');
  });

  tearDown(() => edb.close());

  for (final which in ['out', 'in', 'both']) {
    test('T-286 FU-384: bulk Set category / Set account on an exchange '
        '($which leg picked, with an ordinary row) changes nothing', () async {
      final picked = switch (which) {
        'out' => {outId, 'food'},
        'in' => {inId, 'food'},
        _ => {outId, inId, 'food'},
      };
      await CategoriesDao(db).upsertSystem(
        code: 'food',
        nameAr: 'أكل',
        nameEn: 'Food',
        icon: 'i',
        color: '#0F7A55',
        bucket: 'needs',
        sort: 1,
      );
      final before = {
        for (final id in [outId, inId, 'food']) id: await row(id),
      };
      await expectLater(
        actions.setCategory(picked, 'sys:food'),
        throwsA(
          isA<BulkEditException>().having(
            (e) => e.code,
            'code',
            BulkEditException.exchange,
          ),
        ),
      );
      await expectLater(
        actions.setAccount(picked, 'usd'),
        throwsA(
          isA<BulkEditException>().having(
            (e) => e.code,
            'code',
            BulkEditException.paired,
          ),
        ),
      );
      for (final id in before.keys) {
        expect(await row(id), before[id], reason: id);
      }
      expect(await pairs(), 1);
    });

    test('delete exchange ($which leg picked): both legs and the pair go in '
        'one batch; Undo puts all back; totals identical', () async {
      final before = await snapshot();
      expect(before['EGP']![2], 2970000, reason: 'exchanged in');
      expect(before['USD']![3], 60000, reason: 'exchanged out');

      final picked = switch (which) {
        'out' => {outId},
        'in' => {inId},
        _ => {outId, inId},
      };
      final res = await actions.delete(picked);
      expect(res.changed, 2);
      expect(res.ids, {outId, inId});
      expect((await row(outId)).deletedAt, isNotNull);
      expect((await row(inId)).deletedAt, isNotNull);
      expect(await pairs(), 0);
      final deleted = await snapshot();
      expect(deleted['EGP'], [0, 50000, 0, 0, -50000]);
      expect(deleted['USD'], [100000, 0, 0, 0, 100000]);

      final undo = await actions.undo(res.batchId);
      expect(undo.restored, 2);
      expect(undo.skipped, 0);
      expect(await pairs(), 1);
      for (final id in [outId, inId]) {
        final r = await row(id);
        expect(r.deletedAt, isNull);
        expect(r.isInternal, 1);
        expect(r.transferPairId, pairId, reason: 'same pair id back');
      }
      final kind = await db
          .customSelect(
            'SELECT kind FROM transfer_pairs WHERE id = ?1',
            variables: [Variable.withString(pairId)],
          )
          .getSingle();
      expect(kind.read<String>('kind'), 'cross_currency');
      expect(await snapshot(), before);
    });
  }

  for (final goneIsOut in [true, false]) {
    test('a rule-driven delete of the ${goneIsOut ? 'out' : 'in'} leg never '
        'frees the other into income or spending (it stays internal; '
        'nothing else is deleted)', () async {
      final gone = goneIsOut ? outId : inId;
      final kept = goneIsOut ? inId : outId;
      // Ignore rules / capture controls: a plain delete, then the hook.
      await bulk.apply({gone}, const DeleteTransactions());
      await pairing.onRemoved(gone);
      final k = await row(kept);
      expect(k.deletedAt, isNull, reason: 'never deleted without a tap');
      expect(k.isInternal, 1);
      expect(await pairs(), 0);
      final t = await snapshot();
      expect(t['EGP']![0], 0, reason: 'no EGP income from a freed leg');
      expect(t['EGP']![1], 50000);
      expect(t['USD']![1], 0, reason: 'no USD spending from a freed leg');
      expect(t['USD']![0], 100000);
    });
  }

  test('the heal in onPersisted keeps an exchange survivor internal', () async {
    // A crash between the soft delete and its hook: the pair still points
    // at a deleted leg.
    await TransactionsDao(db).softDelete(outId, at: nowMs);
    await pairing.onPersisted(inId);
    final i = await row(inId);
    expect(i.isInternal, 1);
    expect(i.transferPairId, isNull);
    expect(await pairs(), 0);
    final t = await snapshot();
    expect(t['EGP']![0], 0);
  });

  test('a single-leg ordinary transfer still frees its other leg', () async {
    // Unchanged behaviour outside exchanges (FU-127).
    await TransactionsDao(db).insert(
      txn('to', accountId: 'egp', direction: 'transfer_out', amountMinor: 1000),
    );
    await TransactionsDao(db).insert(
      txn('ti', accountId: 'usd', direction: 'transfer_in', amountMinor: 1000),
    );
    await db.customUpdate(
      'INSERT INTO transfer_pairs (id, out_txn_id, in_txn_id, kind, '
      "created_at) VALUES ('m', 'to', 'ti', 'manual', 1)",
    );
    await db.customUpdate(
      "UPDATE transactions SET transfer_pair_id = 'm', is_internal = 1 "
      "WHERE id IN ('to', 'ti')",
    );
    await actions.delete({'to'});
    final ti = await row('ti');
    expect(ti.deletedAt, isNull);
    expect(ti.isInternal, 0);
  });
}
