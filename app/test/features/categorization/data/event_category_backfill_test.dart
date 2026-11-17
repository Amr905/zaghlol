// FU-254: the one-time pass that gives rows saved before CAT-cash the Cash /
// InstaPay category. Fails without it: old ATM and InstaPay rows stayed
// uncategorized. Synthetic data only.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/categorization/data/event_category_backfill.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol/ingestion/ingestion_pause_gate.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EncryptedDb edb;
  late TransactionsDao txns;
  late Registry registry;
  late String atmTpl;
  late String ipTpl;

  Future<void> put(
    String id, {
    String? template,
    String? cpKind,
    String direction = 'expense',
    String source = 'none',
    String? category,
    bool verified = false,
  }) => txns.insert(
    txn(id, direction: direction).copyWith(
      templateId: Value(template),
      counterpartyKind: Value(cpKind),
      categorySource: Value(source),
      categoryId: Value(category),
      isUserVerified: Value(verified ? 1 : 0),
    ),
  );

  Future<(String?, String)> state(String id) async {
    final r = await txns.byId(id);
    return (r!.categoryId, r.categorySource);
  }

  setUp(() async {
    registry = await preloadBundledRegistry();
    final ids = eventCategoryByTemplate(registry);
    atmTpl = ids.entries.firstWhere((e) => e.value == 'sys:cash').key;
    ipTpl = ids.entries.firstWhere((e) => e.value == 'sys:instapay').key;
    edb = await EncryptedDb.open();
    txns = TransactionsDao(edb.db);
    await AccountsDao(edb.db).insert(account('acc1'));
    final cats = CategoriesDao(edb.db);
    for (final (code, sort) in [('food', 1), ('cash', 2), ('instapay', 3)]) {
      await cats.upsertSystem(
        code: code,
        nameAr: 'ا',
        nameEn: code,
        icon: 'i',
        color: '#0F7A55',
        bucket: 'wants',
        sort: sort,
      );
    }
  });
  tearDown(() => edb.close());

  test('ATM and InstaPay rows get the category; user choices stay', () async {
    await put('atm', template: atmTpl);
    await put(
      'atmCatalog',
      template: atmTpl,
      source: 'catalog',
      category: 'sys:food',
    );
    await put('ip', template: ipTpl, direction: 'transfer_out');
    await put('ipa', cpKind: 'ipa', direction: 'transfer_in');
    await put('ipaExpense', cpKind: 'ipa'); // not a transfer: left alone
    await put('plain');
    await put('user', template: atmTpl, source: 'user', category: 'sys:food');
    await put(
      'rule',
      template: ipTpl,
      source: 'user_rule',
      category: 'sys:food',
    );
    await put('verified', template: atmTpl, verified: true);

    final n = await backfillEventCategories(edb.db, registry, at: t0 + 5);
    expect(n, 4);
    expect(await state('atm'), ('sys:cash', 'heuristic'));
    expect(await state('atmCatalog'), ('sys:cash', 'heuristic'));
    expect(await state('ip'), ('sys:instapay', 'heuristic'));
    expect(await state('ipa'), ('sys:instapay', 'heuristic'));
    expect(await state('ipaExpense'), (null, 'none'));
    expect(await state('plain'), (null, 'none'));
    // User category untouched.
    expect(await state('user'), ('sys:food', 'user'));
    expect(await state('rule'), ('sys:food', 'user_rule'));
    expect(await state('verified'), (null, 'none'));
  });

  test('runs once: marked in db_meta, a second run does nothing', () async {
    await put('atm', template: atmTpl);
    expect(await backfillEventCategories(edb.db, registry, at: t0), 1);
    await put('atm2', template: atmTpl);
    expect(await backfillEventCategories(edb.db, registry, at: t0), isNull);
    expect(await state('atm2'), (null, 'none'));
  });

  test('more rows than one chunk are all done', () async {
    for (var i = 0; i < eventBackfillChunk + 30; i++) {
      await put('r${i.toString().padLeft(4, '0')}', template: atmTpl);
    }
    expect(
      await backfillEventCategories(edb.db, registry, at: t0),
      eventBackfillChunk + 30,
    );
  });

  test('a closed restore gate writes nothing and leaves it unmarked', () async {
    await put('atm', template: atmTpl);
    final gate = IngestionPauseGate();
    await gate.pause();
    expect(
      await backfillEventCategories(edb.db, registry, at: t0, gate: gate),
      isNull,
    );
    expect(await state('atm'), (null, 'none'));
    gate.resume();
    expect(
      await backfillEventCategories(edb.db, registry, at: t0, gate: gate),
      1,
    );
  });

  test('a missing category leaves it unmarked for the next start', () async {
    await edb.db.customStatement(
      "DELETE FROM categories WHERE id = 'sys:cash'",
    );
    await put('atm', template: atmTpl);
    expect(await backfillEventCategories(edb.db, registry, at: t0), isNull);
    expect(await state('atm'), (null, 'none'));
  });
}
