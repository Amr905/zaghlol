// FU-157b: Ask's "budget left" (categoryDonut total) must equal the budget
// screen's figure (CycleRepository totals) for the same cycle, category and
// currency, on a seeded database. Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/offset_links_dao.dart';
import 'package:zaghlol/features/budget/data/cycle_repository.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/insights/data/chart_repository.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../core/db/financial_fixtures.dart';

int at(int d, [int m = 11]) =>
    DateTime.utc(2026, m, d, 10).millisecondsSinceEpoch;

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  final schedule = PaydaySchedule.single(25);
  final cycle = schedule.cycleOn(CivilDate(2026, 11, 10)); // 25 Oct - 24 Nov

  Future<void> add(
    String id, {
    int amount = 1000,
    String direction = 'expense',
    String status = 'posted',
    String currency = 'EGP',
    int? when,
    bool internal = false,
    bool deleted = false,
    String? category,
  }) => db
      .into(db.transactions)
      .insert(
        txn(
          id,
          direction: direction,
          amountMinor: amount,
          currency: currency,
          occurredAt: when ?? at(3),
        ).copyWith(
          status: Value(status),
          isInternal: Value(internal ? 1 : 0),
          deletedAt: Value(deleted ? t0 : null),
          categoryId: Value(category),
        ),
      );

  setUp(() async {
    edb = await EncryptedDb.open(background: false);
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1'));
    for (final id in ['sys:groceries', 'sys:dining']) {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              nameAr: id,
              nameEn: id,
              icon: 'x',
              color: '#000000',
              bucket: 'needs',
              sort: 0,
            ),
          );
    }
  });
  tearDown(() => edb.close());

  test('donut total equals cycle spend, overall and per category', () async {
    await add('a', amount: 1000, category: 'sys:groceries');
    await add('b', amount: 500, status: 'declined');
    await add('c', amount: 500, status: 'reversed');
    await add('d', amount: 500, internal: true);
    await add('e', amount: 500, deleted: true);
    await add('p', amount: 200, status: 'pending', category: 'sys:dining');
    await add('f', amount: 50, direction: 'fee');
    await add('t', amount: 70, direction: 'transfer_out');
    await add('i', amount: 9000, direction: 'income');
    await add('r', amount: 300, direction: 'refund');
    await add('g', amount: 4000, currency: 'GBP');
    await add('x', amount: 800, category: 'sys:groceries', when: at(24));
    await add('outside', amount: 999, when: at(25)); // next cycle
    await add('prev', amount: 777, when: at(24, 10)); // previous cycle
    await add('src', amount: 600, direction: 'transfer_in');
    await add('shared', amount: 2000, category: 'sys:dining');
    await OffsetLinksDao(db)
        .insert(link('l1', expense: 'shared', source: 'src', amountMinor: 600));

    final cycles = CycleRepository(
      db,
      nowUtcMs: () => at(10),
      zone: const FixedLocalZone(120),
    );
    final charts = ChartRepository(db);
    final totals = await cycles.totals(cycle);
    for (final code in ['EGP', 'GBP']) {
      final c = Currency.of(code);
      final donut = await charts.categoryDonut(
        ChartPeriod.cycle(cycle),
        ChartFilter(currency: c),
      );
      final ask = donut is ChartReady<CategoryDonut>
          ? donut.data.total.minor
          : 0;
      expect(ask, totals[c]!.spend.minor, reason: '$code overall');
      if (donut is ChartReady<CategoryDonut>) {
        for (final s in donut.data.slices) {
          final key = s.categoryId ?? CycleTotals.noCategory;
          expect(
            s.amount.minor,
            totals[c]!.byCategoryMinor[key],
            reason: '$code $key',
          );
        }
      }
    }
  });
}
