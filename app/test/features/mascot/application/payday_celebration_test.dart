// T-294: one celebration per salary transaction, any currency, SMS or cash.

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/budget/application/budget_providers.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol/features/salary/application/salary_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _today = CivilDate(2026, 11, 25);

SalaryEntry _e(String id, CivilDate a, {bool captured = true}) =>
    SalaryEntry(txnId: id, captured: captured, anchor: a);

TransactionRecord _txn(
  String id,
  Money amount, {
  TxnDirection dir = TxnDirection.income,
}) => TransactionRecord(
  id: id,
  accountId: 'a1',
  source: TxnSource.manual,
  direction: dir,
  status: TxnStatus.posted,
  amount: amount,
  occurredAt: DateTime.utc(2026, 11, 25, 12),
  occurredTzOffsetMin: 120,
  categorySource: CategorySource.none,
  isUserVerified: false,
  isInternal: false,
  createdAt: DateTime.utc(2026, 11, 25),
  updatedAt: DateTime.utc(2026, 11, 25),
);

class _Txns implements TransactionRepository {
  _Txns(this.rows);
  final Map<String, TransactionRecord> rows;

  @override
  Future<TransactionRecord?> byId(
    String id, {
    bool includeDeleted = false,
  }) async => rows[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Today extends TodayNotifier {
  @override
  CivilDate build() => _today;
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    addTearDown(db.close);
    repo = SettingsRepository(SettingsDao(db));
  });

  /// A fresh container = an app start over the same stored settings.
  Future<PaydayCelebration?> start(
    SalaryState state,
    Map<String, TransactionRecord> txns,
  ) async {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        settingsRepositoryProvider.overrideWith((ref) async => repo),
        salaryStateProvider.overrideWith((ref) => Stream.value(state)),
        todayProvider.overrideWith(_Today.new),
        transactionRepositoryProvider.overrideWith((ref) async => _Txns(txns)),
      ],
    );
    addTearDown(c.dispose);
    // Riverpod pauses a stream provider nobody listens to.
    c.listen(salaryStateProvider, (_, _) {});
    c.listen(paydayCelebrationProvider, (_, _) {});
    await c.read(salaryStateProvider.future);
    return c.read(paydayCelebrationProvider.future);
  }

  final egp = Currency.of('EGP');
  final usd = Currency.of('USD');

  test('new SMS salary celebrates once; the next start does not', () async {
    final state = SalaryState(entries: [_e('s1', _today)]);
    final txns = {'s1': _txn('s1', Money(egp, 2970000))};
    final first = await start(state, txns);
    expect(first?.txnId, 's1');
    expect(first?.amount, Money(egp, 2970000));
    expect(await start(state, txns), isNull);
  });

  test('old salary found by the first scan: silent, never later', () async {
    final state = SalaryState(entries: [_e('s1', CivilDate(2026, 11, 1))]);
    final txns = {'s1': _txn('s1', Money(egp, 100))};
    expect(await start(state, txns), isNull);
    expect(await repo.get(Settings.mascotPaydayCelebratedTxns), ['s1']);
    expect(await start(state, txns), isNull);
  });

  test('cash salary (hand-entered entry) celebrates', () async {
    final state = SalaryState(entries: [_e('c1', _today, captured: false)]);
    final r = await start(state, {'c1': _txn('c1', Money(egp, 500000))});
    expect(r?.txnId, 'c1');
  });

  test('cash income not flagged as a salary has no entry: nothing', () async {
    final r = await start(SalaryState.empty, {
      'c1': _txn('c1', Money(egp, 500000)),
    });
    expect(r, isNull);
  });

  test('USD salary celebrates in USD', () async {
    final state = SalaryState(entries: [_e('u1', _today)]);
    final r = await start(state, {'u1': _txn('u1', Money(usd, 100000))});
    expect(r?.amount, Money(usd, 100000));
    expect(r?.amount.currency, usd);
  });

  test('a deleted or non-income row is marked silently', () async {
    final state = SalaryState(entries: [_e('x1', _today)]);
    expect(await start(state, {}), isNull);
    expect(await start(state, {}), isNull);
  });

  test('the next payday celebrates again', () async {
    final first = SalaryState(entries: [_e('s1', _today)]);
    final txns = {
      's1': _txn('s1', Money(egp, 1)),
      's2': _txn('s2', Money(egp, 2)),
    };
    expect((await start(first, txns))?.txnId, 's1');
    final both = SalaryState(entries: [_e('s1', _today), _e('s2', _today)]);
    expect((await start(both, txns))?.txnId, 's2');
  });

  test('legacy mark: salaries up to that day never celebrate', () async {
    await repo.set(Settings.mascotPaydayCelebrated, _today.epochDay);
    final state = SalaryState(entries: [_e('s1', _today)]);
    expect(await start(state, {'s1': _txn('s1', Money(egp, 1))}), isNull);
  });

  test('pure decision: fresh newest first, stale excluded', () {
    final d = paydayDecision(
      state: SalaryState(
        entries: [
          _e('a', CivilDate(2026, 11, 22)),
          _e('b', _today),
          _e('old', CivilDate(2026, 9, 1)),
          _e('seen', _today),
        ],
      ),
      celebrated: {'seen'},
      legacyMarkEpochDay: null,
      today: _today,
    );
    expect(d.fresh.map((e) => e.txnId), ['b', 'a']);
    expect(d.all.map((e) => e.txnId), ['a', 'b', 'old']);
  });
}
