// T-359: Right / Wrong / Undo on an AI category. Synthetic data only; the
// merchant and category names are invented.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_feedback.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';

import '../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late LlmCatFeedback fb;
  late DateTime clock;
  const merchant = 'zawya cinema';
  late Map<String, String> systemId;

  Future<void> sys(String code) => CategoriesDao(db).upsertSystem(
    code: code,
    nameAr: 'ا',
    nameEn: code,
    icon: 'i',
    color: '#0F7A55',
    bucket: 'wants',
    sort: 1,
  );

  Future<String> idOf(String code) async => (await (db.select(
    db.categories,
  )..where((c) => c.systemCode.equals(code))).getSingle()).id;

  Future<void> put(
    String id,
    String norm, {
    String source = 'ai',
    String? category,
    int verified = 0,
  }) => TransactionsDao(db).insert(
    txn(id, merchantNorm: norm).copyWith(
      categoryId: Value(category),
      categorySource: Value(source),
      isUserVerified: Value(verified),
    ),
  );

  Future<void> suggest(String norm, String code, {String source = 'llm'}) =>
      AiMerchantSuggestionsDao(db).putAnswer(
        merchantNorm: norm,
        categoryId: systemId[code]!,
        confidence: 90,
        source: source,
        at: t0,
      );

  Future<List<Object?>> dump() async {
    final out = <Object?>[];
    for (final t in [
      'transactions',
      'merchant_rules',
      'ai_merchant_suggestions',
      'outbox',
    ]) {
      final rows = await db.customSelect('SELECT * FROM $t ORDER BY 1').get();
      out.add([for (final r in rows) r.data]);
    }
    return out;
  }

  setUp(() async {
    clock = DateTime.utc(2026, 11, 26, 10);
    edb = await EncryptedDb.open();
    db = edb.db;
    await AccountsDao(db).insert(account('acc1'));
    for (final c in ['dining', 'education', 'groceries']) {
      await sys(c);
    }
    systemId = {
      for (final c in ['dining', 'education', 'groceries']) c: await idOf(c),
    };
    await CategoriesDao(db).insert(
      CategoriesCompanion.insert(
        id: 'custom-books',
        nameAr: 'كتب',
        nameEn: 'Books',
        icon: 'i',
        color: '#0F7A55',
        bucket: 'wants',
        isCustom: const Value(1),
        sort: 9,
      ),
    );
    for (final i in ['a1', 'a2', 'a3']) {
      await put(i, merchant, category: systemId['dining']);
    }
    // Other merchants / user-set rows must never be touched.
    await put('o1', 'other shop', category: systemId['dining']);
    await put('u1', merchant, source: 'user', category: systemId['groceries']);
    await suggest(merchant, 'dining');
    await suggest('other shop', 'dining');
    fb = LlmCatFeedback(
      db,
      DriftRulesRepository(
        MerchantRulesDao(db),
        CategoriesDao(db),
        clock: () => clock,
      ),
      clock: () => clock,
    );
  });
  tearDown(() => edb.close());

  Future<List<Map<String, Object?>>> rows(String sql) async => [
    for (final r in await db.customSelect(sql).get()) r.data,
  ];

  test('AC1: Right saves the rule, drops the AI mark on all rows and '
      'queues one confirmation', () async {
    await fb.confirm(merchant);
    final rules = await MerchantRulesDao(db).all();
    expect(rules.single.matchValue, merchant);
    expect(rules.single.categoryId, systemId['dining']);
    final ai = await rows(
      "SELECT id FROM transactions WHERE category_source = 'ai' ORDER BY id",
    );
    expect([for (final r in ai) r['id']], ['o1']);
    expect(
      [
        for (final r in await rows(
          "SELECT id FROM transactions WHERE category_source = 'user_rule' "
          'ORDER BY id',
        ))
          r['id'],
      ],
      ['a1', 'a2', 'a3'],
    );
    final s = await AiMerchantSuggestionsDao(db).byMerchant(merchant);
    expect(s!.state, 'confirmed');
    final o = await rows('SELECT kind, payload FROM outbox');
    expect(o.single['kind'], 'llm_cat_confirmation');
    expect(o.single['payload'], contains('"verdict":"right"'));
    // The user's own row is untouched.
    expect(
      (await rows("SELECT category_id FROM transactions WHERE id = 'u1'"))
          .single['category_id'],
      systemId['groceries'],
    );
  });

  test('AC2: Wrong with a system category: rule, corrected, correction '
      'row carrying codes only', () async {
    await fb.correct(merchant, systemId['education']!);
    expect(
      (await MerchantRulesDao(db).all()).single.categoryId,
      systemId['education'],
    );
    expect(
      (await AiMerchantSuggestionsDao(db).byMerchant(merchant))!.state,
      'corrected',
    );
    final o = (await rows('SELECT kind, payload FROM outbox')).single;
    expect(o['kind'], 'llm_cat_correction');
    expect(
      o['payload'],
      '{"merchantNorm":"$merchant","verdict":"wrong","aiCategory":"dining",'
      '"userCategory":"education","source":"llm"}',
    );
  });

  test('AC2: a custom category goes out as custom; its name and id are in '
      'no outbox row', () async {
    await fb.correct(merchant, 'custom-books');
    final payload =
        (await rows('SELECT payload FROM outbox')).single['payload']! as String;
    expect(payload, contains('"userCategory":"custom"'));
    expect(payload, isNot(contains('كتب')));
    expect(payload, isNot(contains('Books')));
    expect(payload, isNot(contains('custom-books')));
    expect(
      (await MerchantRulesDao(db).all()).single.categoryId,
      'custom-books',
    );
  });

  test('picker cancelled / invalid choices change nothing', () async {
    final before = await dump();
    await expectLater(
      fb.correct(merchant, systemId['dining']!),
      throwsA(
        isA<LlmCatFeedbackException>().having(
          (e) => e.code,
          'code',
          LlmCatFeedbackException.sameCategory,
        ),
      ),
    );
    await expectLater(
      fb.correct(merchant, 'no-such-category'),
      throwsA(anything),
    );
    expect(await dump(), before);
  });

  test('feedback only exists for a pending AI suggestion: never for an '
      'unsuggested merchant, a no-answer row or a decided one', () async {
    await put('p1', 'mona hassan', category: null, source: 'none');
    await AiMerchantSuggestionsDao(db)
        .putNoAnswer(merchantNorm: 'no answer shop', at: t0);
    for (final m in ['mona hassan', 'no answer shop']) {
      await expectLater(
        fb.confirm(m),
        throwsA(
          isA<LlmCatFeedbackException>().having(
            (e) => e.code,
            'code',
            LlmCatFeedbackException.notPending,
          ),
        ),
      );
    }
    await fb.confirm(merchant);
    await expectLater(
      fb.confirm(merchant),
      throwsA(isA<LlmCatFeedbackException>()),
    );
    expect(await rows('SELECT id FROM outbox'), hasLength(1));
  });

  test('AC3: Undo within 5 s restores every affected row exactly', () async {
    final before = await dump();
    final r = await fb.confirm(merchant);
    expect(await dump(), isNot(before));
    clock = clock.add(const Duration(seconds: 5));
    await fb.undo(r);
    expect(await dump(), before);
    expect(await MerchantRulesDao(db).all(), isEmpty);
    expect(await rows('SELECT id FROM outbox'), isEmpty);
  });

  test('AC3: Undo of a correction restores exactly, also over a '
      'pre-existing rule', () async {
    await MerchantRulesDao(db).upsert(
      MerchantRulesCompanion.insert(
        id: 'r-old',
        matchKind: RuleMatchKind.merchantNorm,
        matchValue: merchant,
        categoryId: systemId['groceries']!,
        createdAt: t0,
      ),
    );
    final before = await dump();
    final r = await fb.correct(merchant, systemId['education']!);
    await fb.undo(r);
    expect(await dump(), before);
  });

  test('AC3: after 5 s Undo is gone and changes nothing; a receipt works '
      'once', () async {
    final r = await fb.confirm(merchant);
    final after = await dump();
    clock = clock.add(const Duration(seconds: 5, milliseconds: 1));
    await expectLater(
      fb.undo(r),
      throwsA(
        isA<LlmCatFeedbackException>().having(
          (e) => e.code,
          'code',
          LlmCatFeedbackException.undoExpired,
        ),
      ),
    );
    expect(await dump(), after);

    final r2 = await fb.correct('other shop', systemId['education']!);
    await fb.undo(r2);
    await expectLater(fb.undo(r2), throwsA(isA<LlmCatFeedbackException>()));
  });

  test('Undo never overwrites a later user edit of a row', () async {
    final r = await fb.confirm(merchant);
    await db.customStatement(
      "UPDATE transactions SET category_id = '${systemId['groceries']}', "
      "category_source = 'user' WHERE id = 'a1'",
    );
    await fb.undo(r);
    final a1 = (await rows(
      "SELECT category_id, category_source FROM transactions WHERE id='a1'",
    )).single;
    expect(a1['category_source'], 'user');
    expect(a1['category_id'], systemId['groceries']);
    // The others are back to the AI mark.
    expect(
      (await rows("SELECT category_source s FROM transactions WHERE id='a2'"))
          .single['s'],
      'ai',
    );
  });
}
