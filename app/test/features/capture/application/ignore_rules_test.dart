// T-078: ignore rules on an encrypted database. Acceptance criteria are
// named in the test titles. All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/application/guard_config_writer.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late IgnoreRulesService svc;
  late TransferPairingUseCase pairing;
  late BulkEditUseCase bulk;
  var ruleChanged = 0;
  var removedCalls = <String>[];
  var nextId = 0;

  Future<void> add(
    String id,
    String account, {
    String source = 'sms',
    String direction = 'expense',
    int at = 0,
  }) => TransactionsDao(db).insert(
    txn(
      id,
      accountId: account,
      direction: direction,
      occurredAt: t0 + at,
    ).copyWith(source: Value(source)),
  );

  Future<Set<String>> live() async => {
    for (final r in await (db.select(
      db.transactions,
    )..where((t) => t.deletedAt.isNull())).get())
      r.id,
  };

  setUp(() async {
    ruleChanged = 0;
    removedCalls = [];
    nextId = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    final accounts = AccountsDao(db);
    await accounts.insert(
      account('nbe4567', institution: 'NBE', last4: '4567'),
    );
    await accounts.insert(
      account('nbe1111', institution: 'NBE', last4: '1111'),
    );
    await accounts.insert(account('cib', institution: 'CIB', last4: '2222'));
    final clock = t0 + 1000;
    pairing = TransferPairingUseCase(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
      newId: () => 'p${nextId++}',
    );
    bulk = BulkEditUseCase(
      db,
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
      newId: () => 'u${nextId++}',
    );
    svc = IgnoreRulesService(
      db,
      bulkEdit: bulk,
      onRemoved: (id) async {
        removedCalls.add(id);
        await pairing.onRemoved(id);
      },
      onRuleChanged: () async {
        ruleChanged++;
        return const GuardWriteResult(
          GuardWriteStatus(GuardWriteState.written),
        );
      },
      rescanAvailable: true,
      nowMs: () => t0,
      newId: () => 'r${nextId++}',
    );
    await add('a1', 'nbe4567');
    await add('a2', 'nbe4567', source: 'notification');
    await add('a3', 'nbe1111');
    await add('a4', 'cib');
  });

  tearDown(() => edb.close());

  test('rule for NBE *4567 SMS stores a rule, ignores SMS only, '
      'notifications still captured (AC1)', () async {
    final r = await svc.add(
      const IgnoreTarget(
        institutionCode: 'nbe',
        last4: '4567',
        channel: IgnoreChannel.sms,
      ),
    );
    expect(r.created, isTrue);
    final dao = CaptureControlsDao(db);
    expect(
      await dao.isIgnored(
        institutionCode: 'nbe',
        last4: '4567',
        channel: IgnoreChannel.sms,
      ),
      isTrue,
    );
    expect(
      await dao.isIgnored(
        institutionCode: 'nbe',
        last4: '4567',
        channel: IgnoreChannel.notification,
      ),
      isFalse,
    );
    expect(
      await dao.isIgnored(
        institutionCode: 'nbe',
        last4: '1111',
        channel: IgnoreChannel.sms,
      ),
      isFalse,
    );
    expect(ruleChanged, 1);
  });

  test('keep is the default: no transaction changes (AC keep)', () async {
    final r = await svc.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
    );
    expect(r.deleted, 0);
    expect(await live(), {'a1', 'a2', 'a3', 'a4'});
  });

  test('preview matches only the rule channel and card', () async {
    final p = await svc.previewMatches(
      const IgnoreTarget(
        institutionCode: 'nbe',
        last4: '4567',
        channel: IgnoreChannel.sms,
      ),
    );
    expect(p.ids, ['a1']);
    final inst = await svc.previewMatches(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
    );
    expect(inst.ids.toSet(), {'a1', 'a3'});
  });

  test('delete removes only confirmed ids that still match', () async {
    const target = IgnoreTarget(
      institutionCode: 'nbe',
      channel: IgnoreChannel.sms,
    );
    final preview = await svc.previewMatches(target);
    // A row arrives after the user saw the preview.
    await add('late', 'nbe1111', at: 5);
    // An id the rule does not cover is smuggled in the confirmation.
    final r = await svc.add(
      target,
      existing: DeleteExisting(confirmedIds: {...preview.ids, 'a4'}),
    );
    expect(r.deleted, 2);
    expect(r.undoBatchIds, hasLength(1));
    expect(await live(), {'a2', 'a4', 'late'});
    // Soft delete: restorable by Undo.
    await bulk.undo(r.undoBatchIds.single);
    expect(await live(), {'a1', 'a2', 'a3', 'a4', 'late'});
  });

  test('empty confirmation deletes nothing', () async {
    final r = await svc.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
      existing: const DeleteExisting(confirmedIds: {}),
    );
    expect(r.deleted, 0);
    expect(await live(), hasLength(4));
  });

  test('deleting a paired leg goes through onRemoved and frees the '
      'other leg (FU-127)', () async {
    await add('o', 'nbe1111', direction: 'transfer_out');
    await add('i', 'cib', direction: 'transfer_in', source: 'notification');
    final pr = await pairing.onPersisted('o');
    expect(pr.status, isNot(PairingStatus.skipped));
    final before = await db.customSelect('SELECT id FROM transfer_pairs').get();
    expect(before, hasLength(1));

    await svc.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
      existing: const DeleteExisting(confirmedIds: {'o'}),
    );
    expect(removedCalls, ['o']);
    expect(
      await db.customSelect('SELECT id FROM transfer_pairs').get(),
      isEmpty,
    );
    final other = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals('i'))).getSingle();
    expect(other.transferPairId, isNull);
    expect(other.deletedAt, isNull);
  });

  test('offset links are kept on delete and on un-ignore (EC-63)', () async {
    await add('refund', 'nbe1111', direction: 'refund');
    await OffsetLinksDao(db).insert(
      link(
        'l1',
        expense: 'a3',
        source: 'refund',
        amountMinor: 100,
        kind: 'refund',
      ),
    );
    final r = await svc.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
      existing: const DeleteExisting(confirmedIds: {'a3'}),
    );
    expect(r.deleted, 1);
    expect(
      await db.customSelect('SELECT id FROM offset_links').get(),
      hasLength(1),
    );
    await svc.remove(r.ruleId);
    expect(
      await db.customSelect('SELECT id FROM offset_links').get(),
      hasLength(1),
    );
  });

  test('duplicate add reports created=false and the existing id', () async {
    const t = IgnoreTarget(
      institutionCode: 'nbe',
      last4: '4567',
      channel: IgnoreChannel.sms,
    );
    final a = await svc.add(t);
    final b = await svc.add(t);
    expect(a.created, isTrue);
    expect(b.created, isFalse);
    expect(b.ruleId, a.ruleId);
    expect(await svc.rules(), hasLength(1));
  });

  test('before-seen card (no account) and Arabic-Indic last-4', () async {
    final r = await svc.add(
      const IgnoreTarget(
        institutionCode: 'qnb',
        last4: '٩٨٧٦',
        channel: IgnoreChannel.applePay,
      ),
    );
    expect(r.created, isTrue);
    final rule = (await svc.rules()).single;
    expect(rule.last4, '9876');
  });

  test('invalid targets are refused with a code and write nothing', () async {
    for (final t in const [
      IgnoreTarget(institutionCode: 'N', channel: IgnoreChannel.sms),
      IgnoreTarget(institutionCode: 'NBE', channel: IgnoreChannel.sms),
      IgnoreTarget(
        institutionCode: 'nbe',
        last4: '12345',
        channel: IgnoreChannel.sms,
      ),
      IgnoreTarget(institutionCode: 'nbe', last4: '12a4', channel: 'sms'),
      IgnoreTarget(institutionCode: 'nbe', channel: 'share'),
    ]) {
      await expectLater(
        svc.add(t),
        throwsA(
          isA<IgnoreRuleException>().having(
            (e) => e.code,
            'code',
            IgnoreRuleException.invalid,
          ),
        ),
      );
    }
    expect(await svc.rules(), isEmpty);
    expect(ruleChanged, 0);
  });

  test('un-ignore: removes the rule, rewrites config, offers re-scan for '
      'SMS only', () async {
    final sms = await svc.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
    );
    final notif = await svc.add(
      const IgnoreTarget(
        institutionCode: 'nbe',
        channel: IgnoreChannel.notification,
      ),
    );
    final n = ruleChanged;
    final r1 = await svc.remove(sms.ruleId);
    expect(r1.removed, isTrue);
    expect(r1.rescanOffer?.institutionCode, 'nbe');
    expect(ruleChanged, n + 1);
    final r2 = await svc.remove(notif.ruleId);
    expect(r2.rescanOffer, isNull);
    expect(await live(), hasLength(4));
    await expectLater(
      svc.remove(sms.ruleId),
      throwsA(isA<IgnoreRuleException>()),
    );
  });

  test('no re-scan offer when re-scan is unavailable (iOS)', () async {
    final s = IgnoreRulesService(
      db,
      bulkEdit: BulkEditUseCase(db),
      onRemoved: (_) async {},
      newId: () => 'x${nextId++}',
    );
    final a = await s.add(
      const IgnoreTarget(institutionCode: 'nbe', channel: IgnoreChannel.sms),
    );
    expect((await s.remove(a.ruleId)).rescanOffer, isNull);
  });
}
