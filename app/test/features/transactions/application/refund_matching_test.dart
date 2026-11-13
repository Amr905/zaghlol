// T-090: refund matching and offset links. Acceptance criteria are named in
// the test titles. All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/bulk_edit.dart';
import 'package:zaghlol/features/transactions/application/refund_matching.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late RefundMatching uc;
  late DomainEventBus bus;
  late List<DomainEvent> seen;
  var nextId = 0;

  RefundMatching make() => RefundMatching(
    db,
    loadSchedule: () async => PaydaySchedule.single(1),
    clock: () => DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
    newId: () => 'p${nextId++}',
    events: bus,
  );

  Future<void> add(
    String id, {
    required String direction,
    int minor = 10000,
    int at = 0,
    String merchant = 'acme',
    String account = 'acc1',
    String currency = 'EGP',
    String status = 'posted',
  }) => TransactionsDao(db).insert(
    txn(
      id,
      accountId: account,
      direction: direction,
      amountMinor: minor,
      currency: currency,
      merchantNorm: merchant,
      occurredAt: t0 + at,
    ).copyWith(status: Value(status)),
  );

  Future<int> scalar(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('s');

  // Net spend and income of live, non-internal rows (domain-algorithms §5).
  Future<int> netSpend() => scalar(
    'SELECT coalesce(sum(e.amount_minor), 0) - coalesce((SELECT sum(l.amount_minor) '
    'FROM offset_links l JOIN transactions e2 ON e2.id = l.expense_txn_id '
    'JOIN transactions s ON s.id = l.source_txn_id '
    'WHERE e2.deleted_at IS NULL AND s.deleted_at IS NULL), 0) AS s '
    "FROM transactions e WHERE e.deleted_at IS NULL AND e.direction = 'expense'",
  );
  Future<int> income() => scalar(
    'SELECT coalesce(sum(r.amount_minor), 0) - coalesce((SELECT sum(l.amount_minor) '
    'FROM offset_links l JOIN transactions e2 ON e2.id = l.expense_txn_id '
    'JOIN transactions s ON s.id = l.source_txn_id '
    'WHERE e2.deleted_at IS NULL AND s.deleted_at IS NULL), 0) AS s '
    "FROM transactions r WHERE r.deleted_at IS NULL AND r.direction = 'refund'",
  );
  Future<int> linkCount() => scalar('SELECT count(*) AS s FROM offset_links');

  setUp(() async {
    nextId = 0;
    seen = [];
    bus = DomainEventBus();
    bus.events.listen(seen.add);
    edb = await EncryptedDb.open();
    db = edb.db;
    final accounts = AccountsDao(db);
    await accounts.insert(account('acc1'));
    await accounts.insert(account('acc2', last4: '2222'));
    await accounts.insert(account('kwd', last4: '3333', currency: 'KWD'));
    uc = make();
  });

  tearDown(() async {
    await bus.dispose();
    await edb.close();
  });

  group('AC1 partial refund reduces net spend', () {
    test('100 spent, 30 refunded: net 70, no income', () async {
      await add('e', direction: 'expense', at: -day);
      await add('r', direction: 'refund', minor: 3000);
      final r = await uc.onPersisted('r');
      expect(r.status, RefundMatchStatus.linked);
      expect(r.linkedMinor, 3000);
      expect(r.incomeRemainderMinor, 0);
      expect(await netSpend(), 7000);
      expect(await income(), 0);
      final link = (await OffsetLinksDao(db).forExpense('e')).single;
      expect(link.kind, 'refund');
      expect(link.sourceTxnId, 'r');
    });

    test('two partial refunds stack; a third cannot over-offset', () async {
      await add('e', direction: 'expense', at: -day);
      await add('r1', direction: 'refund', minor: 6000);
      await add('r2', direction: 'refund', minor: 4000, at: 1000);
      await add('r3', direction: 'refund', minor: 500, at: 2000);
      await uc.onPersisted('r1');
      await uc.onPersisted('r2');
      expect(await netSpend(), 0);
      expect((await uc.onPersisted('r3')).status, RefundMatchStatus.unmatched);
      expect(await OffsetLinksDao(db).linkedToExpense('e'), 10000);
      expect(await income(), 500);
    });
  });

  group('AC2 refund larger than the expense: remainder is income', () {
    test('120 refund on a 100 expense: net 0, income 20', () async {
      await add('e', direction: 'expense', at: -day);
      await add('r', direction: 'refund', minor: 12000);
      final r = await uc.onPersisted('r');
      expect(r.linkedMinor, 10000);
      expect(r.incomeRemainderMinor, 2000);
      expect(await netSpend(), 0);
      expect(await income(), 2000);
    });

    test('three-decimal currency keeps exact minor units', () async {
      await add(
        'e',
        direction: 'expense',
        minor: 1000,
        account: 'kwd',
        currency: 'KWD',
        at: -day,
      );
      await add(
        'r',
        direction: 'refund',
        minor: 1250,
        account: 'kwd',
        currency: 'KWD',
      );
      final r = await uc.onPersisted('r');
      expect(r.linkedMinor, 1000);
      expect(r.incomeRemainderMinor, 250);
    });
  });

  group('matching rules', () {
    test('no original: refund stays income, nothing linked', () async {
      await add('r', direction: 'refund', minor: 3000);
      expect((await uc.onPersisted('r')).status, RefundMatchStatus.unmatched);
      expect(await linkCount(), 0);
      expect(await income(), 3000);
    });

    test(
      'other merchant / account / currency / 61 days / pending refund',
      () async {
        await add('e1', direction: 'expense', merchant: 'zed', at: -day);
        await add('e2', direction: 'expense', account: 'acc2', at: -day);
        await add(
          'e3',
          direction: 'expense',
          account: 'kwd',
          currency: 'KWD',
          at: -day,
        );
        await add('e4', direction: 'expense', at: -61 * day);
        await add('r', direction: 'refund', minor: 3000);
        expect((await uc.onPersisted('r')).status, RefundMatchStatus.unmatched);
        await add('e5', direction: 'expense', at: -60 * day);
        await add('r2', direction: 'refund', minor: 3000, status: 'pending');
        expect((await uc.onPersisted('r2')).status, RefundMatchStatus.skipped);
        expect(await linkCount(), 0);
      },
    );

    test('most recent fitting expense wins', () async {
      await add('old', direction: 'expense', at: -10 * day);
      await add('new', direction: 'expense', at: -2 * day);
      await add('r', direction: 'refund', minor: 3000);
      expect((await uc.onPersisted('r')).expenseId, 'new');
    });

    test('same-instant originals: review item, never linked', () async {
      await add('a', direction: 'expense', at: -day);
      await add('b', direction: 'expense', at: -day);
      await add('r', direction: 'refund', minor: 3000);
      expect((await uc.onPersisted('r')).status, RefundMatchStatus.ambiguous);
      expect((await uc.onPersisted('r')).status, RefundMatchStatus.ambiguous);
      expect(await linkCount(), 0);
      final open = await db
          .customSelect(
            'SELECT payload FROM review_items WHERE resolved_at IS NULL',
          )
          .get();
      expect(open, hasLength(1));
    });

    test('idempotent: second run links nothing more', () async {
      await add('e', direction: 'expense', at: -day);
      await add('r', direction: 'refund', minor: 3000);
      await uc.onPersisted('r');
      expect((await uc.onPersisted('r')).status, RefundMatchStatus.skipped);
      expect(await linkCount(), 1);
    });

    test('a fully offset expense is skipped for the next refund', () async {
      await add('e1', direction: 'expense', at: -2 * day, minor: 5000);
      await add('e2', direction: 'expense', at: -day, minor: 5000);
      await add('r1', direction: 'refund', minor: 5000);
      await add('r2', direction: 'refund', minor: 5000, at: 1000);
      expect((await uc.onPersisted('r1')).expenseId, 'e2');
      expect((await uc.onPersisted('r2')).expenseId, 'e1');
    });

    test('non-refund rows are skipped', () async {
      await add('e', direction: 'expense');
      expect((await uc.onPersisted('e')).status, RefundMatchStatus.skipped);
      expect(
        (await uc.onPersisted('missing')).status,
        RefundMatchStatus.skipped,
      );
    });
  });

  group('events and removal (FU-110, FU-127)', () {
    test('event names the linked expense cycle and account', () async {
      await add('e', direction: 'expense', at: -40 * day, account: 'acc1');
      await add('r', direction: 'refund', minor: 3000);
      await uc.onPersisted('r');
      await settle();
      final e = seen.whereType<TransactionsChanged>().single;
      expect(e.cycleKeys, {'2026-11-01', '2026-09-01'});
      expect(e.accountIds, {'acc1'});
    });

    test(
      'deleting the refund frees the link and announces both cycles',
      () async {
        await add('e', direction: 'expense', at: -40 * day);
        await add('r', direction: 'refund', minor: 3000);
        await uc.onPersisted('r');
        await settle();
        seen.clear();
        await TransactionsDao(db).softDelete('r', at: t0);
        final res = await uc.onRemoved('r');
        expect(res, isNotNull);
        expect(await linkCount(), 0);
        expect(await netSpend(), 10000);
        expect(res!.event.cycleKeys, {'2026-11-01', '2026-09-01'});
        await settle();
        expect(seen.whereType<TransactionsChanged>(), hasLength(1));
        expect(await uc.onRemoved('r'), isNull);
      },
    );

    test('deleting the expense frees the refund, which re-matches', () async {
      await add('e1', direction: 'expense', at: -3 * day);
      await add('e2', direction: 'expense', at: -day);
      await add('r', direction: 'refund', minor: 3000);
      await uc.onPersisted('r');
      await TransactionsDao(db).softDelete('e2', at: t0);
      final res = await uc.onRemoved('e2');
      expect(res!.rematched.single.expenseId, 'e1');
      expect(await OffsetLinksDao(db).linkedToExpense('e1'), 3000);
    });

    test(
      'deleting the expense with no other original: refund is income',
      () async {
        await add('e', direction: 'expense', at: -day);
        await add('r', direction: 'refund', minor: 3000);
        await uc.onPersisted('r');
        await TransactionsDao(db).softDelete('e', at: t0);
        final res = await uc.onRemoved('e');
        expect(res!.rematched.single.status, RefundMatchStatus.unmatched);
        expect(await income(), 3000);
      },
    );

    test(
      'unlink frees the link and the refund is not auto-linked again',
      () async {
        await add('e', direction: 'expense', at: -day);
        await add('r', direction: 'refund', minor: 3000);
        final linked = await uc.onPersisted('r');
        await uc.unlink(linked.linkId!);
        expect(await linkCount(), 0);
        expect((await uc.onPersisted('r')).status, RefundMatchStatus.skipped);
        expect(await linkCount(), 0);
        expect(
          await codeOf(uc.unlink(linked.linkId!)),
          RefundMatchingException.notFound,
        );
      },
    );

    test('bulk-edit delete event still includes linked cycles', () async {
      await add('e', direction: 'expense', at: -40 * day);
      await add('r', direction: 'refund', minor: 3000);
      await uc.onPersisted('r');
      await settle();
      seen.clear();
      final bulk = BulkEditUseCase(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        clock: () => DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
        newId: () => 'b${nextId++}',
        events: bus,
      );
      final r = await bulk.apply(['r'], const DeleteTransactions());
      expect(r.event.cycleKeys, {'2026-11-01', '2026-09-01'});
    });
  });
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

Future<String?> codeOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on RefundMatchingException catch (e) {
    return e.code;
  }
}
