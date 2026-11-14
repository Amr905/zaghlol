// T-092: pair suggestions. Acceptance criteria are named in the test titles.
// All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/prices_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/daos/transfers_dao.dart';
import 'package:zaghlol/features/transactions/application/transfer_pairing.dart';
import 'package:zaghlol/features/transfers/application/suggestions.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const int day = 86400000;
const int min = 60000;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late PairSuggestions uc;
  var nextId = 0;

  Future<void> add(
    String id, {
    String direction = 'expense',
    int minor = 120000,
    int at = 0,
    String account = 'acc1',
    String currency = 'EGP',
    String? category,
    String? cpKind,
  }) => TransactionsDao(db).insert(
    txn(
      id,
      accountId: account,
      direction: direction,
      amountMinor: minor,
      currency: currency,
      occurredAt: t0 + at,
    ).copyWith(categoryId: Value(category), counterpartyKind: Value(cpKind)),
  );

  Future<void> category(String id, String code, {String? parent}) => db
      .into(db.categories)
      .insert(
        CategoriesCompanion.insert(
          id: id,
          systemCode: Value(code),
          parentId: Value(parent),
          nameAr: id,
          nameEn: id,
          icon: 'x',
          color: '#000000',
          bucket: 'wants',
          sort: 0,
        ),
      );

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');
  Future<int> links() => count('SELECT count(*) AS n FROM offset_links');
  Future<int> pairs() => count('SELECT count(*) AS n FROM transfer_pairs');

  setUp(() async {
    nextId = 0;
    edb = await EncryptedDb.open();
    db = edb.db;
    final a = AccountsDao(db);
    await a.insert(account('acc1'));
    await a.insert(account('usd', last4: '5555', currency: 'USD'));
    await category('dine', 'dining');
    await category('groc', 'groceries');
    await category('cafe', 'cafes', parent: 'dine');
    uc = PairSuggestions(
      db,
      loadSchedule: () async => PaydaySchedule.single(1),
      clock: () => DateTime.fromMillisecondsSinceEpoch(t0 + day, isUtc: true),
      newId: () => 's${nextId++}',
    );
  });

  tearDown(() => edb.close());

  group('AC1 suggestion appears, applies only on tap', () {
    test(
      'dining bill then friend repays: item opened, nothing linked',
      () async {
        await add('bill', category: 'dine');
        await add(
          'in1',
          direction: 'transfer_in',
          minor: 40000,
          at: day,
          cpKind: 'person',
        );
        final r = await uc.suggestReimbursement('in1');
        expect(r.status, SuggestionStatus.opened);
        expect(r.expenseIds, ['bill']);
        expect(await links(), 0);
        expect(
          await count(
            'SELECT count(*) AS n FROM review_items WHERE '
            "kind = 'reimbursement_suggestion' AND resolved_at IS NULL",
          ),
          1,
        );
      },
    );

    test('accept links the transfer to the expense and resolves it', () async {
      await add('bill', category: 'dine');
      await add(
        'in1',
        direction: 'income',
        minor: 40000,
        at: day,
        cpKind: 'ipa',
      );
      final r = await uc.suggestReimbursement('in1');
      final res = await uc.acceptReimbursement(r.itemId!, 'bill');
      expect(res.plan.grants.single.granted.minor, 40000);
      expect(await links(), 1);
      expect(
        await count(
          'SELECT count(*) AS n FROM review_items WHERE '
          "resolution = 'linked' AND txn_id = 'in1'",
        ),
        1,
      );
      // A resolved item cannot be accepted again.
      await expectLater(
        uc.acceptReimbursement(r.itemId!, 'bill'),
        throwsA(isA<SuggestionException>()),
      );
    });

    test('accept refuses an expense the suggestion did not name', () async {
      await add('bill', category: 'dine');
      await add('other', category: 'dine', at: day ~/ 2);
      await add(
        'in1',
        direction: 'transfer_in',
        minor: 40000,
        at: day,
        cpKind: 'person',
      );
      final r = await uc.suggestReimbursement('in1');
      await expectLater(
        uc.acceptReimbursement(r.itemId!, 'groc-x'),
        throwsA(isA<SuggestionException>()),
      );
      expect(await links(), 0);
    });
  });

  group('eligibility (FR-XFR-08, A-45)', () {
    Future<SuggestionStatus> run({
      int expenseAt = 0,
      int incomingAt = day,
      int expenseMinor = 120000,
      int incomingMinor = 40000,
      String? cat = 'dine',
      String expenseCur = 'EGP',
      String incomingCur = 'EGP',
      String? cpKind = 'person',
      String direction = 'transfer_in',
    }) async {
      await add(
        'bill',
        minor: expenseMinor,
        at: expenseAt,
        category: cat,
        currency: expenseCur,
        account: expenseCur == 'USD' ? 'usd' : 'acc1',
      );
      await add(
        'in1',
        direction: direction,
        minor: incomingMinor,
        at: incomingAt,
        cpKind: cpKind,
        currency: incomingCur,
        account: incomingCur == 'USD' ? 'usd' : 'acc1',
      );
      return (await uc.suggestReimbursement('in1')).status;
    }

    test('exactly 7 days after: yes', () async {
      expect(await run(incomingAt: 7 * day), SuggestionStatus.opened);
    });
    test('one ms past 7 days: none', () async {
      expect(await run(incomingAt: 7 * day + 1), SuggestionStatus.none);
    });
    test('transfer before the expense: none', () async {
      expect(await run(expenseAt: day, incomingAt: 0), SuggestionStatus.none);
    });
    test('bigger than the expense: none', () async {
      expect(await run(incomingMinor: 130000), SuggestionStatus.none);
    });
    test('equal to the remaining amount: yes', () async {
      expect(await run(incomingMinor: 120000), SuggestionStatus.opened);
    });
    test('groceries and uncategorised: none', () async {
      expect(await run(cat: 'groc'), SuggestionStatus.none);
    });
    test('sub-category of dining counts', () async {
      expect(await run(cat: 'cafe'), SuggestionStatus.opened);
    });
    test('other currency: none, nothing converted', () async {
      expect(await run(incomingCur: 'USD'), SuggestionStatus.none);
    });
    test('merchant counterparty: none', () async {
      expect(await run(cpKind: 'merchant'), SuggestionStatus.none);
    });
    test('no counterparty: none', () async {
      expect(await run(cpKind: null), SuggestionStatus.none);
    });
    test('an outgoing transfer: none', () async {
      expect(await run(direction: 'transfer_out'), SuggestionStatus.none);
    });

    test('a shared expense of any category counts', () async {
      await add('bill', category: 'groc');
      await SplitParticipantsDao(db).insert(
        SplitParticipantsCompanion.insert(
          id: 'p1',
          expenseTxnId: 'bill',
          name: 'Synthetic friend',
          shareMinor: 40000,
          createdAt: t0,
        ),
      );
      await add(
        'in1',
        direction: 'transfer_in',
        minor: 40000,
        at: day,
        cpKind: 'person',
      );
      expect(
        (await uc.suggestReimbursement('in1')).status,
        SuggestionStatus.opened,
      );
    });

    test('remaining after earlier links is what counts', () async {
      await add('bill', category: 'dine');
      await add(
        'early',
        direction: 'transfer_in',
        minor: 100000,
        cpKind: 'person',
      );
      await OffsetLinksDao(db).insert(
        OffsetLinksCompanion.insert(
          id: 'l0',
          kind: 'reimbursement',
          expenseTxnId: 'bill',
          sourceTxnId: 'early',
          amountMinor: 100000,
          createdAt: t0,
        ),
      );
      await add(
        'in1',
        direction: 'transfer_in',
        minor: 40000,
        at: day,
        cpKind: 'person',
      );
      expect(
        (await uc.suggestReimbursement('in1')).status,
        SuggestionStatus.none,
      );
    });

    test('most recent first, at most five; repeat call adds no item', () async {
      for (var k = 0; k < 7; k++) {
        await add('b$k', minor: 120000, at: k * day ~/ 10, category: 'dine');
      }
      await add(
        'in1',
        direction: 'transfer_in',
        minor: 40000,
        at: day,
        cpKind: 'person',
      );
      final a = await uc.suggestReimbursement('in1');
      expect(a.expenseIds, ['b6', 'b5', 'b4', 'b3', 'b2']);
      final b = await uc.suggestReimbursement('in1');
      expect(b.status, SuggestionStatus.alreadyOpen);
      expect(b.itemId, a.itemId);
    });
  });

  group('dismiss memory', () {
    test(
      'dismissed candidates are not suggested again; new ones are',
      () async {
        await add('bill', category: 'dine');
        await add(
          'in1',
          direction: 'transfer_in',
          minor: 40000,
          at: day,
          cpKind: 'person',
        );
        final a = await uc.suggestReimbursement('in1');
        expect(await uc.dismiss(a.itemId!), isTrue);
        expect(await uc.dismiss(a.itemId!), isFalse);
        expect(
          (await uc.suggestReimbursement('in1')).status,
          SuggestionStatus.none,
        );
        await add('bill2', category: 'dine', at: day ~/ 2);
        final c = await uc.suggestReimbursement('in1');
        expect(c.expenseIds, ['bill2']);
        expect(await links(), 0);
      },
    );
  });

  group('AC1 cross-currency pairs: suggestion, applied only on tap', () {
    Future<String> suggestFx() async {
      await PricesDao(db).upsertRate((
        base: Currency.of('USD'),
        quote: Currency.of('EGP'),
        rateE9: 48500000000,
        asOf: t0,
      ));
      await add(
        'o',
        direction: 'transfer_out',
        minor: 10000,
        currency: 'USD',
        account: 'usd',
      );
      await add('i', direction: 'transfer_in', minor: 485000, at: min);
      final pairing = TransferPairingUseCase(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        newId: () => 'q${nextId++}',
      );
      expect((await pairing.onPersisted('i')).status, PairingStatus.suggested);
      expect(await pairs(), 0);
      final item = await db
          .customSelect(
            "SELECT id FROM review_items WHERE kind = 'fx_pair_suggestion'",
          )
          .getSingle();
      return item.read<String>('id');
    }

    test('accept pairs the legs, keeps amounts and currencies', () async {
      final id = await suggestFx();
      final r = await uc.acceptFxPair(id, 'o');
      expect(r.pairKind, TransferPairKind.crossCurrency);
      expect(await pairs(), 1);
      final rows = await db
          .customSelect(
            'SELECT amount_minor AS a, currency AS c, is_internal AS x '
            'FROM transactions ORDER BY id',
          )
          .get();
      expect(
        rows.map(
          (e) => (e.read<int>('a'), e.read<String>('c'), e.read<int>('x')),
        ),
        [(485000, 'EGP', 1), (10000, 'USD', 1)],
      );
      expect(
        await count(
          'SELECT count(*) AS n FROM review_items WHERE resolved_at IS NULL',
        ),
        0,
      );
    });

    test('accept works from the item on the outgoing leg too', () async {
      final id = await suggestFx();
      await db.customStatement(
        "UPDATE review_items SET txn_id = 'o', payload = '{\"candidates\":[\"i\"]}' "
        'WHERE id = ?',
        [id],
      );
      await uc.acceptFxPair(id, 'i');
      expect(await pairs(), 1);
    });

    test('nothing is paired unless accepted; unnamed leg is refused', () async {
      final id = await suggestFx();
      expect(await pairs(), 0);
      await expectLater(
        uc.acceptFxPair(id, 'bogus'),
        throwsA(isA<SuggestionException>()),
      );
      expect(await pairs(), 0);
    });

    test(
      'dismiss is remembered: re-evaluating either leg suggests nothing',
      () async {
        final id = await suggestFx();
        expect(await uc.dismiss(id), isTrue);
        final pairing = TransferPairingUseCase(
          db,
          loadSchedule: () async => PaydaySchedule.single(1),
          newId: () => 'q${nextId++}',
        );
        expect((await pairing.onPersisted('i')).status, PairingStatus.none);
        expect((await pairing.onPersisted('o')).status, PairingStatus.none);
        expect(
          await count(
            'SELECT count(*) AS n FROM review_items WHERE resolved_at IS NULL',
          ),
          0,
        );
        expect(await pairs(), 0);
      },
    );
  });
}
