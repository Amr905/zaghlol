// T-357: the AI tier and the recategorizer (LLM-CATEGORISE,
// llm-categorise.md §7 "Categorizer"). An AI suggestion only fills "needs
// classification" rows; rules, catalog and keyword categories replace it
// (FU-408). Synthetic data only; merchant names are invented.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_queue.dart';
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/recategorizer.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol/features/categorization/domain/merchant_rule.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late TransactionsDao txns;
  late DriftRulesRepository rules;
  late AiSuggestionApplier applier;
  late AiMerchantSuggestionsDao sugg;

  Categorizer newCat({bool memo = false}) =>
      Categorizer(driftCategorizerPorts(db, rules), memoize: memo);

  Future<void> put(
    String id, {
    String? norm,
    String source = 'none',
    String? category,
    String? cpKind,
    String? cp,
    bool verified = false,
    bool internal = false,
    bool deleted = false,
    int amount = 10000,
  }) => txns.insert(
    txn(id, merchantNorm: norm, amountMinor: amount).copyWith(
      merchantRaw: Value(norm?.toUpperCase()),
      categorySource: Value(source),
      categoryId: Value(category),
      counterpartyKind: Value(cpKind),
      counterpartyValue: Value(cp),
      isUserVerified: Value(verified ? 1 : 0),
      isInternal: Value(internal ? 1 : 0),
      deletedAt: Value(deleted ? t0 : null),
    ),
  );

  Future<(String?, String)> state(String id) async {
    final r = await txns.byId(id);
    return (r!.categoryId, r.categorySource);
  }

  Future<Map<String, Map<String, Object?>>> snapshot() async => {
    for (final r
        in await db
            .customSelect('SELECT * FROM transactions ORDER BY id')
            .get())
      r.read<String>('id'): Map.of(r.data),
  };

  Future<void> accept(String norm, String cat) => applier.accept(
    merchantNorm: norm,
    categoryId: cat,
    confidence: 90,
    source: AiSuggestionSourceCode.llm,
    at: DateTime.fromMillisecondsSinceEpoch(t0 + 5, isUtc: true),
  );

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    txns = TransactionsDao(db);
    sugg = AiMerchantSuggestionsDao(db);
    rules = DriftRulesRepository(MerchantRulesDao(db), CategoriesDao(db));
    applier = AiSuggestionApplier(db, newCategorizer: newCat);
    await AccountsDao(db).insert(account('acc1'));
    final cats = CategoriesDao(db);
    var sort = 0;
    for (final code in [
      'dining',
      'food',
      'bills',
      'health',
      'cash',
      'instapay',
    ]) {
      await cats.upsertSystem(
        code: code,
        nameAr: 'ا',
        nameEn: code,
        icon: 'i',
        color: '#0F7A55',
        bucket: 'needs',
        sort: ++sort,
      );
    }
  });
  tearDown(() => edb.close());

  test('AC1: a suggestion fills the 3 uncategorised rows; the user row '
      'stays', () async {
    for (final id in ['z1', 'z2', 'z3']) {
      await put(id, norm: 'zawya');
    }
    await put('z4', norm: 'zawya', source: 'user', category: 'sys:bills');
    await LlmCatQueueDao(db).enqueue('zawya', at: t0);

    await accept('zawya', 'sys:dining');

    for (final id in ['z1', 'z2', 'z3']) {
      expect(await state(id), ('sys:dining', 'ai'), reason: id);
    }
    expect(await state('z4'), ('sys:bills', 'user'));
    expect((await sugg.byMerchant('zawya'))!.state, 'unconfirmed');
    expect(await LlmCatQueueDao(db).count(), 0);
    // Idempotent: a repeat changes nothing.
    final before = await snapshot();
    await accept('zawya', 'sys:dining');
    expect(await snapshot(), before);
  });

  test('AC2: a new row gets the AI category through the tier; a catalog '
      'update replaces it and drops the unconfirmed suggestion', () async {
    await put('z1', norm: 'zawya');
    await accept('zawya', 'sys:dining');
    final d = await newCat().categorize(
      categorizeInputFor(merchantRaw: 'ZAWYA', merchantNorm: 'zawya'),
    );
    expect(d.source, CategorySource.ai);
    expect(d.categoryId, 'sys:dining');

    final catalog = CatalogDao(db);
    await catalog.upsertMerchant(
      CatalogMerchantsCompanion.insert(
        id: const Value(9),
        canonical: 'Zawya',
        categoryCode: 'food',
        version: 2,
      ),
    );
    await catalog.upsertAlias(
      merchantId: 9,
      aliasNorm: 'zawya',
      match: 'exact',
    );
    final r = await Recategorizer(db).run(newCat(memo: true), at: t0 + 9);
    expect(r.changed, 1);
    expect(await state('z1'), ('sys:food', 'catalog'));
    expect(await sugg.byMerchant('zawya'), isNull);
  });

  test('FU-408: a user rule (and its apply-to-past) replaces an ai '
      'category', () async {
    await put('z1', norm: 'zawya');
    await put('z2', norm: 'zawya');
    await accept('zawya', 'sys:dining');
    final rule = await rules.save(
      kind: RuleMatchKind.merchantNorm,
      value: 'zawya',
      categoryId: 'sys:health',
    );
    // Through the recategorizer (any pass) ...
    await Recategorizer(db).run(newCat(memo: true), at: t0 + 9);
    expect(await state('z1'), ('sys:health', 'user_rule'));
    // ... and through apply-to-past (the Right/Wrong path).
    await put('z3', norm: 'zawya', source: 'ai', category: 'sys:dining');
    expect(await rules.applyToPast(rule.id), 1);
    expect(await state('z3'), ('sys:health', 'user_rule'));
  });

  test(
    'NEGATIVE PROOF 1 (AC3): after suggestions for every merchant only '
    '"needs classification" rows change; the rest is byte-identical',
    () async {
      await rules.save(
        kind: RuleMatchKind.merchantNorm,
        value: 'ruled',
        categoryId: 'sys:bills',
      );
      for (final m in ['zawya', 'ruled', 'kosharyx']) {
        await put('$m-user', norm: m, source: 'user', category: 'sys:bills');
        await put(
          '$m-rule',
          norm: m,
          source: 'user_rule',
          category: 'sys:food',
        );
        await put('$m-cat', norm: m, source: 'catalog', category: 'sys:food');
        await put(
          '$m-kw',
          norm: m,
          source: 'heuristic',
          category: 'sys:health',
        );
        await put(
          '$m-ipa',
          norm: m,
          source: 'heuristic',
          category: 'sys:instapay',
        );
        await put(
          '$m-cash',
          norm: m,
          source: 'heuristic',
          category: 'sys:cash',
        );
        // Pipeline source but a category: not "needs classification".
        await put('$m-nonecat', norm: m, category: 'sys:food');
        await put('$m-ver', norm: m, verified: true);
        await put('$m-int', norm: m, internal: true);
        await put('$m-del', norm: m, deleted: true);
        await put('$m-p2p', norm: m, cpKind: 'person', cp: 'someone');
        await put('$m-nc', norm: m, amount: 4321);
      }
      // Settle the rule first (pre-T-357 behaviour), so the proof isolates
      // what the suggestions do.
      await Recategorizer(db).run(newCat(memo: true), at: t0 + 2);
      expect(await state('ruled-nc'), ('sys:bills', 'user_rule'));
      final before = await snapshot();
      for (final m in ['zawya', 'ruled', 'kosharyx']) {
        await accept(m, 'sys:dining');
      }
      await Recategorizer(db).run(newCat(memo: true), at: t0 + 9);
      final after = await snapshot();

      const writable = {'category_id', 'category_source', 'updated_at'};
      for (final id in before.keys) {
        if (id == 'zawya-nc' || id == 'kosharyx-nc') {
          expect(after[id]!['category_source'], 'ai', reason: id);
          expect(after[id]!['category_id'], 'sys:dining', reason: id);
          for (final k in before[id]!.keys.where(
            (k) => !writable.contains(k),
          )) {
            expect(after[id]![k], before[id]![k], reason: '$id.$k');
          }
        } else {
          expect(after[id], before[id], reason: id);
        }
      }
    },
  );

  test('NEGATIVE PROOF 2 (AC4): confirmed, corrected and no_answer never '
      'change a row through the tier', () async {
    final at = t0 + 1;
    for (final m in ['conf', 'corr']) {
      await sugg.putAnswer(
        merchantNorm: m,
        categoryId: 'sys:dining',
        confidence: 90,
        source: AiSuggestionSourceCode.llm,
        at: at,
      );
    }
    await sugg.decide('conf', state: AiSuggestionStateCode.confirmed, at: at);
    await sugg.decide('corr', state: AiSuggestionStateCode.corrected, at: at);
    await sugg.putNoAnswer(merchantNorm: 'noans', at: at);
    for (final m in ['conf', 'corr', 'noans']) {
      await put('$m-nc', norm: m);
    }
    final before = await snapshot();
    final re = Recategorizer(db);
    for (final m in ['conf', 'corr', 'noans']) {
      final d = await newCat().categorize(
        categorizeInputFor(merchantRaw: m, merchantNorm: m),
      );
      expect(d.source, isNot(CategorySource.ai), reason: m);
      await re.applySuggestion(m, newCat(), at: t0 + 9);
    }
    await re.run(newCat(memo: true), at: t0 + 9);
    expect(await snapshot(), before);
  });

  test('apply refuses an ai decision over any category', () async {
    await put('x', norm: 'zawya', source: 'none', category: 'sys:food');
    const ai = CategoryDecision(
      categoryId: 'sys:dining',
      source: CategorySource.ai,
      tier: CategorizeTier.ai,
    );
    final n = await Recategorizer(db).apply(
      id: 'x',
      oldCategoryId: 'sys:food',
      oldCatalogMerchantId: null,
      decision: ai,
      at: t0 + 1,
    );
    expect(n, 0);
    expect(Recategorizer.replaceable(CategorySource.ai), ['none']);
  });

  test(
    'noAnswer marks the merchant tried and takes it off the queue',
    () async {
      await put('n1', norm: 'zawya');
      await LlmCatQueueDao(db).enqueue('zawya', at: t0);
      final before = await snapshot();
      await applier.noAnswer(
        merchantNorm: 'zawya',
        at: DateTime.fromMillisecondsSinceEpoch(t0, isUtc: true),
      );
      expect((await sugg.byMerchant('zawya'))!.state, 'no_answer');
      expect(await LlmCatQueueDao(db).count(), 0);
      expect(await snapshot(), before);
    },
  );
}
