// T-049: ReviewRepository against an encrypted database. Synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/ingestion/data/review_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ReviewRepository repo;
  var n = 0;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    n = 0;
    await db.into(db.accounts).insert(account('acc1'));
    await db.into(db.rawMessages).insert(rawMessage('raw1', hash: 1));
    await db
        .into(db.rawMessages)
        .insert(rawMessage('raw2', hash: 2)); // second message
    repo = ReviewRepository(
      db,
      clock: () => DateTime.utc(2026, 11, 13, 10),
      newId: () => 'id${++n}',
    );
  });
  tearDown(() => edb.close());

  Future<void> seed(String id, String kind, {String? raw, String? txnId}) =>
      ReviewItemsDao(db).insert(
        id: id,
        kind: kind,
        rawMessageId: raw,
        txnId: txnId,
        createdAt: t0,
      );

  Future<String> rawStatus(String id) async => (await (db.select(
    db.rawMessages,
  )..where((m) => m.id.equals(id))).getSingle()).parseStatus;

  test(
    'dismiss resolves the item and marks the raw message dismissed',
    () async {
      await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
      final out = await repo.dismiss('r1');
      expect(out.applied, isTrue);
      expect(await rawStatus('raw1'), 'dismissed');
      final row = await ReviewItemsDao(db).byId('r1');
      expect(row!.resolution, 'dismissed');
      expect(await repo.countOpen(), 0);
    },
  );

  test('a second dismiss is a no-op (one winner)', () async {
    await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
    await repo.dismiss('r1');
    expect((await repo.dismiss('r1')).applied, isFalse);
  });

  test('unknown item is REVIEW_NOT_FOUND', () async {
    expect(
      repo.dismiss('nope'),
      throwsA(
        isA<ReviewException>().having(
          (e) => e.code,
          'code',
          ReviewException.notFound,
        ),
      ),
    );
  });

  ManualTxnInput input({int minor = 25050, String cur = 'EGP'}) =>
      ManualTxnInput(
        accountId: 'acc1',
        direction: 'expense',
        amount: Money(Currency.of(cur), minor),
        occurredAt: DateTime.utc(2026, 11, 12, 8),
        tzOffsetMin: 120,
        merchant: 'Synthetic Shop',
      );

  test(
    'manual entry creates a verified transaction and parses the raw',
    () async {
      await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
      final out = await repo.resolveManually('r1', input());
      expect(out.applied, isTrue);
      final t = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(out.txnId!))).getSingle();
      expect(t.isUserVerified, 1);
      expect(t.amountMinor, 25050);
      expect(t.currency, 'EGP');
      expect(t.rawMessageId, 'raw1');
      expect(t.source, 'manual');
      expect(await rawStatus('raw1'), 'parsed');
      expect((await ReviewItemsDao(db).byId('r1'))!.resolution, 'manual');
    },
  );

  test('manual entry twice creates one transaction', () async {
    await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
    await repo.resolveManually('r1', input());
    expect((await repo.resolveManually('r1', input())).applied, isFalse);
    expect((await db.select(db.transactions).get()).length, 1);
  });

  test(
    'currency mismatch rolls back: item stays open, no transaction',
    () async {
      await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
      await expectLater(
        repo.resolveManually('r1', input(cur: 'USD')),
        throwsA(isA<ReviewException>()),
      );
      expect(await repo.countOpen(), 1);
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await rawStatus('raw1'), 'parsed'); // untouched fixture value
    },
  );

  test('zero amount is invalid', () async {
    await expectLater(
      repo.resolveManually('x', input(minor: 0)),
      throwsA(isA<ReviewException>()),
    );
  });

  test('accept suggestion verifies the linked transaction', () async {
    await db.into(db.transactions).insert(txn('t1'));
    await seed('r1', ReviewKind.lowConfidence, txnId: 't1');
    final out = await repo.acceptSuggestion('r1');
    expect(out.applied, isTrue);
    final t = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(t.isUserVerified, 1);
    expect((await ReviewItemsDao(db).byId('r1'))!.resolution, 'accepted');
  });

  test('request my bank queues a bank_request and resolves', () async {
    await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
    final out = await repo.requestMyBank(
      'r1',
      institutionName: 'Banque Synthetic',
    );
    expect(out.applied, isTrue);
    final rows = await db.select(db.outbox).get();
    expect(rows.single.kind, 'bank_request');
    expect(rows.single.payload, contains('Banque Synthetic'));
    expect(rows.single.payload, isNot(contains('body')));
    expect(await rawStatus('raw1'), 'dismissed');
    expect(await repo.countOpen(), 0);
  });

  test('request my bank refuses names with digits runs or @', () async {
    await seed('r1', ReviewKind.unrecognized, raw: 'raw1');
    for (final bad in ['Bank 123456', 'بنك ١٢٣٤٥٦', 'a@b.c', 'x', 'B' * 65]) {
      await expectLater(
        repo.requestMyBank('r1', institutionName: bad),
        throwsA(isA<ReviewException>()),
      );
    }
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await repo.countOpen(), 1);
  });

  test('request my bank is refused for suggestion kinds', () async {
    await seed('r1', ReviewKind.paydaySuggestion);
    await expectLater(
      repo.requestMyBank('r1', institutionName: 'Banque Synthetic'),
      throwsA(isA<ReviewException>()),
    );
    expect(await repo.countOpen(), 1);
  });

  test(
    'open lists oldest first, filters by kind; count stream updates',
    () async {
      await seed('a', ReviewKind.unrecognized, raw: 'raw1');
      await seed('b', ReviewKind.newSender, raw: 'raw2');
      expect((await repo.open()).length, 2);
      expect((await repo.open(kind: ReviewKind.newSender)).single.id, 'b');
      expect(await repo.watchOpenCount().first, 2);
      await repo.dismiss('a');
      expect(await repo.watchOpenCount().first, 1);
    },
  );
}
