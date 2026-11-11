// T-018: the batch-B DAOs other than the catalog (design note §5) on an
// encrypted database, in both executors: categories, merchant rules,
// budgets (Money, one currency per budget), fired alerts (exactly one
// winner, also across two connections), cycle summaries (per currency) and
// recurring items. Refused writes carry codes only. All data synthetic.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/budgets_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/cycle_summaries_dao.dart';
import 'package:zaghlol/core/db/daos/fired_alerts_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart';
import 'package:zaghlol/core/db/daos/recurring_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/core/db/money_columns.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'db_open_harness.dart' show keyOf;
import 'financial_fixtures.dart';

const String sentinel = 'T018SENTINEL';

final Currency egp = Currency.of('EGP');
final Currency usd = Currency.of('USD');
final Currency kwd = Currency.of('KWD');

Money egpMinor(int minor) => Money(egp, minor);

Future<String?> codeOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on DbWriteException catch (e) {
    return e.code;
  }
}

Future<void> seedCategories(CategoriesDao dao) async {
  await dao.upsertSystem(
    code: 'food',
    nameAr: 'أكل',
    nameEn: 'Food',
    icon: 'food',
    color: '#0F7A55',
    bucket: 'needs',
    sort: 2,
  );
  await dao.upsertSystem(
    code: 'bills',
    nameAr: 'فواتير',
    nameEn: 'Bills',
    icon: 'bill',
    color: '#4D695C',
    bucket: 'obligations',
    sort: 1,
  );
}

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late AppDatabase db;

      setUp(() async {
        edb = await EncryptedDb.open(background: background);
        db = edb.db;
        await seedCategories(CategoriesDao(db));
      });

      tearDown(() => edb.close());

      group('categories', () {
        test('system upsert: id sys:<code>, update in place keeps archive '
            'and references', () async {
          final dao = CategoriesDao(db);
          final food = await dao.bySystemCode('food');
          expect(
            (food!.id, food.isCustom, food.isArchived),
            ('sys:food', 0, 0),
          );
          await AccountsDao(db).insert(account('acc1'));
          await TransactionsDao(db)
              .insert(txn('t1').copyWith(categoryId: const Value('sys:food')));
          expect(await dao.setArchived('sys:food', archived: true), 1);
          await dao.upsertSystem(
            code: 'food',
            nameAr: 'أكل وشرب',
            nameEn: 'Food & drink',
            icon: 'food',
            color: '#0F7A55',
            bucket: 'needs',
            sort: 3,
          );
          final again = await dao.byId('sys:food');
          expect(
            (again!.nameEn, again.sort, again.isArchived),
            ('Food & drink', 3, 1),
          );
          expect(
            (await TransactionsDao(db).byId('t1'))!.categoryId,
            'sys:food',
          );
        });

        test('active: archived hidden, ordered by sort', () async {
          final dao = CategoriesDao(db);
          await dao.insert(
            CategoriesCompanion.insert(
              id: 'cust1',
              nameAr: 'هدايا',
              nameEn: 'Gifts',
              icon: 'gift',
              color: '#FFB86B',
              bucket: 'giving',
              sort: 0,
              isCustom: const Value(1),
            ),
          );
          await dao.setArchived('sys:bills', archived: true);
          expect(
            [for (final c in await dao.active()) c.id],
            ['cust1', 'sys:food'],
          );
          await dao.setArchived('sys:bills', archived: false);
          expect(
            [for (final c in await dao.active()) c.id],
            ['cust1', 'sys:bills', 'sys:food'],
          );
        });

        test('a bad bucket is a code-only error', () async {
          expect(
            await codeOf(
              CategoriesDao(db).upsertSystem(
                code: 'x$sentinel',
                nameAr: sentinel,
                nameEn: sentinel,
                icon: 'i',
                color: '#000000',
                bucket: 'fun',
                sort: 1,
              ),
            ),
            DbWriteException.constraintCheck,
          );
        });
      });

      group('merchant rules', () {
        MerchantRulesCompanion rule(String id, String value, String cat) =>
            MerchantRulesCompanion.insert(
              id: id,
              matchKind: RuleMatchKind.merchantNorm,
              matchValue: value,
              categoryId: cat,
              createdAt: t0,
            );

        test('upsert by (kind, value) re-points the rule; find, apply, '
            'delete', () async {
          final dao = MerchantRulesDao(db);
          await dao.upsert(rule('r1', 'koshary el tahrir', 'sys:food'));
          await dao.upsert(rule('r2', 'koshary el tahrir', 'sys:bills'));
          final found = await dao.find(
            RuleMatchKind.merchantNorm,
            'koshary el tahrir',
          );
          expect((found!.id, found.categoryId), ('r1', 'sys:bills'));
          expect(await dao.all(), hasLength(1));
          expect(await dao.markApplied('r1', at: t0 + 5), 1);
          expect(
            (await dao.find(
              RuleMatchKind.merchantNorm,
              'koshary el tahrir',
            ))!.lastAppliedAt,
            t0 + 5,
          );
          expect(await dao.deleteById('r1'), 1);
          expect(await dao.all(), isEmpty);
        });

        test('a non-canonical merchant key or unknown category is refused '
            'with a code only', () async {
          final dao = MerchantRulesDao(db);
          final e = await codeOf(dao.upsert(rule('r1', sentinel, 'sys:food')));
          expect(e, DbWriteException.constraintCheck);
          expect(
            await codeOf(dao.upsert(rule('r2', 'shop', 'nope'))),
            DbWriteException.constraintForeignKey,
          );
        });
      });

      group('budgets', () {
        test('insert with Money; limit and thresholds read back', () async {
          final dao = BudgetsDao(db);
          await dao.insert(
            id: 'b1',
            categoryId: 'sys:food',
            limit: egpMinor(500000),
            period: BudgetPeriod.cycle,
            thresholds: [100, 50, 80],
            createdAt: t0,
          );
          final row = (await dao.byId('b1'))!;
          expect(row.limit, egpMinor(500000));
          expect(budgetThresholdsOf(row), [50, 80, 100]);
          expect(row.rollover, 0);
        });

        test('KWD (exponent 3) and the 2^53 − 1 bound', () async {
          final dao = BudgetsDao(db);
          await dao.insert(
            id: 'k1',
            limit: Money(kwd, 1500),
            period: BudgetPeriod.annual,
            createdAt: t0,
          );
          expect((await dao.byId('k1'))!.limit, Money(kwd, 1500));
          await dao.updateLimit('k1', Money(kwd, maxMinor));
          expect((await dao.byId('k1'))!.limitMinor, maxMinor);
          expect(budgetThresholdsOf((await dao.byId('k1'))!), [80, 100]);
        });

        test('a limit in another currency is refused and changes '
            'nothing', () async {
          final dao = BudgetsDao(db);
          await dao.insert(
            id: 'b1',
            limit: egpMinor(1000),
            period: BudgetPeriod.cycle,
            createdAt: t0,
          );
          await expectLater(
            dao.updateLimit('b1', Money(usd, 999)),
            throwsA(isA<CurrencyMismatch>()),
          );
          expect((await dao.byId('b1'))!.limit, egpMinor(1000));
          expect(await dao.updateLimit('nope', egpMinor(1)), 0);
          expect(await dao.updateLimit('b1', egpMinor(2000)), 1);
          expect((await dao.byId('b1'))!.limit, egpMinor(2000));
        });

        test('one overall budget per currency and period', () async {
          final dao = BudgetsDao(db);
          Future<void> overall(String id, Money limit) => dao.insert(
            id: id,
            limit: limit,
            period: BudgetPeriod.cycle,
            createdAt: t0,
          );
          await overall('o1', egpMinor(1));
          expect(
            await codeOf(overall('o2', egpMinor(2))),
            DbWriteException.constraintUnique,
          );
          await overall('o3', Money(usd, 2));
          expect([for (final b in await dao.inCurrency(egp)) b.id], ['o1']);
        });

        test('bad thresholds are refused before SQL without echoing '
            'them', () async {
          final dao = BudgetsDao(db);
          for (final bad in [
            <int>[],
            [0],
            [1001],
            [80, 80],
            List.generate(11, (i) => i + 1),
          ]) {
            Object? caught;
            try {
              await dao.insert(
                id: 'b1',
                limit: egpMinor(1),
                period: BudgetPeriod.cycle,
                thresholds: bad,
                createdAt: t0,
              );
            } on Object catch (e) {
              caught = e;
            }
            expect(caught, isA<ArgumentError>(), reason: '$bad');
          }
          expect(await dao.byId('b1'), isNull);
          await dao.insert(
            id: 'b1',
            limit: egpMinor(1),
            period: BudgetPeriod.cycle,
            createdAt: t0,
          );
          expect(await dao.setThresholds('b1', [90]), 1);
          expect(budgetThresholdsOf((await dao.byId('b1'))!), [90]);
          expect(await dao.deleteById('b1'), 1);
        });
      });

      group('fired alerts', () {
        Future<bool> fire(FiredAlertsDao dao, {int threshold = 80}) =>
            dao.markFired(
              kind: 'budget_threshold',
              subjectId: 'b1',
              periodKey: '2026-11-25',
              threshold: threshold,
              at: t0,
            );

        test('fires once per key; an ignored insert after another insert '
            'is still "not fired"', () async {
          final dao = FiredAlertsDao(db);
          expect(await fire(dao), isTrue);
          expect(await fire(dao, threshold: 100), isTrue);
          // The last insert id now names the 100 row: the answer must come
          // from the changed-row count.
          expect(await fire(dao), isFalse);
          expect(await fire(dao, threshold: 100), isFalse);
          expect(
            await dao.hasFired(
              kind: 'budget_threshold',
              subjectId: 'b1',
              periodKey: '2026-11-25',
              threshold: 80,
            ),
            isTrue,
          );
          expect(await dao.deleteForSubject('b1'), 2);
          expect(await fire(dao), isTrue);
        });

        test('ten concurrent callers: exactly one wins', () async {
          final dao = FiredAlertsDao(db);
          final results = await Future.wait([
            for (var i = 0; i < 10; i++) fire(dao),
          ]);
          expect(results.where((r) => r), hasLength(1));
        });

        test('two connections on the same file (UI + background engine): '
            'exactly one wins', () async {
          driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
          final other = AppDatabase(
            openEncryptedExecutor(
              edb.world.mainFile,
              keyOf(61),
              inBackground: !background,
            ),
            validateSchema: false,
          );
          addTearDown(other.close);
          final results = await Future.wait([
            for (var i = 0; i < 6; i++)
              fire(FiredAlertsDao(i.isEven ? db : other)),
          ]);
          expect(results.where((r) => r), hasLength(1));
        });
      });

      group('cycle summaries', () {
        test('per currency; upsert replaces; by-category in Money', () async {
          final dao = CycleSummariesDao(db);
          await dao.upsert(
            cycleStart: '2026-11-25',
            income: egpMinor(1000000),
            spend: egpMinor(250000),
            byCategoryMinor: {'sys:food': 250000},
            computedAt: t0,
          );
          await dao.upsert(
            cycleStart: '2026-11-25',
            income: Money(usd, 0),
            spend: Money(usd, 2000),
            byCategoryMinor: {'sys:bills': 2000},
            computedAt: t0,
          );
          await dao.upsert(
            cycleStart: '2026-11-25',
            income: egpMinor(1000000),
            spend: egpMinor(-500),
            byCategoryMinor: const {},
            computedAt: t0 + 1,
          );
          final e = (await dao.find(cycleStart: '2026-11-25', currency: egp))!;
          expect((e.income, e.spend), (egpMinor(1000000), egpMinor(-500)));
          expect(cycleSpendByCategoryOf(e), isEmpty);
          final u = (await dao.find(cycleStart: '2026-11-25', currency: usd))!;
          expect(cycleSpendByCategoryOf(u), {'sys:bills': Money(usd, 2000)});
          expect(await dao.clear(), 2);
        });

        test('mixed currencies are refused before SQL', () async {
          await expectLater(
            CycleSummariesDao(db).upsert(
              cycleStart: '2026-11-25',
              income: egpMinor(1),
              spend: Money(usd, 1),
              byCategoryMinor: const {},
              computedAt: t0,
            ),
            throwsA(isA<CurrencyMismatch>()),
          );
        });

        test('an invalid cycle date is a code-only error', () async {
          expect(
            await codeOf(
              CycleSummariesDao(db).upsert(
                cycleStart: '2026-02-30',
                income: egpMinor(1),
                spend: egpMinor(1),
                byCategoryMinor: const {},
                computedAt: t0,
              ),
            ),
            DbWriteException.constraintCheck,
          );
        });
      });

      group('recurring', () {
        RecurringItemsCompanion item(String id, {String? due}) =>
            RecurringItemsCompanion.insert(
              id: id,
              kind: 'subscription',
              status: 'active',
              name: 'Synthetic $id',
              amountMinor: 0,
              currency: 'XXX',
              cadence: 'monthly',
              nextDueDate: Value(due),
              createdAt: t0,
            ).withAmount(egpMinor(9900));

        test('items with Money, due list, occurrences, cascade', () async {
          final dao = RecurringDao(db);
          await dao.insertItem(item('a', due: '2026-12-01'));
          await dao.insertItem(item('b', due: '2026-11-20'));
          await dao.insertItem(item('c', due: '2027-01-01'));
          expect((await dao.itemById('a'))!.amount, egpMinor(9900));
          expect(
            [for (final r in await dao.activeDueBy('2026-12-01')) r.id],
            ['b', 'a'],
          );
          expect(
            await dao.updateItem(
              'b',
              const RecurringItemsCompanion(status: Value('dismissed')),
            ),
            1,
          );
          expect(
            [for (final r in await dao.activeDueBy('2026-12-01')) r.id],
            ['a'],
          );
          await dao.upsertOccurrence(
            RecurringOccurrencesCompanion.insert(
              itemId: 'a',
              dueDate: '2026-12-01',
            ),
          );
          await dao.upsertOccurrence(
            RecurringOccurrencesCompanion.insert(
              itemId: 'a',
              dueDate: '2026-12-01',
              paidAt: const Value(t0),
            ),
          );
          final occ = await dao.occurrencesOf('a');
          expect(
            [for (final o in occ) (o.dueDate, o.paidAt)],
            [('2026-12-01', t0)],
          );
          expect(await dao.deleteItem('a'), 1);
          expect(await dao.occurrencesOf('a'), isEmpty);
        });

        test('custom cadence without days is a code-only error', () async {
          expect(
            await codeOf(
              RecurringDao(db).insertItem(
                item('x').copyWith(
                  cadence: const Value('custom_days'),
                  name: const Value(sentinel),
                ),
              ),
            ),
            DbWriteException.constraintCheck,
          );
        });
      });
    });
  }
}
