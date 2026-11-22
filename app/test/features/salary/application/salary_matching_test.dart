// T-195 (D-71): the salary is counted once, whichever arrives first. Every
// order asserts the number of live income rows per currency and the real
// cycle totals. All data synthetic.

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/salary/application/salary_matching.dart';
import 'package:zaghlol/features/salary/application/salary_matching_hook.dart';
import 'package:zaghlol/features/salary/application/salary_service.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;
final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');
final CivilDate payday = CivilDate(2026, 11, 25);
const int tenK = 1000000; // 10,000.00 EGP in piasters

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late SalaryMatching matching;
  late SalaryService service;
  late DomainEventBus bus;
  late List<DomainEvent> seen;
  var nextId = 0;
  final nowMs = CivilDate(2026, 11, 25).epochDay * day + 14 * 3600000;

  final schedule = PaydaySchedule.single(25);

  SalaryMatching makeMatching() => SalaryMatching(
    db,
    loadSchedule: () async => schedule,
    clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
    events: bus,
  );

  /// A received credit (source sms) at local noon of [date] (+02:00).
  Future<String> sms(
    String id,
    int minor,
    CivilDate date, {
    Currency? currency,
    String? merchant,
    String direction = 'income',
    String source = 'sms',
  }) async {
    await TransactionsDao(db).insert(
      TransactionsCompanion.insert(
        id: id,
        accountId: 'acc1',
        source: source,
        direction: direction,
        amountMinor: minor,
        currency: (currency ?? egp).code,
        occurredAt: date.epochDay * day + 10 * 3600000,
        occurredTzOffsetMin: 120,
        merchantRaw: Value(merchant),
        categorySource: 'none',
        createdAt: t0,
        updatedAt: t0,
      ),
    );
    return id;
  }

  Future<SalaryMatchStatus> arrive(String id) => matching.onPersisted(id);

  Future<void> setPlan({int minor = tenK, Currency? c, String? account}) =>
      service.setPlan(
        SalaryPlan.tryCreate(
          amount: Money(c ?? egp, minor),
          day: 25,
          accountId: account,
        ),
      );

  /// Live income rows of [currency] (the thing totals sum).
  Future<List<int>> incomes(Currency currency) async => [
    for (final r
        in await db
            .customSelect(
              'SELECT amount_minor FROM transactions WHERE deleted_at IS NULL '
              "AND direction IN ('income', 'transfer_in') AND is_internal = 0 "
              'AND currency = ? ORDER BY occurred_at, id',
              variables: [Variable.withString(currency.code)],
              readsFrom: {db.transactions},
            )
            .get())
      r.read<int>('amount_minor'),
  ];

  /// What Home and budgets read: the live cycle totals.
  Future<int> cycleIncome(CivilDate date, Currency currency) async {
    final repo = CycleRepository(
      db,
      nowUtcMs: () => nowMs,
      zone: const FixedLocalZone(120),
    );
    final cycle = schedule.cycleOnMs(date.epochDay * day + 10 * 3600000, 120);
    final totals = await repo.computeLive(cycle);
    return totals[currency]?.income.minor ?? 0;
  }

  Future<String> manual({
    int minor = tenK,
    CivilDate? date,
    Currency? currency,
  }) async {
    final d = date ?? payday;
    final r = await service.recordManual(
      NewTransaction(
        accountId: 'acc1',
        direction: TxnDirection.income,
        amount: Money(currency ?? egp, minor),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          d.epochDay * day + 10 * 3600000,
          isUtc: true,
        ),
        occurredTzOffsetMin: 120,
      ),
    );
    return (r as SalaryRecorded).txnId;
  }

  Future<bool> deleted(String id) async =>
      (await TransactionsDao(db).byId(id))!.deletedAt != null;

  setUp(() async {
    nextId = 0;
    seen = [];
    bus = DomainEventBus();
    bus.events.listen(seen.add);
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    await AccountsDao(db).insert(
      account(
        'cash',
        kind: 'cash',
        institution: null,
        last4: null,
        defaultCash: true,
      ),
    );
    await CategoriesDao(db).upsertSystem(
      code: 'income',
      nameAr: 'دخل',
      nameEn: 'Income',
      icon: 'x',
      color: '#112233',
      bucket: 'income',
      sort: 1,
    );
    matching = makeMatching();
    service = SalaryService(
      db,
      DriftTransactionRepository(
        TransactionsDao(db),
        clock: () => DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
        newId: () => 'm${nextId++}',
      ),
      zone: const FixedLocalZone(120),
    );
  });

  tearDown(() async {
    await bus.dispose();
    await edb.close();
  });

  group('AC1: a salary with no SMS counts as income', () {
    test('expected item is in no total until confirmed', () async {
      await setPlan();
      final e = await service.expected(payday);
      expect(e?.payday, payday);
      expect(e?.amount, Money(egp, tenK));
      expect(await incomes(egp), isEmpty);
      expect(await cycleIncome(payday, egp), 0);
      final r = await service.confirmReceived(payday, today: payday);
      expect(r, isA<SalaryRecorded>());
      expect(await incomes(egp), [tenK]);
      expect(await cycleIncome(payday, egp), tenK);
      expect(await service.expected(payday), isNull);
      // The category is the seeded income one; the account is the default
      // cash account (the plan names none).
      final row = (await TransactionsDao(db)
          .byId((r as SalaryRecorded).txnId))!;
      expect(row.categoryId, 'sys:income');
      expect(row.accountId, 'cash');
      expect(row.source, 'manual');
    });

    test('a second confirm for the same payday is refused', () async {
      await setPlan();
      await service.confirmReceived(payday, today: payday);
      expect(
        service.confirmReceived(payday, today: payday),
        throwsA(
          isA<SalaryServiceException>().having(
            (e) => e.code,
            'code',
            SalaryServiceException.notOpen,
          ),
        ),
      );
      expect(await incomes(egp), [tenK]);
    });

    test(
      'the plan account is used; a missing one falls back to cash',
      () async {
        await setPlan(account: 'acc1');
        var r = await service.confirmReceived(payday, today: payday);
        expect(
          (await TransactionsDao(db).byId((r as SalaryRecorded).txnId))!
              .accountId,
          'acc1',
        );
        await service.skip(payday.plusDays(31)); // unrelated
        await setPlan(account: 'gone');
        await db.customStatement('UPDATE transactions SET deleted_at = 1');
        r = await service.confirmReceived(payday, today: payday);
        expect(
          (await TransactionsDao(db).byId((r as SalaryRecorded).txnId))!
              .accountId,
          'cash',
        );
      },
    );

    test('a manual one-off salary counts too, without any plan', () async {
      final id = await manual(date: CivilDate(2026, 11, 10));
      expect(await incomes(egp), [tenK]);
      expect(await cycleIncome(CivilDate(2026, 11, 10), egp), tenK);
      expect((await TransactionsDao(db).byId(id))!.categoryId, 'sys:income');
    });
  });

  group('AC2: exactly one income, both orders', () {
    test('manual first, SMS later: the SMS is shown and counted', () async {
      await setPlan();
      final man = await manual();
      await sms('s1', tenK, payday.plusDays(1), merchant: 'BNK');
      expect(await arrive('s1'), SalaryMatchStatus.merged);
      expect(await incomes(egp), [tenK]);
      expect(await cycleIncome(payday, egp), tenK);
      expect(await deleted(man), isTrue);
      expect(await deleted('s1'), isFalse);
      expect((await TransactionsDao(db).byId('s1'))!.categoryId, 'sys:income');
      // Running it again changes nothing.
      expect(await arrive('s1'), SalaryMatchStatus.none);
      expect(await incomes(egp), [tenK]);
      expect(await service.expected(payday.plusDays(1)), isNull);
    });

    test('SMS first, manual later: the manual one is not added', () async {
      await setPlan();
      await sms('s1', tenK, payday);
      expect(await arrive('s1'), SalaryMatchStatus.tagged);
      final r = await service.recordManual(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.income,
          amount: Money(egp, tenK),
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            payday.epochDay * day + 10 * 3600000,
            isUtc: true,
          ),
          occurredTzOffsetMin: 120,
        ),
      );
      expect(r, isA<SalaryFoundExisting>());
      expect((r as SalaryFoundExisting).txnId, 's1');
      expect(await incomes(egp), [tenK]);
    });

    test('SMS first with no plan, manual later: asks, then ties it', () async {
      await sms('s1', tenK, payday);
      expect(await arrive('s1'), SalaryMatchStatus.none);
      final r = await service.recordManual(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.income,
          amount: Money(egp, tenK),
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            payday.epochDay * day + 10 * 3600000,
            isUtc: true,
          ),
          occurredTzOffsetMin: 120,
        ),
      );
      expect(r, isA<SalaryFoundExisting>());
      expect(await incomes(egp), [tenK]);
      // The user says it is another income: it is then written.
      final again = await service.recordManual(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.income,
          amount: Money(egp, tenK),
          occurredAt: DateTime.fromMillisecondsSinceEpoch(
            payday.epochDay * day + 10 * 3600000,
            isUtc: true,
          ),
          occurredTzOffsetMin: 120,
        ),
        allowDuplicate: true,
      );
      expect(again, isA<SalaryRecorded>());
      expect(await incomes(egp), [tenK, tenK]);
    });

    test('SMS first while no plan, plan later: reconcile ties it', () async {
      await sms('s1', tenK, payday);
      expect(await arrive('s1'), SalaryMatchStatus.none);
      await setPlan();
      expect(await service.expected(payday), isNotNull);
      expect(await matching.reconcile(today: payday.plusDays(1)), 1);
      expect(await service.expected(payday.plusDays(1)), isNull);
      expect(await incomes(egp), [tenK]);
      // Ties once.
      expect(await matching.reconcile(today: payday.plusDays(1)), 0);
    });

    test(
      'amount drift: 14 percent merges, 16 percent stays separate',
      () async {
        await setPlan();
        await manual();
        await sms('s1', 1140000, payday);
        expect(await arrive('s1'), SalaryMatchStatus.merged);
        expect(await incomes(egp), [1140000]);

        await manual(date: payday.plusDays(31 - 3));
        await sms('s2', 1160000, payday.plusDays(31 - 3));
        expect(await arrive('s2'), SalaryMatchStatus.none);
        expect(await incomes(egp).then((l) => l.length), 3);
      },
    );

    test('a salary keyword merges whatever the amount', () async {
      await manual();
      await sms('s1', 2500000, payday, merchant: 'ACME PAYROLL');
      expect(await arrive('s1'), SalaryMatchStatus.merged);
      expect(await incomes(egp), [2500000]);
    });

    test('early and late payday: -3 and +5 merge, -4 and +6 do not', () async {
      await setPlan();
      for (final (offset, merges) in [
        (-3, true),
        (5, true),
        (-4, false),
        (6, false),
      ]) {
        await db.customStatement('DELETE FROM transactions');
        await db.customStatement(
          "DELETE FROM settings WHERE key = 'salary.state'",
        );
        final man = await manual();
        await sms('s$offset', tenK, payday.plusDays(offset));
        final r = await arrive('s$offset');
        expect(r == SalaryMatchStatus.merged, merges, reason: 'offset $offset');
        expect(await deleted(man), merges, reason: 'offset $offset');
        expect((await incomes(egp)).length, merges ? 1 : 2);
      }
    });

    test('two currencies never merge, never mix', () async {
      await setPlan();
      await manual();
      await sms('u1', tenK, payday, currency: usd, merchant: 'Salary');
      expect(await arrive('u1'), SalaryMatchStatus.none);
      expect(await incomes(egp), [tenK]);
      expect(await incomes(usd), [tenK]);
      expect(await cycleIncome(payday, egp), tenK);
      expect(await cycleIncome(payday, usd), tenK);
      // A USD salary plan with a USD credit: one USD income, EGP untouched.
      await setPlan(c: usd);
      await sms('u2', tenK, payday.plusDays(31), currency: usd);
      final next = CivilDate(2026, 12, 25);
      await sms('u3', tenK, next, currency: usd);
      expect(await arrive('u3'), SalaryMatchStatus.tagged);
    });

    test('a second similar credit stays a plain income', () async {
      await setPlan();
      await sms('s1', tenK, payday);
      await sms('s2', tenK, payday.plusDays(1));
      expect(await arrive('s1'), SalaryMatchStatus.tagged);
      expect(await arrive('s2'), SalaryMatchStatus.none);
      expect(await incomes(egp), [tenK, tenK]);
    });

    test(
      'undo restores the manual row and never merges that SMS again',
      () async {
        await setPlan();
        final man = await manual();
        await sms('s1', tenK, payday);
        await arrive('s1');
        await matching.undoMerge('s1');
        expect(await deleted(man), isFalse);
        expect(await incomes(egp), [tenK, tenK]);
        expect(await arrive('s1'), SalaryMatchStatus.none);
        expect(await incomes(egp), [tenK, tenK]);
        // No second undo.
        expect(
          matching.undoMerge('s1'),
          throwsA(
            isA<SalaryException>().having(
              (e) => e.code,
              'code',
              SalaryException.noMerge,
            ),
          ),
        );
      },
    );

    test('undo after the manual row was purged says so', () async {
      final man = await manual();
      await sms('s1', tenK, payday);
      await arrive('s1');
      await TransactionsDao(db).purgeDeletedAtOrBefore(nowMs + day);
      expect(await TransactionsDao(db).byId(man), isNull);
      expect(
        matching.undoMerge('s1'),
        throwsA(
          isA<SalaryException>().having(
            (e) => e.code,
            'code',
            SalaryException.gone,
          ),
        ),
      );
      expect(await incomes(egp), [tenK]);
    });

    test('two engines racing: exactly one winner, one income', () async {
      await manual();
      await sms('s1', tenK, payday);
      final other = makeMatching();
      final r = await Future.wait([arrive('s1'), other.onPersisted('s1')]);
      expect(r.where((s) => s == SalaryMatchStatus.merged).length, 1);
      expect(await incomes(egp), [tenK]);
    });

    test('credits that are not salary are left alone', () async {
      await setPlan();
      await manual();
      for (final (id, d, src) in [
        ('t1', 'transfer_out', 'sms'),
        ('t2', 'expense', 'sms'),
        ('t3', 'refund', 'sms'),
        ('t4', 'income', 'manual'),
      ]) {
        await sms(id, tenK, payday, direction: d, source: src);
        expect(await arrive(id), SalaryMatchStatus.none, reason: id);
      }
      await db.customStatement(
        "UPDATE transactions SET status = 'pending' WHERE id = 'p'",
      );
      await sms('i1', tenK, payday);
      await db.customStatement(
        "UPDATE transactions SET is_internal = 1 WHERE id = 'i1'",
      );
      expect(await arrive('i1'), SalaryMatchStatus.none);
      await sms('d1', tenK, payday);
      await TransactionsDao(db).softDelete('d1', at: nowMs);
      expect(await arrive('d1'), SalaryMatchStatus.none);
    });

    test('a merge announces the cycles of both rows', () async {
      await manual(); // Nov cycle
      await sms('s1', tenK, payday.plusDays(-3)); // Oct cycle
      await arrive('s1');
      await Future<void>.delayed(Duration.zero);
      final ev = seen.whereType<TransactionsChanged>().single;
      expect(ev.cycleKeys, containsAll(['2026-10-25', '2026-11-25']));
    });
  });

  group('hook', () {
    test('offers inserted rows only and never throws', () async {
      await manual();
      await sms('s1', tenK, payday);
      final hook = SalaryMatchingHook(matching);
      await hook.afterPersist(
        const PersistedTxn(txnId: 's1', accountId: 'acc1', inserted: false),
      );
      expect(await incomes(egp), [tenK, tenK]);
      await hook.afterPersist(
        const PersistedTxn(txnId: 'nope', accountId: 'acc1', inserted: true),
      );
      await hook.afterPersist(
        const PersistedTxn(txnId: 's1', accountId: 'acc1', inserted: true),
      );
      expect(await incomes(egp), [tenK]);
    });
  });

  group('AC3: skip, reopen, nudge', () {
    test('skip hides the item and the nudge', () async {
      await setPlan();
      expect(await service.nudgeDue(payday.plusDays(6)), payday);
      await service.skip(payday);
      expect(await service.expected(payday.plusDays(6)), isNull);
      expect(await service.nudgeDue(payday.plusDays(6)), isNull);
    });

    test('nudge only after the window, and not once tied', () async {
      await setPlan();
      expect(await service.nudgeDue(payday.plusDays(5)), isNull);
      expect(await service.nudgeDue(payday.plusDays(6)), payday);
      expect(await service.nudgeDue(payday.plusDays(21)), isNull);
      await sms('s1', tenK, payday.plusDays(2));
      await arrive('s1');
      expect(await service.nudgeDue(payday.plusDays(6)), isNull);
    });

    test('deleting the tied transaction reopens the item', () async {
      await setPlan();
      final id = await manual();
      expect(await service.expected(payday), isNull);
      await TransactionsDao(db).softDelete(id, at: nowMs);
      expect((await service.expected(payday))?.payday, payday);
    });

    test('link existing closes the item with a received credit', () async {
      await setPlan(minor: 5000000);
      await sms('s1', 3000000, payday); // 60% of the plan: asked, not tied
      expect(await arrive('s1'), SalaryMatchStatus.none);
      final r = await service.confirmReceived(payday, today: payday);
      expect(r, isA<SalaryFoundExisting>());
      await service.linkExisting(payday, 's1');
      expect(await service.expected(payday), isNull);
      expect(await incomes(egp), [3000000]);
    });
  });

  group('review fixes', () {
    NewTransaction leg() => NewTransaction(
      accountId: 'acc1',
      direction: TxnDirection.income,
      amount: Money(egp, tenK),
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        payday.epochDay * day + 10 * 3600000,
        isUtc: true,
      ),
      occurredTzOffsetMin: 120,
    );

    test('F1 add flow: "another income" survives reconcile', () async {
      await setPlan();
      await sms('s1', tenK, payday);
      expect(await service.recordManual(leg()), isA<SalaryFoundExisting>());
      await service.recordManual(leg(), allowDuplicate: true);
      expect(await incomes(egp), [tenK, tenK]);
      await matching.reconcile(today: payday.plusDays(1));
      expect(await arrive('s1'), SalaryMatchStatus.none);
      expect(await incomes(egp), [tenK, tenK]);
    });

    test('F1 "It arrived" flow: "another income" survives reconcile', () async {
      await setPlan(minor: 5000000);
      await sms('s1', 3000000, payday);
      final r = await service.confirmReceived(payday, today: payday);
      expect(r, isA<SalaryFoundExisting>());
      await service.confirmReceived(
        payday,
        today: payday,
        allowDuplicate: true,
      );
      expect(await incomes(egp), [5000000, 3000000]);
      await matching.reconcile(today: payday.plusDays(1));
      expect(await incomes(egp), [5000000, 3000000]);
    });

    test('FU-268 a declined credit is offered again once the other income '
        'row is deleted', () async {
      await setPlan();
      await sms('s1', tenK, payday);
      await service.recordManual(leg(), allowDuplicate: true);
      expect(await incomes(egp), [tenK, tenK]);
      // While the other income is live, s1 stays declined.
      expect(await service.recordManual(leg()), isA<SalaryFoundExisting>());
      await db.customStatement(
        "UPDATE transactions SET deleted_at = 1 WHERE source = 'manual'",
      );
      final r = await service.recordManual(leg());
      expect(r, isA<SalaryFoundExisting>());
      expect((r as SalaryFoundExisting).txnId, 's1');
    });

    test('F2 linkExisting keeps a manual entry manual', () async {
      await setPlan();
      final man = await manual();
      await service.linkExisting(payday, man);
      final state = await SettingsRepository(SettingsDao(db))
          .get(Settings.salaryState);
      expect(state.entryOf(man)!.captured, isFalse);
      await sms('s1', tenK, payday);
      expect(await arrive('s1'), SalaryMatchStatus.merged);
      expect(await incomes(egp), [tenK]);
    });

    test(
      'F3 a tied row edited to an expense or internal reopens the payday',
      () async {
        await setPlan();
        final id = await manual();
        expect(await service.expected(payday), isNull);
        await db.customStatement(
          "UPDATE transactions SET direction = 'expense' WHERE id = '$id'",
        );
        expect((await service.expected(payday))?.payday, payday);
        await db.customStatement(
          "UPDATE transactions SET direction = 'income', is_internal = 1 "
          "WHERE id = '$id'",
        );
        expect((await service.expected(payday))?.payday, payday);
        // And an SMS is not merged into a row that no longer counts as income.
        await sms('s1', tenK, payday);
        expect(await arrive('s1'), SalaryMatchStatus.tagged);
      },
    );
  });
}
