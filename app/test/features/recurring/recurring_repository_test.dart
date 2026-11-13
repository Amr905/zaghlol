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

  group('detection', () {
    test(
      'Netflix-like history yields one suggestion and one review item',
      () async {
        await charge('t1', 2026, 8, 5, 19900);
        await charge('t2', 2026, 9, 5, 19900);
        await charge('t3', 2026, 10, 5, 19900);
        final ids = await repo.detectAndSuggest();
        expect(ids, hasLength(1));
        final row = await item(ids.single);
        expect(row.status, 'suggested');
        expect(row.amount, Money(egp, 19900));
        expect(row.nextDueDate, '2026-11-05');
        final open = await ReviewItemsDao(db)
            .open(kind: ReviewKind.subscriptionSuggestion);
        expect(open, hasLength(1));
        // Idempotent: a second run adds nothing.
        expect(await repo.detectAndSuggest(), isEmpty);
        expect(await ReviewItemsDao(db).countOpen(), 1);
      },
    );

    test('internal transfers and deleted rows are ignored', () async {
      await charge('t1', 2026, 9, 5, 100);
      await charge('t2', 2026, 10, 5, 100);
      await (db.update(db.transactions)..where((t) => t.id.equals('t2'))).write(
        const TransactionsCompanion(isInternal: Value(1)),
      );
      expect(await repo.detectAndSuggest(), isEmpty);
    });

    test('confirm activates and resolves the review item; once only', () async {
      await charge('t1', 2026, 9, 5, 100);
      await charge('t2', 2026, 10, 5, 100);
      final id = (await repo.detectAndSuggest()).single;
      expect(await repo.confirm(id), isTrue);
      expect((await item(id)).status, 'active');
      expect(await ReviewItemsDao(db).countOpen(), 0);
      expect(await repo.confirm(id), isFalse);
      expect(await repo.dismiss(id), isFalse);
    });

    test('a dismissed suggestion is never suggested again', () async {
      await charge('t1', 2026, 9, 5, 100);
      await charge('t2', 2026, 10, 5, 100);
      final id = (await repo.detectAndSuggest()).single;
      expect(await repo.dismiss(id), isTrue);
      expect((await item(id)).status, 'dismissed');
      await charge('t3', 2026, 11, 5, 100);
      expect(await repo.detectAndSuggest(), isEmpty);
      expect(await ReviewItemsDao(db).countOpen(), 0);
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
      await charge('t1', 2026, 10, 20, 100);
      await charge('t2', 2026, 11, 19, 100);
      await repo.detectAndSuggest();
      now = DateTime.utc(2026, 12, 17, 12);
      expect(await repo.dueReminders(), isEmpty);
    });
  });
}
