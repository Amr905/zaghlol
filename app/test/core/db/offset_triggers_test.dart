// T-017 AC2: offset over-allocation aborts (BR-XFR-06, FR-XFR-07; design
// note §6). The triggers on offset_links (insert, update) and on
// transactions (amount / currency edits) raise fixed codes, which
// OffsetLinksDao surfaces as DbWriteException. Both executors (drift's
// background isolate and this isolate). All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import 'financial_fixtures.dart';

Matcher failsWith(String code) =>
    throwsA(isA<DbWriteException>().having((e) => e.code, 'code', code));

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late OffsetLinksDao links;
      late TransactionsDao txns;

      setUp(() async {
        edb = await EncryptedDb.open(background: background);
        links = OffsetLinksDao(edb.db);
        txns = TransactionsDao(edb.db);
        await AccountsDao(edb.db).insert(account('acc1'));
        // The spec example (FR-XFR-04/07): a 1,200.00 bill, 800.00 and
        // 400.00 coming back.
        await txns.insert(txn('bill', amountMinor: 120000));
        await txns.insert(txn('bill2', amountMinor: 30000));
        await txns.insert(
          txn('ahmed', direction: 'transfer_in', amountMinor: 80000),
        );
        await txns.insert(
          txn('karim', direction: 'transfer_in', amountMinor: 40000),
        );
        await txns.insert(
          txn('usd', direction: 'refund', amountMinor: 5000, currency: 'USD'),
        );
      });

      tearDown(() => edb.close());

      test('links up to exactly the expense amount are accepted', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'ahmed', amountMinor: 80000),
        );
        await links.insert(
          link('l2', expense: 'bill', source: 'karim', amountMinor: 40000),
        );
        expect(await links.linkedToExpense('bill'), 120000);
      });

      test('AC2: one minor unit over the expense aborts '
          '(OFFSET_EXCEEDS_EXPENSE), nothing written', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'ahmed', amountMinor: 80000),
        );
        await txns.insert(
          txn('omar', direction: 'transfer_in', amountMinor: 90000),
        );
        await expectLater(
          links.insert(
            link('l2', expense: 'bill', source: 'omar', amountMinor: 40001),
          ),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
        expect(await links.linkedToExpense('bill'), 80000);
        expect((await links.forExpense('bill')).length, 1);
      });

      test('AC2: a single link larger than the expense aborts', () async {
        await txns.insert(
          txn('big', direction: 'transfer_in', amountMinor: 999999),
        );
        await expectLater(
          links.insert(
            link('l1', expense: 'bill2', source: 'big', amountMinor: 30001),
          ),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
      });

      test('AC2: one incoming transfer split over expenses beyond its own '
          'amount aborts (OFFSET_EXCEEDS_SOURCE)', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'karim', amountMinor: 30000),
        );
        await expectLater(
          links.insert(
            link('l2', expense: 'bill2', source: 'karim', amountMinor: 10001),
          ),
          failsWith(DbWriteException.offsetExceedsSource),
        );
        // Exactly the rest is fine (FR-XFR-07).
        await links.insert(
          link('l3', expense: 'bill2', source: 'karim', amountMinor: 10000),
        );
        expect(await links.linkedFromSource('karim'), 40000);
      });

      test('AC2: raising a link through UPDATE is checked without counting '
          'its old amount', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'ahmed', amountMinor: 70000),
        );
        await links.insert(
          link('l2', expense: 'bill', source: 'karim', amountMinor: 40000),
        );
        // 80,000 + 40,000 = the bill: allowed (the old 70,000 is replaced).
        expect(await links.updateAmount('l1', 80000), 1);
        await expectLater(
          links.updateAmount('l1', 80001),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
        await expectLater(
          links.updateAmount('l2', 40001),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
        expect(await links.linkedToExpense('bill'), 120000);
      });

      test('AC2: an UPDATE moving a link to a smaller source aborts', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'ahmed', amountMinor: 50000),
        );
        expect(
          await failureOf(
            edb.db,
            "UPDATE offset_links SET source_txn_id = 'karim' WHERE id = 'l1'",
          ),
          DbWriteException.offsetExceedsSource,
        );
        expect(
          await failureOf(
            edb.db,
            "UPDATE offset_links SET expense_txn_id = 'bill2' WHERE id = 'l1'",
          ),
          DbWriteException.offsetExceedsExpense,
        );
      });

      test('AC2: lowering a linked expense or source below its links aborts; '
          'down to exactly the linked sum is allowed', () async {
        await links.insert(
          link('l1', expense: 'bill', source: 'ahmed', amountMinor: 60000),
        );
        await expectLater(
          txns.updateById(
            'bill',
            const TransactionsCompanion(amountMinor: Value(59999)),
          ),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
        await expectLater(
          txns.updateById(
            'ahmed',
            const TransactionsCompanion(amountMinor: Value(59999)),
          ),
          failsWith(DbWriteException.offsetExceedsSource),
        );
        expect(
          await txns.updateById(
            'bill',
            const TransactionsCompanion(amountMinor: Value(60000)),
          ),
          1,
        );
        expect((await txns.byId('bill'))!.amountMinor, 60000);
        // Unlinked transactions are free to change.
        expect(
          await txns.updateById(
            'bill2',
            const TransactionsCompanion(amountMinor: Value(1)),
          ),
          1,
        );
      });

      test('a source in another currency aborts (OFFSET_CURRENCY_MISMATCH); '
          'so does changing the currency of a linked transaction', () async {
        await expectLater(
          links.insert(
            link('l1', expense: 'bill', source: 'usd', amountMinor: 100),
          ),
          failsWith(DbWriteException.offsetCurrencyMismatch),
        );
        await links.insert(
          link('l2', expense: 'bill', source: 'ahmed', amountMinor: 100),
        );
        for (final id in ['bill', 'ahmed']) {
          await expectLater(
            txns.updateById(
              id,
              const TransactionsCompanion(currency: Value('USD')),
            ),
            failsWith(DbWriteException.offsetCurrencyMismatch),
          );
        }
        // Unlinked: allowed.
        expect(
          await txns.updateById(
            'bill2',
            const TransactionsCompanion(currency: Value('USD')),
          ),
          1,
        );
      });

      test('a participant of another expense aborts '
          '(OFFSET_PARTICIPANT_MISMATCH); one of the same expense is '
          'accepted', () async {
        Future<void> participant(String id, String expense) => edb.db
            .into(edb.db.splitParticipants)
            .insert(
              SplitParticipantsCompanion.insert(
                id: id,
                expenseTxnId: expense,
                name: 'Synthetic friend',
                shareMinor: 40000,
                createdAt: t0,
              ),
            );
        await participant('p-bill', 'bill');
        await participant('p-bill2', 'bill2');
        await expectLater(
          links.insert(
            link(
              'l1',
              expense: 'bill',
              source: 'karim',
              amountMinor: 40000,
              participant: 'p-bill2',
            ),
          ),
          failsWith(DbWriteException.offsetParticipantMismatch),
        );
        await links.insert(
          link(
            'l2',
            expense: 'bill',
            source: 'karim',
            amountMinor: 40000,
            participant: 'p-bill',
          ),
        );
        expect(
          await failureOf(
            edb.db,
            "UPDATE offset_links SET participant_id = 'p-bill2' WHERE id = 'l2'",
          ),
          DbWriteException.offsetParticipantMismatch,
        );
      });

      test('deleting a link frees its amount', () async {
        await links.insert(
          link('l1', expense: 'bill2', source: 'karim', amountMinor: 30000),
        );
        expect(await links.deleteById('l1'), 1);
        await links.insert(
          link('l2', expense: 'bill2', source: 'ahmed', amountMinor: 30000),
        );
        expect(await links.linkedToExpense('bill2'), 30000);
      });

      test('a failed link inside a transaction rolls back the whole '
          'transaction', () async {
        await expectLater(
          edb.db.transaction(() async {
            await links.insert(
              link('l1', expense: 'bill', source: 'ahmed', amountMinor: 80000),
            );
            await links.insert(
              link('l2', expense: 'bill', source: 'karim', amountMinor: 40001),
            );
          }),
          failsWith(DbWriteException.offsetExceedsExpense),
        );
        expect(await links.linkedToExpense('bill'), 0);
      });
    });
  }
}
