// T-357: filling the auto-category queue and picking what may be sent
// (FR-LCAT-04/05/40). Nothing is sent here. Synthetic data only; names are
// invented.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart' show LlmQuota;
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_business_templates.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_queue.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol/features/categorization/domain/llm_payment_kind.dart';
import 'package:zaghlol/features/categorization/domain/merchant_rule.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

NameLexicon loadLexicon() => NameLexicon.fromLines(
  givenNames: File('assets/data/eg_given_names.txt').readAsStringSync(),
  honorifics: File('assets/data/eg_honorifics.txt').readAsStringSync(),
  businessWords: File('assets/data/eg_business_words.txt').readAsStringSync(),
);

void main() {
  final lexicon = loadLexicon();
  final now = DateTime.fromMillisecondsSinceEpoch(t0 + 1000, isUtc: true);
  late EncryptedDb edb;
  late AppDatabase db;
  late TransactionsDao txns;
  late LlmQuotaStore quota;
  late LlmCatQueueDao queue;
  // Template id -> registry event (the typed evidence of the row kind).
  const events = {
    'bank.card': TemplateEvent.cardPurchase,
    'wal.pay': TemplateEvent.cardPurchase,
    'ipa': TemplateEvent.instapayOut,
    'wallet': TemplateEvent.transferOut,
    'atm': TemplateEvent.atmWithdrawal,
    'bank.refund': TemplateEvent.refund,
    'wal.refund': TemplateEvent.refund,
  };
  var flagOn = true;
  var consent = true;

  LlmCatQueueFiller filler() => LlmCatQueueFiller(
    db,
    gate: LlmCatGate(
      isFlagOn: () => flagOn,
      hasConsent: () async => consent,
      quota: quota,
    ),
    lexicon: () async => lexicon,
    templateEvents: () => events,
    businessTemplates: const {'bank.card'},
  );

  Future<void> put(
    String id,
    String norm, {
    String? raw,
    String source = 'sms',
    String direction = 'expense',
    String? cpKind,
    String? category,
    String categorySource = 'none',
    int createdAt = t0,
    bool internal = false,
    String? template = 'bank.card',
  }) => txns.insert(
    txn(id, merchantNorm: norm, direction: direction).copyWith(
      source: Value(source),
      merchantRaw: Value(raw ?? norm.toUpperCase()),
      counterpartyKind: Value(cpKind),
      counterpartyValue: Value(cpKind == null ? null : 'cp'),
      categoryId: Value(category),
      categorySource: Value(categorySource),
      createdAt: Value(createdAt),
      isInternal: Value(internal ? 1 : 0),
      templateId: Value(template),
    ),
  );

  Future<Map<String, int>> queued() async => {
    for (final r in await queue.all()) r.merchantNorm: r.txnCount,
  };

  setUp(() async {
    flagOn = true;
    consent = true;
    edb = await EncryptedDb.open();
    db = edb.db;
    txns = TransactionsDao(db);
    queue = LlmCatQueueDao(db);
    quota = LlmQuotaStore(SettingsRepository(SettingsDao(db), nowMs: () => 1));
    await AccountsDao(db).insert(account('acc1'));
    await CategoriesDao(db).upsertSystem(
      code: 'food',
      nameAr: 'ا',
      nameEn: 'food',
      icon: 'i',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
  });
  tearDown(() => edb.close());

  group('llmPaymentKindOf (conservative)', () {
    LlmPaymentKind k({
      String direction = 'expense',
      String source = 'sms',
      String? cp,
      bool internal = false,
      bool paired = false,
    }) => llmPaymentKindOf(
      direction: direction,
      source: source,
      counterpartyKind: cp,
      isInternal: internal,
      hasTransferPair: paired,
    );

    test('only an automated expense/refund to a merchant is a business '
        'payment', () {
      expect(k(), LlmPaymentKind.businessPayment);
      expect(
        k(direction: 'refund', cp: 'merchant'),
        LlmPaymentKind.businessPayment,
      );
      expect(k(direction: 'income'), LlmPaymentKind.income);
      expect(k(direction: 'transfer_out'), LlmPaymentKind.transfer);
      expect(k(direction: 'transfer_in'), LlmPaymentKind.transfer);
      expect(k(direction: 'fee'), LlmPaymentKind.unknown);
      expect(k(direction: '??'), LlmPaymentKind.unknown);
      expect(k(cp: 'person'), LlmPaymentKind.transfer);
      expect(k(cp: 'ipa'), LlmPaymentKind.transfer);
      expect(k(internal: true), LlmPaymentKind.transfer);
      expect(k(paired: true), LlmPaymentKind.transfer);
      for (final s in ['manual', 'voice', 'csv', 'other']) {
        expect(k(source: s), LlmPaymentKind.unknown, reason: s);
      }
    });
  });

  test('queues eligible merchants with their counts; idempotent', () async {
    await put('a1', 'zawya cinema');
    await put(
      'a2',
      'zawya cinema',
      direction: 'refund',
      template: 'bank.refund',
    );
    await put('b1', 'kosharyx', source: 'notification');
    final r = await filler().fill(now: now);
    expect(r.ran, isTrue);
    expect(await queued(), {'zawya cinema': 2, 'kosharyx': 1});
    final first = await queue.all();
    await filler().fill(now: now.add(const Duration(minutes: 5)));
    expect(await queued(), {'zawya cinema': 2, 'kosharyx': 1});
    // first_queued_at and retry state are kept.
    expect(
      [for (final q in await queue.all()) q.firstQueuedAt],
      [for (final q in first) q.firstQueuedAt],
    );
  });

  test(
    'card purchase evidence: a brand without a business word is queued; '
    'the same name on a transfer row, mixed rows or a person name is not',
    () async {
      await put('c1', 'kosharyx');
      await put('p1', 'kosharyx', template: 'ipa');
      await put('p2', 'zawya cinema');
      await put('p3', 'zawya cinema', template: 'wallet');
      await put('a1', 'atm shop', template: 'atm');
      await put('n1', 'plainx', template: null);
      await put('u1', 'mona'); // person-like name on a card row
      await put('ok', 'kosharyz');
      await filler().fill(now: now);
      expect(await queued(), {'kosharyz': 1});
    },
  );

  test(
    'B95-M1: a wallet "paid to" payee is never business evidence, even '
    'when the event says card purchase; a refund follows its sibling',
    () async {
      await put('w1', 'rahul sharma', template: 'wal.pay');
      await put('w2', 'priya', template: 'wal.pay');
      await put('w3', 'zawya cinema', template: 'wal.pay');
      await put('w4', 'kosharyz', direction: 'refund', template: 'wal.refund');
      await put('b1', 'kosharyx', template: 'bank.card');
      // The same person-like name on the allowed bank template: the
      // template is business evidence, but the name still fails the
      // eligibility rule (given-name lexicon), so it is not queued.
      await put('b2', 'rahul sharma', template: 'bank.card');
      await filler().fill(now: now);
      expect(await queued(), {'kosharyx': 1});
    },
  );

  test('B95-M1: every bundled card-purchase template has an explicit '
      'decision, and the lists hold no stale id', () async {
    final registry = await preloadBundledRegistry();
    final cards = <String>{};
    for (final i in registry.institutions) {
      for (final t in i.templates) {
        if (t.event == TemplateEvent.cardPurchase ||
            t.event == TemplateEvent.cardPurchaseFx) {
          cards.add(t.id);
        }
      }
    }
    final allowed = llmBusinessPurchaseTemplates;
    final refused = llmRefusedPurchaseTemplates.keys.toSet();
    expect(allowed.intersection(refused), isEmpty);
    expect(
      cards.difference(allowed.union(refused)),
      isEmpty,
      reason: 'decide every new card-purchase template',
    );
    expect(allowed.union(refused).difference(cards), isEmpty);
    // The reviewer's probes stay refused.
    for (final id in [
      'vodafone_cash.payment.ar',
      'vodafone_cash.ocr_payment.en',
      'vodafone_cash.ocr_payment.ar',
      'revolut.card_purchase.en',
      'paytm.card_purchase.en',
      'orange_cash.card_purchase.ar',
      'we_pay.card_purchase.en',
      'instapay.bill.en',
    ]) {
      expect(refused, contains(id));
    }
    // Refund evidence: only where a purchase sibling is allowed.
    final refunds = [
      for (final i in registry.institutions)
        for (final t in i.templates)
          if (t.event == TemplateEvent.refund) t.id,
    ];
    expect(refunds, isNotEmpty);
    for (final id in refunds) {
      final sibling = allowed.any(
        (p) => templateInstitution(p) == templateInstitution(id),
      );
      expect(isBusinessRefundTemplate(id, allowed), sibling, reason: id);
    }
    // FU-437: the institutions whose refunds count, pinned literally. A new
    // refund template, or a new allowed purchase template, must be decided.
    final refundInstitutions = {
      for (final id in refunds)
        if (isBusinessRefundTemplate(id, allowed)) templateInstitution(id),
    };
    expect(refundInstitutions.toList()..sort(), [
      'liv',
      'monzo',
      'n26',
      'wise',
    ]);
    expect(isBusinessRefundTemplate('revolut.refund.en', allowed), isFalse);
    expect(isBusinessRefundTemplate('instapay.refund.en', allowed), isFalse);
  });

  test('without template evidence nothing is a business payment', () async {
    await put('c1', 'kosharyx');
    final f = LlmCatQueueFiller(
      db,
      gate: LlmCatGate(
        isFlagOn: () => true,
        hasConsent: () async => true,
        quota: quota,
      ),
      lexicon: () async => lexicon,
    );
    await f.fill(now: now);
    expect(await queue.count(), 0);
  });

  test('NEGATIVE PROOF 3a: nothing ineligible is ever queued', () async {
    await put('p1', 'mona'); // a given name
    await put('p2', 'dr ahmed'); // honorific + name
    await put('i1', 'shop 123456'); // digit run
    // The key is a transliteration; the Arabic raw text is a given name.
    await put('i2', 'mna', raw: 'منى');
    await put('t1', 'some place', direction: 'transfer_out');
    await put('t2', 'other place', cpKind: 'person');
    await put('m1', 'typed place', source: 'manual');
    await put('v1', 'spoken place', source: 'voice');
    await put('in1', 'salary co', direction: 'income');
    // Mixed: one row of the key is a transfer → the key is refused.
    await put('x1', 'mixed shop');
    await put('x2', 'mixed shop', direction: 'transfer_out');
    // Tried before (any state).
    await put('tr', 'tried shop');
    await AiMerchantSuggestionsDao(db)
        .putNoAnswer(merchantNorm: 'tried shop', at: t0);
    // A user rule exists.
    await put('ru', 'ruled shop');
    await DriftRulesRepository(MerchantRulesDao(db), CategoriesDao(db)).save(
      kind: RuleMatchKind.merchantNorm,
      value: 'ruled shop',
      categoryId: 'sys:food',
    );
    // Not "needs classification".
    await put(
      'c1',
      'catalog shop',
      category: 'sys:food',
      categorySource: 'catalog',
    );
    await put('int', 'own shop', internal: true);
    // Older than 60 days.
    await put(
      'old',
      'old shop',
      createdAt:
          now.millisecondsSinceEpoch - const Duration(days: 61).inMilliseconds,
    );
    // The control: one eligible merchant.
    await put('ok', 'zawya cinema');

    await filler().fill(now: now);
    expect(await queued(), {'zawya cinema': 1});
    expect(await filler().pickForSend(now: now, batchMax: 20), [
      'zawya cinema',
    ]);
  });

  test('NEGATIVE PROOF 3b: flag off, no consent or quota 0 → nothing queued '
      'or picked', () async {
    await put('a1', 'zawya cinema');
    flagOn = false;
    expect((await filler().fill(now: now)).ran, isFalse);
    expect(await filler().pickForSend(now: now, batchMax: 20), isEmpty);
    expect(await queue.count(), 0);

    flagOn = true;
    consent = false;
    expect((await filler().fill(now: now)).ran, isFalse);
    expect(await filler().pickForSend(now: now, batchMax: 20), isEmpty);
    expect(await queue.count(), 0);

    consent = true;
    final resets = now.add(const Duration(days: 3)).toIso8601String();
    await quota.record(
      LlmFeature.categorise,
      LlmQuota(limit: 15, used: 15, remaining: 0, resetsAt: resets),
    );
    expect(await filler().pickForSend(now: now, batchMax: 20), isEmpty);

    // Paused until the next sync.
    await quota.record(
      LlmFeature.categorise,
      LlmQuota(limit: 15, used: 0, remaining: 15, resetsAt: resets),
    );
    await quota.pause(LlmFeature.categorise);
    expect(await filler().pickForSend(now: now, batchMax: 20), isEmpty);
  });

  test('picks at most the remaining allowance, in send order; after the '
      'reset the full batch', () async {
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j <= i; j++) {
        await put('s$i-$j', 'store x$i', createdAt: t0 + i);
      }
    }
    final resets = now.add(const Duration(days: 1));
    await quota.record(
      LlmFeature.categorise,
      LlmQuota(
        limit: 15,
        used: 13,
        remaining: 2,
        resetsAt: resets.toIso8601String(),
      ),
    );
    expect(await filler().pickForSend(now: now, batchMax: 20), [
      'store x4',
      'store x3',
    ]);
    // Picking counts nothing: the same two again.
    expect(await filler().pickForSend(now: now, batchMax: 20), hasLength(2));
    final later = resets.add(const Duration(minutes: 1));
    expect(await filler().pickForSend(now: later, batchMax: 20), hasLength(5));
    expect(await filler().pickForSend(now: later, batchMax: 3), hasLength(3));
  });

  test('a merchant the user categorised leaves the queue', () async {
    await put('a1', 'zawya cinema');
    await filler().fill(now: now);
    expect(await queue.count(), 1);
    await db.customStatement(
      "UPDATE transactions SET category_id = 'sys:food', "
      "category_source = 'user' WHERE id = 'a1'",
    );
    final r = await filler().fill(now: now);
    expect(r.removed, 1);
    expect(await queue.count(), 0);
  });

  test('cap: the 100 most recently seen merchants', () async {
    for (var i = 0; i < 105; i++) {
      await put('c$i', 'store y$i', createdAt: t0 + i);
    }
    await filler().fill(now: now);
    final q = await queued();
    expect(q, hasLength(llmCatQueueCap));
    for (var i = 0; i < 5; i++) {
      expect(q.containsKey('store y$i'), isFalse);
    }
    // Stable on re-run (no churn).
    await filler().fill(now: now);
    expect((await queued()).keys.toSet(), q.keys.toSet());
  });

  test('an empty lexicon refuses everything (fail closed)', () async {
    await put('a1', 'zawya cinema');
    final f = LlmCatQueueFiller(
      db,
      gate: LlmCatGate(
        isFlagOn: () => true,
        hasConsent: () async => true,
        quota: quota,
      ),
      lexicon: () async =>
          NameLexicon(givenNames: [], honorifics: [], businessWords: []),
    );
    await f.fill(now: now);
    expect(await queue.count(), 0);
  });

  test('queue keys match the table CHECK', () {
    expect(isQueueableKey('zawya cinema'), isTrue);
    for (final k in ['a', ' ab', 'ab ', 'a  b', 'Ab', 'ab-c', 'x' * 65]) {
      expect(isQueueableKey(k), isFalse, reason: k);
    }
  });
}
