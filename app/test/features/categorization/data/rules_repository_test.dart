// T-074: the merchant rules repository on an encrypted database, plus a
// two-connection concurrency group (UI engine + background engine, pattern
// of T-045). Acceptance criteria are named in the test titles. All data
// synthetic.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/encrypted_open.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol/features/categorization/domain/merchant_rule.dart';

import '../../../core/db/db_open_harness.dart' show keyOf;
import '../../../core/db/financial_fixtures.dart';

const String foodId = 'sys:food';
const String billsId = 'sys:bills';
const String sentinel = 'T074SENTINEL';

Future<String?> ruleCode(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on RulesException catch (e) {
    expect(e.toString(), isNot(contains(sentinel)));
    return e.code;
  }
}

void main() {
  for (final background in [true, false]) {
    group(background ? 'background' : 'foreground', () {
      late EncryptedDb edb;
      late AppDatabase other;
      late DriftRulesRepository repo;
      late DriftRulesRepository repoB;
      late TransactionsDao txns;
      var clockMs = t0 + 5000;
      var nextId = 0;

      DriftRulesRepository make(AppDatabase db, String tag) =>
          DriftRulesRepository(
            MerchantRulesDao(db),
            CategoriesDao(db),
            clock: () =>
                DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
            newId: () => '$tag${nextId++}',
          );

      Future<void> put(
        String id, {
        String? norm,
        String? counterparty,
        int? catalogId,
        String source = 'none',
        String? category,
        bool verified = false,
        bool internal = false,
        bool deleted = false,
      }) async {
        await txns.insert(
          txn(id, merchantNorm: norm, counterparty: counterparty).copyWith(
            catalogMerchantId: Value(catalogId),
            categorySource: Value(source),
            categoryId: Value(category),
            isUserVerified: Value(verified ? 1 : 0),
            isInternal: Value(internal ? 1 : 0),
            deletedAt: Value(deleted ? t0 : null),
          ),
        );
      }

      Future<(String?, String)> state(String id) async {
        final r = await txns.byId(id);
        return (r!.categoryId, r.categorySource);
      }

      setUp(() async {
        clockMs = t0 + 5000;
        nextId = 0;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        edb = await EncryptedDb.open(background: background);
        other = AppDatabase(
          openEncryptedExecutor(
            edb.world.mainFile,
            keyOf(61),
            inBackground: !background,
          ),
          validateSchema: false,
        );
        repo = make(edb.db, 'a');
        repoB = make(other, 'b');
        txns = TransactionsDao(edb.db);
        await AccountsDao(edb.db).insert(account('acc1'));
        final cats = CategoriesDao(edb.db);
        for (final (code, sort, bucket) in [
          ('food', 1, 'needs'),
          ('bills', 2, 'obligations'),
        ]) {
          await cats.upsertSystem(
            code: code,
            nameAr: 'ا',
            nameEn: code,
            icon: 'i',
            color: '#0F7A55',
            bucket: bucket,
            sort: sort,
          );
        }
      });

      tearDown(() async {
        await other.close();
        await edb.close();
      });

      group('save / list / edit / delete', () {
        test('save creates a rule; same key updates it in place', () async {
          final a = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'koshary el tahrir',
            categoryId: foodId,
          );
          expect(a.categoryId, foodId);
          expect(a.lastAppliedAt, isNull);
          clockMs += 1000;
          final b = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'koshary el tahrir',
            categoryId: billsId,
          );
          expect(b.id, a.id);
          expect(b.categoryId, billsId);
          expect(b.createdAt, a.createdAt);
          expect(await repo.list(), hasLength(1));
        });

        test(
          'values are validated per kind; errors never echo input',
          () async {
            for (final (kind, value) in [
              (RuleMatchKind.merchantNorm, 'Bad Key$sentinel'),
              (RuleMatchKind.merchantNorm, ''),
              (RuleMatchKind.merchantNorm, 'two  spaces'),
              (RuleMatchKind.catalogMerchant, '0'),
              (RuleMatchKind.catalogMerchant, '012'),
              (RuleMatchKind.catalogMerchant, '12345678901'),
              (RuleMatchKind.catalogMerchant, '١٢'),
              (RuleMatchKind.counterparty, ''),
              (RuleMatchKind.counterparty, 'a\u0000$sentinel'),
              (RuleMatchKind.counterparty, 'x' * 129),
            ]) {
              expect(
                await ruleCode(
                  repo.save(kind: kind, value: value, categoryId: foodId),
                ),
                RulesException.invalid,
                reason: '$kind',
              );
            }
            expect(await repo.list(), isEmpty);
            // Boundary values are accepted.
            await repo.save(
              kind: RuleMatchKind.counterparty,
              value: 'x' * 128,
              categoryId: foodId,
            );
            await repo.save(
              kind: RuleMatchKind.catalogMerchant,
              value: '1234567890',
              categoryId: foodId,
            );
          },
        );

        test('unknown or archived category is refused', () async {
          expect(
            await ruleCode(
              repo.save(
                kind: RuleMatchKind.merchantNorm,
                value: 'abc',
                categoryId: 'sys:nope',
              ),
            ),
            RulesException.categoryUnavailable,
          );
          await CategoriesDao(edb.db).setArchived(billsId, archived: true);
          expect(
            await ruleCode(
              repo.save(
                kind: RuleMatchKind.merchantNorm,
                value: 'abc',
                categoryId: billsId,
              ),
            ),
            RulesException.categoryUnavailable,
          );
        });

        test('changeCategory and delete; missing rule is reported', () async {
          final r = await repo.save(
            kind: RuleMatchKind.counterparty,
            value: 'user@bank',
            categoryId: foodId,
          );
          expect(
            (await repo.changeCategory(r.id, billsId)).categoryId,
            billsId,
          );
          expect(
            await ruleCode(repo.changeCategory('missing', foodId)),
            RulesException.notFound,
          );
          expect(await repo.delete(r.id), isTrue);
          expect(await repo.delete(r.id), isFalse);
          expect(await repo.list(), isEmpty);
        });
      });

      group('rule beats catalog (BR-CAT-01)', () {
        test('match prefers a rule: counterparty, norm, catalog', () async {
          await repo.save(
            kind: RuleMatchKind.catalogMerchant,
            value: '7',
            categoryId: foodId,
          );
          expect(
            (await repo.match(
              merchantNorm: 'zzz',
              catalogMerchantId: 7,
            ))?.categoryId,
            foodId,
          );
          await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'zzz',
            categoryId: billsId,
          );
          expect(
            (await repo.match(
              merchantNorm: 'zzz',
              catalogMerchantId: 7,
            ))?.categoryId,
            billsId,
          );
          await repo.save(
            kind: RuleMatchKind.counterparty,
            value: '01000000000',
            categoryId: foodId,
          );
          expect(
            (await repo.match(
              counterparty: '01000000000',
              merchantNorm: 'zzz',
              catalogMerchantId: 7,
            ))?.categoryId,
            foodId,
          );
          expect(await repo.match(merchantNorm: 'other'), isNull);
          expect(await repo.match(merchantNorm: 'Not Canonical'), isNull);
          expect(await repo.match(), isNull);
        });

        test(
          'apply-to-past replaces a catalog category with the rule',
          () async {
            await put(
              't1',
              norm: 'carrefour',
              source: 'catalog',
              category: billsId,
            );
            final r = await repo.save(
              kind: RuleMatchKind.merchantNorm,
              value: 'carrefour',
              categoryId: foodId,
            );
            expect(await repo.applyToPast(r.id), 1);
            expect(await state('t1'), (foodId, 'user_rule'));
          },
        );
      });

      group('apply to past (A-13)', () {
        test('recategorizes the chosen transactions only', () async {
          for (final id in ['t1', 't2', 't3']) {
            await put(id, norm: 'carrefour');
          }
          await put('other', norm: 'spinneys');
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          // Saving alone changes no past row.
          expect(await state('t1'), (null, 'none'));
          expect(await repo.countPastMatches(r.id), 3);
          expect(await repo.pastMatchIds(r.id), hasLength(3));

          clockMs += 1000;
          expect(await repo.applyToPast(r.id, transactionIds: {'t1', 't3'}), 2);
          expect(await state('t1'), (foodId, 'user_rule'));
          expect(await state('t3'), (foodId, 'user_rule'));
          expect(await state('t2'), (null, 'none'));
          expect(await state('other'), (null, 'none'));
          expect(await repo.countPastMatches(r.id), 1);
          final updated = await txns.byId('t1');
          expect(updated!.updatedAt, clockMs);
          expect(
            (await repo.list()).single.lastAppliedAt,
            DateTime.fromMillisecondsSinceEpoch(clockMs, isUtc: true),
          );
        });

        test(
          'ids outside the match set, and empty choice, change nothing',
          () async {
            await put('t1', norm: 'carrefour');
            await put('other', norm: 'spinneys');
            final r = await repo.save(
              kind: RuleMatchKind.merchantNorm,
              value: 'carrefour',
              categoryId: foodId,
            );
            expect(await repo.applyToPast(r.id, transactionIds: {'other'}), 0);
            expect(await repo.applyToPast(r.id, transactionIds: {}), 0);
            expect(await state('other'), (null, 'none'));
            expect(await state('t1'), (null, 'none'));
            expect(
              await ruleCode(
                repo.applyToPast(
                  r.id,
                  transactionIds: {for (var i = 0; i < 1001; i++) 'x$i'},
                ),
              ),
              RulesException.invalid,
            );
          },
        );

        test('never touches user edits, verified, deleted, internal or '
            'other-rule rows', () async {
          await put(
            'user',
            norm: 'carrefour',
            source: 'user',
            category: billsId,
          );
          await put('ver', norm: 'carrefour', verified: true);
          await put('del', norm: 'carrefour', deleted: true);
          await put('int', norm: 'carrefour', internal: true);
          await put(
            'rule2',
            norm: 'carrefour',
            source: 'user_rule',
            category: billsId,
          );
          await put(
            'same',
            norm: 'carrefour',
            source: 'catalog',
            category: foodId,
          );
          await put('ok', norm: 'carrefour', source: 'heuristic');
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          expect(await repo.countPastMatches(r.id), 1);
          expect(
            await repo.applyToPast(
              r.id,
              transactionIds: {'user', 'ver', 'del', 'int', 'rule2', 'same'},
            ),
            0,
          );
          expect(await repo.applyToPast(r.id), 1);
          expect(await state('user'), (billsId, 'user'));
          expect(await state('rule2'), (billsId, 'user_rule'));
          expect(await state('same'), (foodId, 'catalog'));
          expect(await state('ok'), (foodId, 'user_rule'));
          expect((await txns.byId('ver'))!.categoryId, isNull);
          expect((await txns.byId('del'))!.categoryId, isNull);
          expect((await txns.byId('int'))!.categoryId, isNull);
        });

        test(
          'counterparty and catalog merchant kinds match their column',
          () async {
            await put('c1', counterparty: 'user@bank');
            await put('c2', counterparty: 'USER@bank');
            await put('m1', catalogId: 42);
            await put('m2', catalogId: 4);
            final c = await repo.save(
              kind: RuleMatchKind.counterparty,
              value: 'user@bank',
              categoryId: billsId,
            );
            final m = await repo.save(
              kind: RuleMatchKind.catalogMerchant,
              value: '42',
              categoryId: foodId,
            );
            expect(await repo.applyToPast(c.id), 1);
            expect(await repo.applyToPast(m.id), 1);
            expect(await state('c1'), (billsId, 'user_rule'));
            expect(await state('c2'), (null, 'none'));
            expect(await state('m1'), (foodId, 'user_rule'));
            expect(await state('m2'), (null, 'none'));
          },
        );

        test('archived category or deleted rule: nothing changes', () async {
          await put('t1', norm: 'carrefour');
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: billsId,
          );
          await CategoriesDao(edb.db).setArchived(billsId, archived: true);
          expect(await repo.applyToPast(r.id), 0);
          await CategoriesDao(edb.db).setArchived(billsId, archived: false);
          await repo.delete(r.id);
          expect(await repo.applyToPast(r.id), 0);
          expect(await repo.countPastMatches(r.id), 0);
          expect(await state('t1'), (null, 'none'));
        });

        test('deleting a rule keeps categories it already applied', () async {
          await put('t1', norm: 'carrefour');
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          await repo.applyToPast(r.id);
          await repo.delete(r.id);
          expect(await state('t1'), (foodId, 'user_rule'));
        });

        test('money is untouched by apply', () async {
          await put('t1', norm: 'carrefour');
          final before = await txns.byId('t1');
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          await repo.applyToPast(r.id);
          final after = await txns.byId('t1');
          expect(after!.amountMinor, before!.amountMinor);
          expect(after.currency, before.currency);
        });
      });

      group('two connections', () {
        test('a user edit committed by another connection is never '
            'overwritten', () async {
          for (var i = 0; i < 30; i++) {
            await put('t$i', norm: 'carrefour');
          }
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          // Connection B edits half the rows as the user, while A applies.
          final edited = {for (var i = 0; i < 30; i += 2) 't$i'};
          await Future.wait([
            repo.applyToPast(r.id),
            for (final id in edited)
              TransactionsDao(other).updateById(
                id,
                TransactionsCompanion(
                  categoryId: const Value(billsId),
                  categorySource: const Value('user'),
                  isUserVerified: const Value(1),
                ),
              ),
          ]);
          for (var i = 0; i < 30; i++) {
            final s = await state('t$i');
            if (edited.contains('t$i')) {
              expect(s, (billsId, 'user'), reason: 't$i');
            } else {
              expect(s, (foodId, 'user_rule'), reason: 't$i');
            }
          }
        });

        test('concurrent applies from both connections change each row '
            'once', () async {
          for (var i = 0; i < 20; i++) {
            await put('t$i', norm: 'carrefour');
          }
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          final counts = await Future.wait([
            for (var i = 0; i < 8; i++)
              (i.isEven ? repo : repoB).applyToPast(r.id),
          ]);
          expect(counts.fold<int>(0, (a, b) => a + b), 20);
          expect(await repo.countPastMatches(r.id), 0);
        });

        test('rule deleted on another connection mid-apply: no row gets a '
            'dangling or stale category', () async {
          for (var i = 0; i < 10; i++) {
            await put('t$i', norm: 'carrefour');
          }
          final r = await repo.save(
            kind: RuleMatchKind.merchantNorm,
            value: 'carrefour',
            categoryId: foodId,
          );
          await Future.wait([repo.applyToPast(r.id), repoB.delete(r.id)]);
          final rows = await edb.db
              .customSelect(
                'SELECT category_id AS c, category_source AS s FROM transactions',
              )
              .get();
          for (final row in rows) {
            final c = row.read<String?>('c');
            final s = row.read<String>('s');
            expect(
              (c, s) == (null, 'none') || (c, s) == (foodId, 'user_rule'),
              isTrue,
            );
          }
        });
      });
    });
  }
}
