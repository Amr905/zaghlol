// T-272 (PO 2026-11-26): a bank-counter exchange sends no SMS; the next
// balance message shows more EGP than the ledger explains. One review item
// asks "Did you exchange money?" only when another currency had income
// lately; nothing is ever created by the check. All data synthetic.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';

import '../../../core/db/financial_fixtures.dart' show account, txn;

import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';

import '../support/ingest_harness.dart';

const int day = 24 * 3600 * 1000;

void main() {
  late IngestWorld w;
  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  Future<void> usdSalary({int at = t0}) async {
    await AccountsDao(w.db).insert(
      account('usd', institution: 'ARB', last4: '9945', currency: 'USD'),
    );
    await TransactionsDao(w.db).insert(
      txn(
        'salary',
        accountId: 'usd',
        direction: 'income',
        amountMinor: 18966,
        currency: 'USD',
        occurredAt: at,
      ),
    );
  }

  Future<List<Map<String, Object?>>> jumps() async => [
    for (final r in await w.reviews())
      if ((jsonDecode(r['payload']! as String) as Map)['reason'] ==
          ReviewReason.exchangeBalanceJump)
        r,
  ];

  Future<int> txnCount() => w.count('transactions');

  test('EGP balance rises 29,700 with no credit seen, USD salary lately: '
      'ONE question with the rise; nothing created', () async {
    await usdSalary();
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    final before = await txnCount();
    await w.run([
      sms('b2', 'ZBANK: Balance EGP 30,700.00 acct *1111', rx: t0 + day),
    ]);
    final items = await jumps();
    expect(items, hasLength(1));
    final payload = jsonDecode(items.single['payload']! as String) as Map;
    expect(payload['amount'], {'minor': 2970000, 'currency': 'EGP'});
    expect(payload['accountId'], isA<String>());
    expect(items.single['kind'], ReviewKind.lowConfidence);
    expect(items.single['txn_id'], isNull);
    expect(await txnCount(), before);

    // Declined (or ignored): the next balance compares with this one, so
    // the same jump is never asked again.
    await w.db.customStatement(
      "UPDATE review_items SET resolved_at = 1, resolution = 'dismissed'",
    );
    await w.run([
      sms('b3', 'ZBANK: Balance EGP 30,700.00 acct *1111', rx: t0 + 2 * day),
    ]);
    expect(await jumps(), hasLength(1));
  });

  test('no other currency with income lately: no question', () async {
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    await w.run([
      sms('b2', 'ZBANK: Balance EGP 30,700.00 acct *1111', rx: t0 + day),
    ]);
    expect(await jumps(), isEmpty);
  });

  test('a salary older than the lookback does not count', () async {
    await usdSalary(at: t0 - 60 * day);
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    await w.run([
      sms('b2', 'ZBANK: Balance EGP 30,700.00 acct *1111', rx: t0 + day),
    ]);
    expect(await jumps(), isEmpty);
  });

  test('a rise the ledger explains (a credit seen) is not asked', () async {
    await usdSalary();
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    await w.run([
      sms('s', 'ZBANK: Salary EGP 29,700.00 acct *1111', rx: t0 + day ~/ 2),
    ]);
    await w.run([
      sms('b2', 'ZBANK: Balance EGP 30,700.00 acct *1111', rx: t0 + day),
    ]);
    expect(await jumps(), isEmpty);
  });

  test('a small rise (under 500) is not asked', () async {
    await usdSalary();
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    await w.run([
      sms('b2', 'ZBANK: Balance EGP 1,499.99 acct *1111', rx: t0 + day),
    ]);
    expect(await jumps(), isEmpty);
  });

  test('FU-366: an old jump (inbox catch-up, > 14 days) raises nothing; a '
      'recent one still asks once', () async {
    await usdSalary();
    await w.run([sms('b1', 'ZBANK: Balance EGP 1,000.00 acct *1111')]);
    w.clockMs = t0 + 30 * day;
    await w.run([
      sms(
        'b2',
        'ZBANK: Balance EGP 30,700.00 acct *1111',
        rx: t0 + day,
        origin: MessageOrigin.inboxScan,
      ),
    ]);
    expect(await jumps(), isEmpty);

    w.clockMs = t0 + 31 * day;
    await w.run([
      sms('b3', 'ZBANK: Balance EGP 60,700.00 acct *1111', rx: t0 + 30 * day),
    ]);
    expect(await jumps(), hasLength(1));
  });

  test('FU-366: the store reads the stored rate (direct or inverse) for '
      'the threshold; none stored gives null', () async {
    await AccountsDao(w.db).insert(account('usd', currency: 'USD'));
    await w.db.customStatement(
      'INSERT INTO account_balances (account_id, currency, balance_minor, '
      "as_of) VALUES ('usd', 'USD', 10000, $t0)",
    );
    final store = DriftIngestStore(w.db);
    Future<int?> rate() async => (await store.balanceJumpFacts(
      accountId: 'usd',
      currency: 'USD',
      asOfMs: t0 + day,
      lookbackMs: 45 * day,
    ))!.egpPerUnitE9;

    expect(await rate(), isNull);
    await w.db.customStatement(
      'INSERT INTO fx_rates (base, quote, rate_e9, as_of) '
      "VALUES ('EGP', 'USD', 20000000, $t0)",
    ); // 1 EGP = 0.02 USD
    expect(await rate(), 50000000000); // 1 USD = 50 EGP
    await w.db.customStatement(
      'INSERT INTO fx_rates (base, quote, rate_e9, as_of) '
      "VALUES ('USD', 'EGP', 48000000000, $t0)",
    );
    expect(await rate(), 48000000000); // direct row wins
  });
}
