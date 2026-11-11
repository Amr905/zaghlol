// T-050: the transactions repository on an encrypted database (FR-TXN-01…05;
// T-017 review m-4). Acceptance criteria are named in the test titles.
// All data synthetic.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/features/transactions/data/drift_transaction_repository.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

const String foodId = 'sys:food';
const String billsId = 'sys:bills';
const String sentinel = 'T050SENTINEL';
final Currency egp = Currency.of('EGP');
final Currency kwd = Currency.of('KWD');
final Currency jpy = Currency.of('JPY');

Money egpMinor(int m) => Money(egp, m);

DateTime at(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

Future<String?> txnCode(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on TransactionsException catch (e) {
    return e.code;
  }
}

void main() {
  late EncryptedDb edb;
  late TransactionsDao dao;
  late DriftTransactionRepository repo;
  var clockMs = t0 + 1000;
  var nextId = 0;

  Future<List<String>> ids({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async => [
    for (final r in await repo.query(filter: filter, text: text, page: page))
      r.id,
  ];

  setUp(() async {
    clockMs = t0 + 1000;
    nextId = 0;
    edb = await EncryptedDb.open();
    dao = TransactionsDao(edb.db);
    repo = DriftTransactionRepository(
      dao,
      clock: () => at(clockMs),
      newId: () => 'gen${nextId++}',
    );
    final accounts = AccountsDao(edb.db);
    await accounts.insert(account('acc1'));
    await accounts.insert(account('acc2', institution: 'WAL', last4: '5678'));
    final cats = CategoriesDao(edb.db);
    await cats.upsertSystem(
      code: 'food',
      nameAr: 'أكل',
      nameEn: 'Food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    await cats.upsertSystem(
      code: 'bills',
      nameAr: 'فواتير',
      nameEn: 'Bills',
      icon: 'i',
      color: '#4D695C',
      bucket: 'obligations',
      sort: 2,
    );
  });

  tearDown(() => edb.close());

  group('add / edit (FR-TXN-02)', () {
    test('add stores a user-verified manual row, UTC, exact money', () async {
      final r = await repo.add(
        NewTransaction(
          accountId: 'acc1',
          direction: TxnDirection.expense,
          amount: Money(kwd, 1250),
          originalAmount: Money(Currency.of('USD'), 400),
          occurredAt: DateTime.utc(2026, 11, 1, 22, 30),
          occurredTzOffsetMin: 120,
          categoryId: foodId,
          merchant: '  Café Zamalek  ',
          note: '',
        ),
      );
      expect(r.id, 'gen0');
      expect(r.source, TxnSource.manual);
      expect(r.isUserVerified, isTrue);
      expect(r.categorySource, CategorySource.user);
      expect(r.amount, Money(kwd, 1250));
      expect(r.originalAmount, Money(Currency.of('USD'), 400));
      expect(r.occurredAt, DateTime.utc(2026, 11, 1, 22, 30));
      expect(r.occurredAt.isUtc, isTrue);
      expect(r.merchantRaw, 'Café Zamalek');
      expect(r.note, isNull);
      expect(r.createdAt, at(clockMs));
      expect(await repo.byId('gen0'), isNotNull);
    });

    test('add without a category records category_source none', () async {
      final r = await repo.add(_new());
      expect(r.categoryId, isNull);
      expect(r.categorySource, CategorySource.none);
    });

    test('add refuses a negative amount, a bad offset and an empty account '
        'before SQL', () async {
      expect(
        await txnCode(repo.add(_new(amount: egpMinor(-1)))),
        TransactionsException.invalid,
      );
      expect(
        await txnCode(repo.add(_new(tz: 1081))),
        TransactionsException.invalid,
      );
      expect(
        await txnCode(repo.add(_new(account: ''))),
        TransactionsException.invalid,
      );
    });

    test('add on an unknown account is a code-only DbWriteException', () async {
      try {
        await repo.add(_new(account: 'nope', merchant: sentinel));
        fail('expected a failure');
      } on DbWriteException catch (e) {
        expect(e.code, DbWriteException.constraintForeignKey);
        expect(e.toString(), isNot(contains(sentinel)));
      }
      expect(await repo.count(), 0);
    });

    test('add: very long merchant and note are cut to the caps', () async {
      final r = await repo.add(_new(merchant: 'م' * 500, note: 'n' * 5000));
      expect(r.merchantRaw!.runes.length, maxMerchantRunes);
      expect(r.note!.runes.length, maxNoteRunes);
    });

    test('AC2: editing an auto-captured row sets is_user_verified', () async {
      await dao.insert(
        txn(
          'sms1',
          merchant: 'Auto Merchant',
        ).copyWith(source: const Value('sms')),
      );
      final before = await repo.byId('sms1');
      expect(before!.isUserVerified, isFalse);
      expect(before.source, TxnSource.sms);

      final after = await repo.edit(
        'sms1',
        const TransactionEdit(note: Maybe('taxi')),
      );
      expect(after.isUserVerified, isTrue);
      expect(after.source, TxnSource.sms, reason: 'source is history');
      expect(after.note, 'taxi');
      expect(after.updatedAt, at(clockMs));
    });

    test('edit: category sets source user; clearing sets none', () async {
      await dao.insert(txn('a'));
      var r = await repo.edit(
        'a',
        const TransactionEdit(categoryId: Maybe(billsId)),
      );
      expect((r.categoryId, r.categorySource), (billsId, CategorySource.user));
      r = await repo.edit('a', const TransactionEdit(categoryId: Maybe(null)));
      expect((r.categoryId, r.categorySource), (null, CategorySource.none));
    });

    test('edit: amount keeps its currency pairing; time keeps the offset '
        'unless given', () async {
      await dao.insert(txn('a'));
      final r = await repo.edit(
        'a',
        TransactionEdit(
          amount: Money(kwd, 7),
          occurredAt: DateTime.utc(2026, 12, 1),
        ),
      );
      expect(r.amount, Money(kwd, 7));
      expect(r.occurredAt, DateTime.utc(2026, 12, 1));
      expect(r.occurredTzOffsetMin, 120);
    });

    test(
      'edit: a retyped merchant is searchable and the old name is not',
      () async {
        await dao.insert(
          txn('a', merchant: 'Oldname Store', merchantNorm: 'oldname store'),
        );
        await repo.edit(
          'a',
          const TransactionEdit(merchant: Maybe('Newname Shop')),
        );
        expect(await ids(text: 'Newname'), ['a']);
        expect(await ids(text: 'Oldname'), isEmpty);
      },
    );

    test(
      'edit of a missing, purged or soft-deleted row is TXN_NOT_FOUND',
      () async {
        await dao.insert(txn('a'));
        await repo.softDelete(['a']);
        for (final id in ['a', 'ghost']) {
          expect(
            await txnCode(
              repo.edit(id, const TransactionEdit(note: Maybe('x'))),
            ),
            TransactionsException.notFound,
          );
        }
        expect((await repo.byId('a', includeDeleted: true))!.note, isNull);
      },
    );

    test('edit that breaks an offset link aborts, nothing changes', () async {
      await dao.insert(txn('bill', amountMinor: 10000));
      await dao.insert(txn('refund', direction: 'refund', amountMinor: 10000));
      await OffsetLinksDao(edb.db).insert(
        link(
          'l1',
          expense: 'bill',
          source: 'refund',
          amountMinor: 6000,
          kind: 'refund',
        ),
      );
      try {
        await repo.edit(
          'bill',
          TransactionEdit(amount: egpMinor(5000), note: const Maybe('x')),
        );
        fail('expected a failure');
      } on DbWriteException catch (e) {
        expect(e.code, DbWriteException.offsetExceedsExpense);
      }
      final r = await repo.byId('bill');
      expect(
        (r!.amount, r.note, r.isUserVerified),
        (egpMinor(10000), null, false),
      );
    });
  });

  group('filters (FR-TXN-01)', () {
    setUp(() async {
      await dao.insert(txn('e1', occurredAt: t0 + 10, merchant: 'Alpha'));
      await dao.insert(
        txn(
          'i1',
          direction: 'income',
          occurredAt: t0 + 20,
          accountId: 'acc2',
        ).copyWith(
          source: const Value('sms'),
          categoryId: const Value(billsId),
        ),
      );
      await dao.insert(
        txn(
          'k1',
          occurredAt: t0 + 30,
          currency: 'KWD',
          amountMinor: 1500,
        ).copyWith(categoryId: const Value(foodId)),
      );
      await dao.insert(txn('e2', occurredAt: t0 + 40, amountMinor: 999));
    });

    test('no filter: newest first, deterministic tie-break by id', () async {
      expect(await ids(), ['e2', 'k1', 'i1', 'e1']);
      await dao.insert(txn('a-tie', occurredAt: t0 + 40));
      expect((await ids()).take(2), ['a-tie', 'e2']);
    });

    test('period is half-open [from, to)', () async {
      expect(
        await ids(
          filter: TransactionFilter(from: at(t0 + 20), to: at(t0 + 40)),
        ),
        ['k1', 'i1'],
      );
      expect(await ids(filter: TransactionFilter(from: at(t0 + 41))), isEmpty);
    });

    test('account, category, type, source, currency, status', () async {
      expect(await ids(filter: const TransactionFilter(accountIds: {'acc2'})), [
        'i1',
      ]);
      expect(
        await ids(
          filter: const TransactionFilter(categoryIds: {foodId, billsId}),
        ),
        ['k1', 'i1'],
      );
      expect(
        await ids(
          filter: const TransactionFilter(directions: {TxnDirection.income}),
        ),
        ['i1'],
      );
      expect(
        await ids(filter: const TransactionFilter(sources: {TxnSource.sms})),
        ['i1'],
      );
      expect(await ids(filter: TransactionFilter(currencies: {kwd})), ['k1']);
      expect(
        await ids(
          filter: const TransactionFilter(statuses: {TxnStatus.declined}),
        ),
        isEmpty,
      );
    });

    test('filters combine with AND and with text', () async {
      expect(
        await ids(
          filter: TransactionFilter(
            currencies: {egp},
            directions: const {TxnDirection.expense},
          ),
        ),
        ['e2', 'e1'],
      );
      expect(
        await ids(
          text: 'Alpha',
          filter: const TransactionFilter(accountIds: {'acc2'}),
        ),
        isEmpty,
      );
      expect(
        await ids(
          text: 'Alpha',
          filter: const TransactionFilter(accountIds: {'acc1'}),
        ),
        ['e1'],
      );
    });

    test('paging and count', () async {
      expect(await ids(page: const PageRequest(limit: 2)), ['e2', 'k1']);
      expect(await ids(page: const PageRequest(limit: 2, offset: 2)), [
        'i1',
        'e1',
      ]);
      expect(await ids(page: const PageRequest(limit: 0)), isEmpty);
      expect(await repo.count(), 4);
      expect(await repo.count(filter: TransactionFilter(currencies: {egp})), 3);
      expect(await repo.count(text: 'Alpha'), 1);
    });

    test('oversized filter sets and bulk calls are refused', () async {
      final big = {for (var i = 0; i <= maxIdsPerCall; i++) 'x$i'};
      expect(
        await txnCode(repo.query(filter: TransactionFilter(accountIds: big))),
        TransactionsException.invalid,
      );
      expect(
        await txnCode(repo.softDelete(big)),
        TransactionsException.invalid,
      );
      expect(
        await txnCode(repo.softDelete(const [])),
        TransactionsException.invalid,
      );
    });
  });

  group('search (FR-TXN-01)', () {
    setUp(() async {
      await dao.insert(
        txn(
          'carrefour',
          merchant: 'كارفور المعادي',
          amountMinor: 125050,
          occurredAt: t0 + 5,
        ),
      );
      await dao.insert(
        txn('fifty', merchant: 'Kiosk', amountMinor: 5000, occurredAt: t0 + 4),
      );
      await dao.insert(
        txn(
          'fiftyone',
          merchant: 'Other',
          amountMinor: 5150,
          occurredAt: t0 + 3,
        ),
      );
      await dao.insert(
        txn(
          'yen',
          merchant: 'Ramen',
          amountMinor: 50,
          currency: 'JPY',
          occurredAt: t0 + 2,
        ),
      );
      await dao.insert(
        txn('note', note: 'dinner with family', occurredAt: t0 + 1),
      );
    });

    test('partial Arabic and English text, case-insensitive', () async {
      expect(await ids(text: 'كارف'), ['carrefour']);
      expect(await ids(text: 'KIOS'), ['fifty']);
      expect(await ids(text: 'dinner'), ['note']);
    });

    test('amount text in either digit system', () async {
      expect(await ids(text: '1250.50'), ['carrefour']);
      expect(await ids(text: '١٢٥٠'), ['carrefour']);
    });

    test('1-2 digit query is an amount filter on whole units (Latin and '
        'Arabic-Indic), 0-exponent currencies included', () async {
      expect(await ids(text: '50'), ['fifty', 'yen']);
      expect(await ids(text: '٥٠'), ['fifty', 'yen']);
      expect(await ids(text: '51'), ['fiftyone']);
      expect(
        await ids(text: '5'),
        isEmpty,
        reason: 'whole units only, not prefixes',
      );
    });

    test('1-2 character name query uses the word-prefix table', () async {
      expect(await ids(text: 'ki'), ['fifty']);
      expect(await ids(text: 'كا'), ['carrefour']);
    });

    test('empty, blank, NUL and FTS syntax are matched literally', () async {
      expect(await ids(text: ''), hasLength(5));
      expect(await ids(text: '   '), hasLength(5));
      expect(await ids(text: 'ki\u0000os'), isEmpty);
      expect(await ids(text: '"'), isEmpty);
      expect(await ids(text: 'Kiosk OR Ramen'), isEmpty);
      expect(await ids(text: '*'), isEmpty);
    });

    test('soft-deleted rows are not found, restored rows are', () async {
      await repo.softDelete(['fifty']);
      expect(await ids(text: 'Kiosk'), isEmpty);
      expect(await ids(text: '50'), ['yen']);
      expect(await repo.count(text: 'Kiosk'), 0);
      await repo.restore(['fifty']);
      expect(await ids(text: 'Kiosk'), ['fifty']);
    });
  });

  group('soft delete, Undo, purge (FR-TXN-06)', () {
    test('soft delete hides, keeps the row, restore brings it back', () async {
      await dao.insert(txn('a'));
      await dao.insert(txn('b', occurredAt: t0 + 1));
      await repo.softDelete(['a', 'b', 'a']);
      expect(await ids(), isEmpty);
      expect(await repo.byId('a'), isNull);
      final gone = await repo.byId('a', includeDeleted: true);
      expect(gone!.deletedAt, at(clockMs));
      clockMs += 5000;
      await repo.restore(['a', 'b']);
      expect(await ids(), ['b', 'a']);
      expect((await repo.byId('a'))!.deletedAt, isNull);
    });

    test('a bulk delete with one unknown id changes nothing', () async {
      await dao.insert(txn('a'));
      expect(
        await txnCode(repo.softDelete(['a', 'ghost'])),
        TransactionsException.notFound,
      );
      expect(await ids(), ['a']);
    });

    test(
      'deleting twice keeps the first deleted_at and reports not found',
      () async {
        await dao.insert(txn('a'));
        await repo.softDelete(['a']);
        final first = clockMs;
        clockMs += 9999;
        expect(
          await txnCode(repo.softDelete(['a'])),
          TransactionsException.notFound,
        );
        expect(
          (await repo.byId('a', includeDeleted: true))!.deletedAt,
          at(first),
        );
      },
    );

    test('restore of a live or unknown row, all-or-none', () async {
      await dao.insert(txn('a'));
      await dao.insert(txn('b'));
      await repo.softDelete(['a']);
      expect(
        await txnCode(repo.restore(['a', 'b'])),
        TransactionsException.notDeleted,
      );
      expect(await ids(), ['b'], reason: 'a stays deleted: rolled back');
      expect(
        await txnCode(repo.restore(['ghost'])),
        TransactionsException.notFound,
      );
    });

    test('purge removes only rows deleted 30+ days ago', () async {
      for (final id in ['old', 'edge', 'recent', 'live']) {
        await dao.insert(txn(id));
      }
      const day = 24 * 3600 * 1000;
      final now = t0 + 100 * day;
      clockMs = now - 31 * day;
      await repo.softDelete(['old']);
      clockMs = now - 30 * day;
      await repo.softDelete(['edge']);
      clockMs = now - 29 * day;
      await repo.softDelete(['recent']);
      clockMs = now;

      expect(await repo.purgeExpired(), 2);
      expect(await repo.byId('old', includeDeleted: true), isNull);
      expect(await repo.byId('edge', includeDeleted: true), isNull);
      expect(await repo.byId('recent', includeDeleted: true), isNotNull);
      expect(await repo.byId('live'), isNotNull);
      expect(await repo.purgeExpired(), 0, reason: 'idempotent');
      expect(
        await txnCode(repo.restore(['old'])),
        TransactionsException.notFound,
      );
    });

    test(
      'a deleted_at in the future (clock moved back) is not purged',
      () async {
        await dao.insert(txn('a'));
        clockMs = t0 + 10 * 24 * 3600 * 1000;
        await repo.softDelete(['a']);
        clockMs = t0;
        expect(await repo.purgeExpired(), 0);
      },
    );

    test('purge cascades to links and keeps the search index sound', () async {
      await dao.insert(txn('bill', amountMinor: 10000, merchant: 'Gone Co'));
      await dao.insert(txn('refund', direction: 'refund', amountMinor: 4000));
      final links = OffsetLinksDao(edb.db);
      await links.insert(
        link(
          'l1',
          expense: 'bill',
          source: 'refund',
          amountMinor: 4000,
          kind: 'refund',
        ),
      );
      await repo.softDelete(['bill']);
      clockMs += 31 * 24 * 3600 * 1000;
      expect(await repo.purgeExpired(), 1);
      expect(await links.forExpense('bill'), isEmpty);
      expect(await ids(text: 'Gone'), isEmpty);
      for (final t in ['transactions_fts', 'transactions_fts_short']) {
        await edb.db.customStatement(
          "INSERT INTO $t ($t) VALUES ('integrity-check')",
        );
      }
    });

    test('m-4: offset sums ignore links with a soft-deleted side; Undo '
        'restores them', () async {
      await dao.insert(txn('bill', amountMinor: 10000));
      await dao.insert(txn('refund', direction: 'refund', amountMinor: 4000));
      final links = OffsetLinksDao(edb.db);
      await links.insert(
        link(
          'l1',
          expense: 'bill',
          source: 'refund',
          amountMinor: 4000,
          kind: 'refund',
        ),
      );
      expect(await links.activeLinkedToExpense('bill'), 4000);
      expect(await links.activeLinkedFromSource('refund'), 4000);

      await repo.softDelete(['refund']);
      expect(await links.activeLinkedToExpense('bill'), 0);
      expect(await links.linkedToExpense('bill'), 4000, reason: 'link kept');
      await repo.restore(['refund']);
      expect(await links.activeLinkedToExpense('bill'), 4000);

      await repo.softDelete(['bill']);
      expect(await links.activeLinkedToExpense('bill'), 0);
      expect(await links.activeLinkedFromSource('refund'), 0);
      await repo.restore(['bill']);
      expect(await links.activeLinkedFromSource('refund'), 4000);
    });
  });

  test('provider builds the repository from the open database', () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => edb.db),
        clockProvider.overrideWithValue(() => at(clockMs)),
        idGeneratorProvider.overrideWithValue(() => 'p1'),
      ],
    );
    addTearDown(container.dispose);
    final r = await container.read(transactionRepositoryProvider.future);
    expect((await r.add(_new())).id, 'p1');
  });

  test('newUuidV4 has the v4 shape and is not repeated', () {
    final re = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final seen = {for (var i = 0; i < 100; i++) newUuidV4()};
    expect(seen, hasLength(100));
    expect(seen.every(re.hasMatch), isTrue);
  });
}

NewTransaction _new({
  Money? amount,
  int tz = 120,
  String account = 'acc1',
  String? merchant,
  String? note,
}) => NewTransaction(
  accountId: account,
  direction: TxnDirection.expense,
  amount: amount ?? egpMinor(2500),
  occurredAt: DateTime.utc(2026, 11, 1),
  occurredTzOffsetMin: tz,
  merchant: merchant,
  note: note,
);
