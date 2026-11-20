// T-096: RecurringRepository against an encrypted database. Synthetic data.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/core/db/money_columns.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../core/db/financial_fixtures.dart';

final egp = Currency.of('EGP');

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late RecurringRepository repo;
  var n = 0;
  var now = DateTime.utc(2026, 11, 13, 12);

  /// Noon UTC on the given civil date (+120 min offset keeps the local date).
  int at(int y, int m, int d) =>
      DateTime.utc(y, m, d, 12).millisecondsSinceEpoch;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    n = 0;
    now = DateTime.utc(2026, 11, 13, 12);
    await db.into(db.accounts).insert(account('acc1'));
    repo = RecurringRepository(db, clock: () => now, newId: () => 'id${++n}');
  });
  tearDown(() => edb.close());

  Future<void> charge(
    String id,
    int y,
    int m,
    int d,
    int minor, {
    String merchant = 'streamco',
    String account = 'acc1',
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          accountId: account,
          amountMinor: minor,
          merchantNorm: merchant,
          merchant: 'StreamCo',
          occurredAt: at(y, m, d),
        ),
      );

  Future<RecurringItemRow> item(String id) async =>
      (await RecurringDao(db).itemById(id))!;

  Future<void> setCategory(String txnId, String category) =>
      (db.update(db.transactions)..where((t) => t.id.equals(txnId))).write(
        TransactionsCompanion(
          categoryId: Value(category),
          categorySource: const Value('user'),
        ),
      );

  /// [count] charges of [minor], [stepMonths] apart, the last one on
  /// [y]-[m]-[d] (months counted back from it).
  Future<void> chain(
    int count,
    int stepMonths,
    int y,
    int m,
    int d,
    int minor, {
    String merchant = 'streamco',
    String account = 'acc1',
    String prefix = 't',
  }) async {
    for (var i = 0; i < count; i++) {
      final back = (count - 1 - i) * stepMonths;
      final idx = y * 12 + (m - 1) - back;
      await charge(
        '$prefix${i + 1}',
        idx ~/ 12,
        idx % 12 + 1,
        d,
        minor,
        merchant: merchant,
        account: account,
      );
    }
  }

  Future<List<String>> dismissalKeys() async => [
    for (final r in await db.select(db.recurringDismissals).get())
      r.dismissalKey,
  ];

  group('detection (D-72: added as bills automatically)', () {
    test(
      'FU-256: a restore waiting stops detection before it writes',
      () async {
        await chain(3, 1, 2026, 10, 5, 19900);
        expect(await repo.detectAndAutoAdd(shouldStop: () => true), isEmpty);
        expect(await repo.detectAndAutoAdd(), hasLength(1)); // next run
      },
    );

    test('a monthly chain becomes an active, auto-added bill at once, with '
        'no review item', () async {
      await chain(3, 1, 2026, 10, 5, 19900);
      final added = await repo.detectAndAutoAdd();
      expect(added, hasLength(1));
      final row = await item(added.single.id);
      expect(row.status, 'active');
      expect(row.kind, RecurringKind.subscription);
      expect(row.cadence, 'monthly');
      expect(row.amount, Money(egp, 19900));
      expect(row.nextDueDate, '2026-11-05');
      expect(row.dueDay, 5);
      expect(row.autoAddedAt, now.millisecondsSinceEpoch);
      expect(await ReviewItemsDao(db).countOpen(), 0);
      expect(await repo.list(), hasLength(1));
      // Idempotent: a second run adds nothing.
      expect(await repo.detectAndAutoAdd(), isEmpty);
      expect(await repo.list(), hasLength(1));
    });

    test('3-, 6- and 12-month chains are added with their cadence and next '
        'due date', () async {
      // Quarterly: Feb 10, May 10, Aug 10 -> next Nov 10 (2026).
      await chain(3, 3, 2026, 8, 10, 30000, merchant: 'insureco');
      // Every 6 months: 2025-12-31 and 2026-06-30 -> next 2026-12-31.
      await charge('s1', 2025, 12, 31, 90000, merchant: 'clubco');
      await charge('s2', 2026, 6, 30, 90000, merchant: 'clubco');
      // Yearly: 2025-03-03, 2026-03-03 -> next 2027-03-03.
      await charge('y1', 2025, 3, 3, 250000, merchant: 'domainco');
      await charge('y2', 2026, 3, 3, 250000, merchant: 'domainco');
      final added = await repo.detectAndAutoAdd();
      final byMerchant = {for (final r in added) r.merchantNorm!: r};
      expect(byMerchant.keys.toSet(), {'insureco', 'clubco', 'domainco'});
      expect(byMerchant['insureco']!.cadence, 'quarterly');
      expect(byMerchant['insureco']!.nextDueDate, '2026-11-10');
      expect(byMerchant['clubco']!.cadence, 'semi_annual');
      expect(byMerchant['clubco']!.nextDueDate, '2026-12-31');
      expect(byMerchant['clubco']!.dueDay, 31);
      expect(byMerchant['domainco']!.cadence, 'yearly');
      expect(byMerchant['domainco']!.nextDueDate, '2027-03-03');
      // All show in the bills list without any user action.
      expect(await repo.list(), hasLength(3));
    });

    test('near misses add nothing: two monthly charges, irregular gaps, '
        'varying merchants, a different amount', () async {
      await chain(2, 1, 2026, 10, 5, 100, merchant: 'two');
      await charge('i1', 2026, 5, 1, 100, merchant: 'irregular');
      await charge('i2', 2026, 6, 20, 100, merchant: 'irregular');
      await charge('i3', 2026, 7, 25, 100, merchant: 'irregular');
      await charge('i4', 2026, 10, 1, 100, merchant: 'irregular');
      await charge('v1', 2026, 8, 5, 100, merchant: 'shop one');
      await charge('v2', 2026, 9, 5, 100, merchant: 'shop two');
      await charge('v3', 2026, 10, 5, 100, merchant: 'shop three');
      await charge('p1', 2026, 8, 7, 1000, merchant: 'pricey');
      await charge('p2', 2026, 9, 7, 2000, merchant: 'pricey');
      await charge('p3', 2026, 10, 7, 3000, merchant: 'pricey');
      expect(await repo.detectAndAutoAdd(), isEmpty);
      expect(await repo.list(), isEmpty);
    });

    test('a stopped plan (last charge long ago) is not added', () async {
      await chain(3, 1, 2026, 3, 5, 100);
      expect(await repo.detectAndAutoAdd(), isEmpty);
      await charge('y1', 2024, 12, 1, 100, merchant: 'oldyearly');
      await charge('y2', 2025, 12, 1, 100, merchant: 'oldyearly');
      now = DateTime.utc(2026, 12, 20, 12); // next due 2026-12-01 is stale
      expect(await repo.detectAndAutoAdd(), isEmpty);
      now = DateTime.utc(2026, 12, 8, 12);
      expect(await repo.detectAndAutoAdd(), hasLength(1));
    });

    test('currencies never mix: the same merchant in two currencies is two '
        'chains, and a mixed series is none', () async {
      await db
          .into(db.accounts)
          .insert(account('usdacc', currency: 'USD', last4: '5678'));
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.transactions)
            .insert(
              txn(
                'u$i',
                accountId: 'usdacc',
                currency: 'USD',
                amountMinor: 999,
                merchantNorm: 'streamco',
                occurredAt: at(2026, 8 + i, 5),
              ),
            );
      }
      // Alternating currencies on one account: no chain.
      await charge('m1', 2026, 8, 9, 100, merchant: 'mixed');
      await db
          .into(db.transactions)
          .insert(
            txn(
              'm2',
              currency: 'USD',
              amountMinor: 100,
              merchantNorm: 'mixed',
              occurredAt: at(2026, 9, 9),
            ),
          );
      await charge('m3', 2026, 10, 9, 100, merchant: 'mixed');
      await chain(3, 1, 2026, 10, 5, 19900);
      final added = await repo.detectAndAutoAdd();
      expect(
        {for (final r in added) '${r.merchantNorm}/${r.currency}'},
        {'streamco/USD', 'streamco/EGP'},
      );
      expect(
        added.firstWhere((r) => r.currency == 'USD').amount,
        Money(Currency.of('USD'), 999),
      );
    });

    test('internal transfers, deleted rows and groceries are '
        'ignored', () async {
      for (final c in [
        'sys:groceries',
        'sys:dining',
        'sys:rent',
        'sys:bills',
      ]) {
        await db.customStatement(
          'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
          "sort) VALUES ('$c', 'x', 'X', 'i', '#000000', 'needs', 1)",
        );
      }
      await chain(3, 1, 2026, 10, 5, 100, merchant: 'internal', prefix: 'i');
      await (db.update(db.transactions)..where((t) => t.id.equals('i2'))).write(
        const TransactionsCompanion(isInternal: Value(1)),
      );
      await chain(3, 1, 2026, 10, 6, 100, merchant: 'gone', prefix: 'g');
      await (db.update(db.transactions)..where((t) => t.id.equals('g3'))).write(
        TransactionsCompanion(deletedAt: Value(now.millisecondsSinceEpoch)),
      );
      await chain(3, 1, 2026, 10, 7, 100, merchant: 'grocer', prefix: 'r');
      for (final id in ['r1', 'r2', 'r3']) {
        await setCategory(id, 'sys:groceries');
      }
      await chain(3, 1, 2026, 10, 8, 100, merchant: 'fun', prefix: 'f');
      await chain(3, 1, 2026, 10, 11, 100, merchant: 'eatery', prefix: 'd');
      for (final id in ['d1', 'd2', 'd3']) {
        await setCategory(id, 'sys:dining'); // dining is not a bill
      }
      // Rent and an electricity bill ARE bills; groceries is not.
      await chain(3, 1, 2026, 10, 9, 500000, merchant: 'landlord', prefix: 'l');
      for (final id in ['l1', 'l2', 'l3']) {
        await setCategory(id, 'sys:rent');
      }
      await chain(3, 1, 2026, 10, 10, 90000, merchant: 'power co', prefix: 'p');
      for (final id in ['p1', 'p2', 'p3']) {
        await setCategory(id, 'sys:bills');
      }
      final added = await repo.detectAndAutoAdd();
      expect(
        {for (final r in added) r.merchantNorm},
        {'fun', 'landlord', 'power co'},
      );
    });

    test('an own-account transfer (transfer_out) is never a bill', () async {
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.transactions)
            .insert(
              txn(
                'x$i',
                direction: 'transfer_out',
                amountMinor: 500000,
                merchantNorm: 'savings',
                occurredAt: at(2026, 8 + i, 1),
              ),
            );
      }
      expect(await repo.detectAndAutoAdd(), isEmpty);
    });

    test('a hand-typed item for the merchant (any status) blocks detection, '
        'also without an account', () async {
      await repo.addManual(
        kind: RecurringKind.bill,
        name: 'StreamCo',
        amount: Money(egp, 100),
        dueDay: 5,
        merchantNorm: 'streamco',
        nextDue: CivilDate(2026, 11, 5),
      );
      await chain(3, 1, 2026, 10, 5, 100);
      expect(await repo.detectAndAutoAdd(), isEmpty);
    });

    test('legacy suggested items still confirm and dismiss; a dismissed '
        'one is never re-added', () async {
      // A row from the old confirm-first flow.
      await RecurringDao(db).insertItem(
        RecurringItemsCompanion.insert(
          id: 'old1',
          kind: RecurringKind.subscription,
          status: RecurringStatus.suggested,
          name: 'StreamCo',
          merchantNorm: const Value('streamco'),
          accountId: const Value('acc1'),
          amountMinor: 0,
          currency: 'EGP',
          cadence: 'monthly',
          dueDay: const Value(5),
          nextDueDate: const Value('2026-11-05'),
          createdAt: 1,
        ).withAmount(Money(egp, 100)),
      );
      expect(await repo.dismiss('old1'), isTrue);
      expect((await item('old1')).status, 'dismissed');
      await chain(3, 1, 2026, 10, 5, 100);
      expect(await repo.detectAndAutoAdd(), isEmpty);
      expect(await repo.confirm('old1'), isFalse);
    });

    test('Not a bill removes the item for good: never re-added, even with '
        'newer charges and after the key rows are all that is left', () async {
      await chain(3, 1, 2026, 10, 5, 19900);
      final id = (await repo.detectAndAutoAdd()).single.id;
      expect(await repo.notABill(id), isTrue);
      expect(await RecurringDao(db).itemById(id), isNull);
      expect(await repo.list(), isEmpty);
      expect(await dismissalKeys(), ['streamco|acc1|EGP']);
      // Runs again, now and after the next charge and a month later.
      expect(await repo.detectAndAutoAdd(), isEmpty);
      await charge('t4', 2026, 11, 5, 19900);
      now = DateTime.utc(2026, 12, 1, 12);
      expect(await repo.detectAndAutoAdd(), isEmpty);
      expect(await repo.list(), isEmpty);
      // A second tap is a no-op.
      expect(await repo.notABill(id), isFalse);
      expect(await dismissalKeys(), hasLength(1));
      // Another merchant is still detected.
      await chain(3, 1, 2026, 11, 20, 500, merchant: 'other', prefix: 'o');
      expect(await repo.detectAndAutoAdd(), hasLength(1));
    });

    test('Not a bill only works on an active auto-added item; editing it '
        'ends the badge', () async {
      final manual = await repo.addManual(
        kind: RecurringKind.subscription,
        name: 'Mine',
        amount: Money(egp, 100),
        dueDay: 5,
        merchantNorm: 'mine',
      );
      expect(await repo.notABill(manual), isFalse);
      expect(await repo.notABill('nope'), isFalse);
      await chain(3, 1, 2026, 10, 5, 19900);
      final auto = (await repo.detectAndAutoAdd()).single;
      expect(
        await repo.updateManual(
          auto.id,
          kind: RecurringKind.subscription,
          name: 'StreamCo plus',
          amount: Money(egp, 19900),
          dueDay: 5,
          nextDue: CivilDate(2026, 11, 5),
          accountId: 'acc1',
        ),
        isTrue,
      );
      expect((await item(auto.id)).autoAddedAt, isNull);
      expect(await repo.notABill(auto.id), isFalse);
    });

    test('deleting a subscription by hand is remembered too', () async {
      await chain(3, 1, 2026, 10, 5, 19900);
      final id = (await repo.detectAndAutoAdd()).single.id;
      expect(await repo.deleteItem(id), isTrue);
      expect(await dismissalKeys(), ['streamco|acc1|EGP']);
      expect(await repo.detectAndAutoAdd(), isEmpty);
      expect(await repo.deleteItem(id), isFalse);
    });

    test('two repositories on the same database add one bill', () async {
      await chain(3, 1, 2026, 10, 5, 19900);
      final other = RecurringRepository(
        db,
        clock: () => now,
        newId: () => 'other${++n}',
      );
      final a = await repo.detectAndAutoAdd();
      final b = await other.detectAndAutoAdd();
      expect(a.length + b.length, 1);
      expect(await repo.list(), hasLength(1));
    });

    test('the look-back is long enough to see a yearly chain twice', () {
      expect(
        RecurringRepository.detectionLookbackDays,
        greaterThanOrEqualTo(740),
      );
    });
  });

  group('cadences after detection', () {
    test('a quarterly bill: auto-mark pays it and moves it 3 months on '
        '(month end clamps)', () async {
      await chain(3, 3, 2026, 8, 31, 30000, merchant: 'insureco');
      now = DateTime.utc(2026, 9, 1, 12);
      final id = (await repo.detectAndAutoAdd()).single.id;
      expect((await item(id)).nextDueDate, '2026-11-30');
      expect((await item(id)).dueDay, 31);
      await charge('pay', 2026, 11, 29, 30000, merchant: 'insureco');
      now = DateTime.utc(2026, 11, 27, 12);
      expect(await repo.autoMarkPaid(), hasLength(1));
      expect((await item(id)).nextDueDate, '2027-02-28');
    });

    test('markPaidManual moves quarterly, semi-annual and yearly items by '
        'their cycle', () async {
      for (final (cad, due, next) in <(RecurrenceCadence, String, String)>[
        (RecurrenceCadence.quarterly, '2026-11-30', '2027-02-28'),
        (RecurrenceCadence.semiAnnual, '2026-08-31', '2027-02-28'),
        (RecurrenceCadence.yearly, '2028-02-29', '2029-02-28'),
      ]) {
        final id = await repo.addManual(
          kind: RecurringKind.bill,
          name: cad.code,
          amount: Money(egp, 100),
          dueDay: CivilDate.tryParse(due)!.day,
          cadence: cad,
          merchantNorm: 'm ${cad.code.replaceAll('_', ' ')}',
          nextDue: CivilDate.tryParse(due),
        );
        expect(await repo.markPaidManual(id), isTrue, reason: cad.code);
        expect((await item(id)).nextDueDate, next, reason: cad.code);
      }
    });

    test('reminders reach quarterly, semi-annual and yearly items', () async {
      for (final cad in [
        RecurrenceCadence.quarterly,
        RecurrenceCadence.semiAnnual,
        RecurrenceCadence.yearly,
      ]) {
        await repo.addManual(
          kind: RecurringKind.bill,
          name: cad.code,
          amount: Money(egp, 100),
          dueDay: 16,
          cadence: cad,
          merchantNorm: 'r ${cad.code.replaceAll('_', ' ')}',
          nextDue: CivilDate(2026, 11, 16),
        );
      }
      expect(await repo.dueReminders(), hasLength(3));
      now = DateTime.utc(2026, 11, 19, 12);
      expect(await repo.overdueReminders(), hasLength(3));
    });
  });

  group('manual items', () {
    test('installment: matching payment marks it paid and advances', () async {
      final id = await repo.addManual(
        kind: RecurringKind.installment,
        name: 'Phone',
        amount: Money(egp, 150000),
        dueDay: 15,
        totalCount: 3,
        merchantNorm: 'tvshop',
        nextDue: CivilDate(2026, 11, 15),
      );
      await charge('p1', 2026, 11, 14, 150000, merchant: 'tvshop');
      final marks = await repo.autoMarkPaid();
      expect(marks.map((m) => m.txnId), ['p1']);
      final row = await item(id);
      expect(row.paidCount, 1);
      expect(row.nextDueDate, '2026-12-15');
      expect(row.status, 'active');
      final occ = await RecurringDao(db).occurrencesOf(id);
      expect(occ.single.txnId, 'p1');
      expect(occ.single.dueDate, '2026-11-15');
      // Running again links nothing (the transaction already paid).
      expect(await repo.autoMarkPaid(), isEmpty);
      expect((await item(id)).paidCount, 1);
    });

    test('last payment completes a counted item', () async {
      final id = await repo.addManual(
        kind: RecurringKind.installment,
        name: 'Fridge',
        amount: Money(egp, 100000),
        dueDay: 10,
        totalCount: 2,
        paidCount: 1,
        merchantNorm: 'tvshop',
        nextDue: CivilDate(2026, 11, 10),
      );
      await charge('p1', 2026, 11, 10, 100000, merchant: 'tvshop');
      final marks = await repo.autoMarkPaid();
      expect(marks.single.completed, isTrue);
      expect((await item(id)).status, 'completed');
      expect((await item(id)).paidCount, 2);
    });

    test(
      'out-of-window, off-amount and other-currency payments do not match',
      () async {
        await repo.addManual(
          kind: RecurringKind.bill,
          name: 'Rent',
          amount: Money(egp, 100000),
          dueDay: 15,
          merchantNorm: 'landlord',
          nextDue: CivilDate(2026, 11, 15),
        );
        await charge('late', 2026, 11, 21, 100000, merchant: 'landlord');
        await charge('off', 2026, 11, 15, 103000, merchant: 'landlord');
        expect(await repo.autoMarkPaid(), isEmpty);
      },
    );

    test('gameya is manual with a round count', () async {
      final id = await repo.addManual(
        kind: RecurringKind.gameya,
        name: 'Gameya',
        amount: Money(egp, 200000),
        dueDay: 31,
        totalCount: 10,
        accountId: 'acc1',
        nextDue: CivilDate(2026, 11, 30),
      );
      now = DateTime.utc(2026, 11, 29, 12);
      await db
          .into(db.transactions)
          .insert(txn('g1', amountMinor: 200000, occurredAt: at(2026, 11, 29)));
      final marks = await repo.autoMarkPaid();
      expect(marks, hasLength(1));
      // Anchor day 31 clamps to the month end.
      expect((await item(id)).nextDueDate, '2026-12-31');
    });

    test('validation rejects bad input with a typed failure', () async {
      Future<void> bad({
        String kind = RecurringKind.bill,
        String name = 'x',
        int minor = 100,
        int dueDay = 5,
        int? total,
        String? merchant = 'shop',
      }) => expectLater(
        repo.addManual(
          kind: kind,
          name: name,
          amount: Money(egp, minor),
          dueDay: dueDay,
          totalCount: total,
          merchantNorm: merchant,
        ),
        throwsA(isA<RecurringException>()),
      );
      await bad(kind: 'loan');
      await bad(name: '  ');
      await bad(minor: 0);
      await bad(minor: -5);
      await bad(dueDay: 0);
      await bad(dueDay: 32);
      await bad(total: 0);
      await bad(merchant: 'Bad Name');
      await bad(merchant: null); // neither merchant nor account
    });
  });

  group('card dues', () {
    test('a credit account with a due day gets one active item; due day change moves it', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'card1',
              kind: 'credit',
              label: 'Card',
              defaultCurrency: 'EGP',
              statementDueDay: const Value(20),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      expect(await repo.syncCardDues(), 1);
      expect(await repo.syncCardDues(), 0);
      final items = await repo.list();
      expect(items.single.kind, RecurringKind.cardDue);
      expect(items.single.nextDueDate, '2026-11-20');
      expect(items.single.amount, Money.zero(egp));
      await (db.update(db.accounts)..where((a) => a.id.equals('card1'))).write(
        const AccountsCompanion(statementDueDay: Value(5)),
      );
      expect(await repo.syncCardDues(), 1);
      expect((await repo.list()).single.nextDueDate, '2026-12-05');
    });

    test('a payment landing on the card marks the due paid', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'card1',
              kind: 'credit',
              label: 'Card',
              defaultCurrency: 'EGP',
              statementDueDay: const Value(20),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      await repo.syncCardDues();
      now = DateTime.utc(2026, 11, 18, 12);
      await db
          .into(db.transactions)
          .insert(
            txn(
              'pay',
              accountId: 'card1',
              direction: 'transfer_in',
              amountMinor: 345600,
              occurredAt: at(2026, 11, 19),
            ),
          );
      expect(await repo.autoMarkPaid(), hasLength(1));
      expect((await repo.list()).single.nextDueDate, '2026-12-20');
    });

    test('a 45 EGP purchase on the card does not mark the due paid', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: 'card1',
              kind: 'credit',
              label: 'Card',
              defaultCurrency: 'EGP',
              statementDueDay: const Value(20),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      await repo.syncCardDues();
      now = DateTime.utc(2026, 11, 18, 12);
      await db
          .into(db.transactions)
          .insert(
            txn(
              'buy',
              accountId: 'card1',
              direction: 'expense',
              amountMinor: 4500,
              occurredAt: at(2026, 11, 19),
            ),
          );
      expect(await repo.autoMarkPaid(), isEmpty);
      expect((await repo.list()).single.nextDueDate, '2026-11-20');
    });
  });

  group('reminders', () {
    test('fire 3 days before from 10:00 local, not before', () async {
      await repo.addManual(
        kind: RecurringKind.bill,
        name: 'Rent',
        amount: Money(egp, 100),
        dueDay: 20,
        merchantNorm: 'landlord',
        nextDue: CivilDate(2026, 11, 20),
      );
      now = DateTime.utc(2026, 11, 16, 12);
      expect(await repo.dueReminders(), isEmpty);
      now = DateTime.utc(2026, 11, 17, 12);
      final r = await repo.dueReminders();
      expect(r.single.dueDate, CivilDate(2026, 11, 20));
    });

    test('dismissed and suggested items never remind', () async {
      for (final status in [
        RecurringStatus.suggested,
        RecurringStatus.dismissed,
      ]) {
        await RecurringDao(db).insertItem(
          RecurringItemsCompanion.insert(
            id: status,
            kind: RecurringKind.subscription,
            status: status,
            name: 'x',
            merchantNorm: Value(status),
            accountId: const Value('acc1'),
            amountMinor: 0,
            currency: 'EGP',
            cadence: 'monthly',
            dueDay: const Value(20),
            nextDueDate: const Value('2026-11-20'),
            createdAt: 1,
          ).withAmount(Money(egp, 100)),
        );
      }
      now = DateTime.utc(2026, 11, 18, 12);
      expect(await repo.dueReminders(), isEmpty);
    });
  });
}
