// T-091: splits and reimbursements. Acceptance criteria are named in the
// test titles. All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/transactions/application/reimbursements.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late Reimbursements uc;
  late DomainEventBus bus;
  late List<DomainEvent> seen;
  var nextId = 0;
  var clock = t0;

  Future<void> add(
    String id, {
    String direction = 'expense',
    int minor = 120000,
    int at = 0,
    String account = 'acc1',
    String currency = 'EGP',
    String status = 'posted',
    int internal = 0,
  }) => TransactionsDao(db).insert(
    txn(
      id,
      accountId: account,
      direction: direction,
      amountMinor: minor,
      currency: currency,
      occurredAt: t0 + at,
    ).copyWith(status: Value(status), isInternal: Value(internal)),
  );

  Future<int> scalar(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('s');

  // domain-algorithms §5: net spend and income from live rows and links.
  Future<int> netSpend() => scalar(
    'SELECT coalesce(sum(e.amount_minor), 0) - coalesce((SELECT '
    'sum(l.amount_minor) FROM offset_links l '
    'JOIN transactions e2 ON e2.id = l.expense_txn_id '
    'JOIN transactions s ON s.id = l.source_txn_id '
    'WHERE e2.deleted_at IS NULL AND s.deleted_at IS NULL), 0) AS s '
    "FROM transactions e WHERE e.deleted_at IS NULL AND e.direction = 'expense'",
  );
  Future<int> income() => scalar(
    'SELECT coalesce(sum(r.amount_minor), 0) - coalesce((SELECT '
    "sum(l.amount_minor) FROM offset_links l WHERE l.kind = 'reimbursement'"
    '), 0) AS s FROM transactions r WHERE r.deleted_at IS NULL '
    "AND r.is_internal = 0 AND r.direction IN ('income', 'transfer_in')",
  );

  setUp(() async {
    nextId = 0;
    clock = t0;
    seen = [];
    bus = DomainEventBus();
    bus.events.listen(seen.add);
    edb = await EncryptedDb.open();
    db = edb.db;
    final accounts = AccountsDao(db);
    await accounts.insert(account('acc1'));
    await accounts.insert(account('acc2', last4: '2222'));
    uc = Reimbursements(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
      newId: () => 'p${nextId++}',
      events: bus,
    );
  });

  tearDown(() async {
    await bus.dispose();
    await edb.close();
  });

  group('AC1 1,200 bill + 400 + 400 -> net 400', () {
    test('two friends repay one expense', () async {
      await add('bill');
      await add('ahmed', direction: 'transfer_in', minor: 40000, at: day);
      await add('karim', direction: 'transfer_in', minor: 40000, at: 2 * day);
      final a = await uc.assign('ahmed', [
        const AssignRequest(expenseId: 'bill', amountMinor: 40000),
      ]);
      clock += 1000;
      final b = await uc.assign('karim', [
        const AssignRequest(expenseId: 'bill', amountMinor: 40000),
      ]);
      expect(a.plan.grants.single.granted.minor, 40000);
      expect(b.plan.grants.single.granted.minor, 40000);
      expect(await netSpend(), 40000);
      final links = await OffsetLinksDao(db).forExpense('bill');
      expect(links.map((l) => l.kind), ['reimbursement', 'reimbursement']);
    });
  });

  group('AC2 reimbursement is excluded from income', () {
    test('assigned money leaves income; unassign brings it back', () async {
      await add('bill');
      await add('in1', direction: 'transfer_in', minor: 40000);
      expect(await income(), 40000);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'bill', amountMinor: 40000),
      ]);
      expect(await income(), 0);
      expect(await netSpend(), 80000);
      await uc.unassign(r.linkIds.single);
      expect(await income(), 40000);
      expect(await netSpend(), 120000);
      expect(await OffsetLinksDao(db).forExpense('bill'), isEmpty);
    });

    test('part of a transfer assigned: the rest stays income', () async {
      await add('bill');
      await add('in1', direction: 'income', minor: 50000);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'bill', amountMinor: 30000),
      ]);
      expect(r.plan.incomeRemainder.minor, 20000);
      expect(await income(), 20000);
    });
  });

  group('FR-XFR-07 / EC-39 one transfer across several expenses', () {
    test('split over two, capped by the transfer', () async {
      await add('e1', minor: 30000);
      await add('e2', minor: 40000, at: day);
      await add('in1', direction: 'transfer_in', minor: 50000, at: 2 * day);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'e1', amountMinor: 30000),
        const AssignRequest(expenseId: 'e2', amountMinor: 30000),
      ]);
      expect(r.plan.grants.map((g) => g.granted.minor), [30000, 20000]);
      expect(r.plan.grants.last.clamped, isTrue);
      expect(await OffsetLinksDao(db).linkedFromSource('in1'), 50000);
      expect(await income(), 0);
      expect(await netSpend(), 70000 - 50000);
    });

    test('second assign cannot take more than the transfer had', () async {
      await add('e1', minor: 30000);
      await add('e2', minor: 30000);
      await add('in1', direction: 'transfer_in', minor: 30000);
      await uc.assign('in1', [
        const AssignRequest(expenseId: 'e1', amountMinor: 30000),
      ]);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'e2', amountMinor: 30000),
      ]);
      expect(r.plan.grants, isEmpty);
      expect(r.plan.rejected.single.reason, RejectReason.noRoom);
      expect(await OffsetLinksDao(db).linkedFromSource('in1'), 30000);
    });

    test('two actors at once never over-allocate a transfer', () async {
      await add('e1', minor: 30000);
      await add('e2', minor: 30000);
      await add('in1', direction: 'transfer_in', minor: 30000);
      await Future.wait([
        uc.assign('in1', [
          const AssignRequest(expenseId: 'e1', amountMinor: 30000),
        ]),
        uc.assign('in1', [
          const AssignRequest(expenseId: 'e2', amountMinor: 30000),
        ]),
      ]);
      expect(await OffsetLinksDao(db).linkedFromSource('in1'), 30000);
      expect(await income(), 0);
    });
  });

  group('BR-XFR-06 caps; excess stays income', () {
    test('transfer larger than the expense', () async {
      await add('e1', minor: 30000);
      await add('in1', direction: 'transfer_in', minor: 50000);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'e1', amountMinor: 50000),
      ]);
      expect(r.plan.grants.single.granted.minor, 30000);
      expect(r.plan.incomeRemainder.minor, 20000);
      expect(await income(), 20000);
      expect(await netSpend(), 0);
    });

    test('expense already fully offset by a refund takes nothing', () async {
      await add('e1', minor: 30000);
      await add('rf', direction: 'refund', minor: 30000);
      await db.customStatement(
        'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
        "amount_minor, created_at) VALUES ('x', 'refund', 'e1', 'rf', 30000, 1)",
      );
      await add('in1', direction: 'transfer_in', minor: 100);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'e1', amountMinor: 100),
      ]);
      expect(r.plan.grants, isEmpty);
      expect(await income(), 100);
    });
  });

  group('FR-XFR-04/05 participants and EC-37', () {
    test('shares, unsettled per person, repayment attributed', () async {
      await add('bill');
      final ali = await uc.addParticipant('bill', ' Ali ', 40000);
      final omar = await uc.addParticipant('bill', 'Omar', 40000);
      await add('in1', direction: 'transfer_in', minor: 25000);
      await uc.assign('in1', [
        AssignRequest(
          expenseId: 'bill',
          amountMinor: 25000,
          participantId: ali,
        ),
      ]);
      final u = await uc.unsettled('bill');
      expect(u[ali]!.minor, 15000);
      expect(u[omar]!.minor, 40000);
    });

    test('a friend paying more than their share: excess is income', () async {
      await add('bill');
      final ali = await uc.addParticipant('bill', 'Ali', 40000);
      await add('in1', direction: 'transfer_in', minor: 60000);
      final r = await uc.assign('in1', [
        AssignRequest(
          expenseId: 'bill',
          amountMinor: 60000,
          participantId: ali,
        ),
      ]);
      expect(r.plan.grants.single.granted.minor, 40000);
      expect(await income(), 20000);
      expect((await uc.unsettled('bill'))[ali]!.minor, 0);
    });

    test('Σ shares above the expense is refused', () async {
      await add('bill', minor: 1000);
      await uc.addParticipant('bill', 'A', 600);
      await expectLater(
        uc.addParticipant('bill', 'B', 401),
        throwsA(
          isA<ReimbursementException>().having(
            (e) => e.code,
            'code',
            ReimbursementException.sharesExceed,
          ),
        ),
      );
      final b = await uc.addParticipant('bill', 'B', 400);
      await expectLater(
        uc.updateShare(b, 401),
        throwsA(isA<ReimbursementException>()),
      );
      await uc.updateShare(b, 100);
    });

    test('bad name or negative share is invalid', () async {
      await add('bill');
      for (final f in [
        () => uc.addParticipant('bill', '   ', 1),
        () => uc.addParticipant('bill', 'x' * 65, 1),
        () => uc.addParticipant('bill', 'A', -1),
      ]) {
        await expectLater(f(), throwsA(isA<ReimbursementException>()));
      }
    });

    test('removing a participant keeps the link amount', () async {
      await add('bill');
      final ali = await uc.addParticipant('bill', 'Ali', 40000);
      await add('in1', direction: 'transfer_in', minor: 10000);
      await uc.assign('in1', [
        AssignRequest(
          expenseId: 'bill',
          amountMinor: 10000,
          participantId: ali,
        ),
      ]);
      await uc.removeParticipant(ali);
      final link = (await OffsetLinksDao(db).forExpense('bill')).single;
      expect(link.participantId, isNull);
      expect(link.amountMinor, 10000);
    });
  });

  group('eligibility and validation', () {
    test(
      'only live posted non-internal incoming money can be assigned',
      () async {
        await add('e1');
        await add('exp2', minor: 100);
        await add(
          'pend',
          direction: 'transfer_in',
          minor: 100,
          status: 'pending',
        );
        await add(
          'internal',
          direction: 'transfer_in',
          minor: 100,
          internal: 1,
        );
        await add('gone', direction: 'income', minor: 100);
        await TransactionsDao(db).softDelete('gone', at: t0);
        for (final id in ['pend', 'internal', 'gone', 'exp2', 'missing']) {
          await expectLater(
            uc.assign(id, [
              const AssignRequest(expenseId: 'e1', amountMinor: 1),
            ]),
            throwsA(isA<ReimbursementException>()),
            reason: id,
          );
        }
        expect(await OffsetLinksDao(db).forExpense('e1'), isEmpty);
      },
    );

    test('other-currency expense is rejected, never converted', () async {
      await add('usd', currency: 'USD', minor: 5000);
      await add('in1', direction: 'transfer_in', minor: 5000);
      final r = await uc.assign('in1', [
        const AssignRequest(expenseId: 'usd', amountMinor: 5000),
      ]);
      expect(r.plan.grants, isEmpty);
      expect(r.plan.rejected.single.reason, RejectReason.unknownExpense);
      expect(await income(), 5000);
    });

    test('same pair twice is refused; empty and zero are invalid', () async {
      await add('e1');
      await add('in1', direction: 'transfer_in', minor: 1000);
      await uc.assign('in1', [
        const AssignRequest(expenseId: 'e1', amountMinor: 100),
      ]);
      await expectLater(
        uc.assign('in1', [
          const AssignRequest(expenseId: 'e1', amountMinor: 100),
        ]),
        throwsA(
          isA<ReimbursementException>().having(
            (e) => e.code,
            'code',
            ReimbursementException.alreadyLinked,
          ),
        ),
      );
      await expectLater(
        uc.assign('in1', []),
        throwsA(isA<ReimbursementException>()),
      );
      await expectLater(
        uc.assign('in1', [
          const AssignRequest(expenseId: 'e1', amountMinor: 0),
        ]),
        throwsA(isA<ReimbursementException>()),
      );
    });

    test('refund links cannot be unassigned here; unknown link', () async {
      await add('e1', minor: 1000);
      await add('rf', direction: 'refund', minor: 100);
      await db.customStatement(
        'INSERT INTO offset_links (id, kind, expense_txn_id, source_txn_id, '
        "amount_minor, created_at) VALUES ('x', 'refund', 'e1', 'rf', 100, 1)",
      );
      await expectLater(
        uc.unassign('x'),
        throwsA(isA<ReimbursementException>()),
      );
      await expectLater(
        uc.unassign('nope'),
        throwsA(isA<ReimbursementException>()),
      );
      expect(await OffsetLinksDao(db).forExpense('e1'), hasLength(1));
    });
  });

  group('BR-XFR-07 later-cycle restatement', () {
    test(
      'event names the original expense cycle and the current one',
      () async {
        await add('bill', at: -40 * day);
        await add('in1', direction: 'transfer_in', minor: 40000, at: 0);
        seen.clear();
        final r = await uc.assign('in1', [
          const AssignRequest(expenseId: 'bill', amountMinor: 40000),
        ]);
        await Future<void>.delayed(Duration.zero);
        final ev = r.event!;
        final s = PaydaySchedule.single(1);
        expect(ev.cycleKeys, {
          s.cycleOnMs(t0 - 40 * day, 120).key,
          s.cycleOnMs(t0, 120).key,
        });
        expect(ev.cycleKeys.length, 2);
        expect(seen.whereType<TransactionsChanged>(), hasLength(1));
      },
    );
  });

  group('EC-40 expense edit repairs the links', () {
    test(
      'without repair the shrink is refused; with it newest links go',
      () async {
        await add('bill');
        await add('a', direction: 'transfer_in', minor: 40000);
        await add('b', direction: 'transfer_in', minor: 40000);
        await uc.assign('a', [
          const AssignRequest(expenseId: 'bill', amountMinor: 40000),
        ]);
        clock += 1000;
        final second = await uc.assign('b', [
          const AssignRequest(expenseId: 'bill', amountMinor: 40000),
        ]);
        final dao = TransactionsDao(db);
        await expectLater(
          dao.updateById(
            'bill',
            const TransactionsCompanion(amountMinor: Value(60000)),
          ),
          throwsA(anything),
        );
        final r = await db.transaction(() async {
          final r = await uc.repairForNewAmount('bill', 60000);
          await dao.updateById(
            'bill',
            const TransactionsCompanion(amountMinor: Value(60000)),
          );
          return r;
        });
        expect(r.removedLinkIds, [second.linkIds.single]);
        expect(r.event, isNotNull);
        expect(await OffsetLinksDao(db).linkedToExpense('bill'), 40000);
        // The freed transfer is income again.
        expect(await income(), 40000);
      },
    );

    test(
      'shrinking to zero removes everything; nothing exceeds is a no-op',
      () async {
        await add('bill');
        await add('a', direction: 'transfer_in', minor: 40000);
        await uc.assign('a', [
          const AssignRequest(expenseId: 'bill', amountMinor: 40000),
        ]);
        expect(
          (await uc.repairForNewAmount('bill', 120000)).removedLinkIds,
          isEmpty,
        );
        expect(
          (await uc.repairForNewAmount('bill', 0)).removedLinkIds,
          hasLength(1),
        );
      },
    );

    test('editing the incoming transfer down also repairs', () async {
      await add('e1');
      await add('e2');
      await add('a', direction: 'transfer_in', minor: 50000);
      await uc.assign('a', [
        const AssignRequest(expenseId: 'e1', amountMinor: 30000),
        const AssignRequest(expenseId: 'e2', amountMinor: 20000),
      ]);
      final r = await uc.repairForNewAmount('a', 30000);
      expect(r.removedLinkIds, hasLength(1));
      expect(
        await OffsetLinksDao(db).linkedFromSource('a'),
        lessThanOrEqualTo(30000),
      );
    });

    test(
      'shares above the new amount are flagged, not silently changed',
      () async {
        await add('bill', minor: 1000);
        await uc.addParticipant('bill', 'A', 800);
        final r = await uc.repairForNewAmount('bill', 500);
        expect(r.sharesExceedAmount, isTrue);
        expect((await uc.unsettled('bill')).values.single.minor, 800);
      },
    );
  });
}
