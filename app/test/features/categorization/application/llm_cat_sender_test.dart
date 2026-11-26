// T-358: the auto-category sender over the real gateway client and a scripted
// transport (the wire body is what the test reads). Synthetic data only;
// every name is invented.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart' show DiagLevel;
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_queue.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_sender.dart';
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/backend/backend_test_support.dart';
import '../../../core/db/financial_fixtures.dart';

const _terms = LlmTerms(provider: 'openai-luna', v: 1);
final _now = DateTime.fromMillisecondsSinceEpoch(t0 + 1000, isUtc: true);
final _resets = _now.add(const Duration(days: 3)).toIso8601String();

NameLexicon _lexicon() => NameLexicon.fromLines(
  givenNames: File('assets/data/eg_given_names.txt').readAsStringSync(),
  honorifics: File('assets/data/eg_honorifics.txt').readAsStringSync(),
  businessWords: File('assets/data/eg_business_words.txt').readAsStringSync(),
);

final class _Diag implements DiagStore {
  final List<String> rows = [];
  @override
  Future<void> append({
    required int at,
    required DiagLevel level,
    required String code,
    required Map<String, Object?> fields,
  }) async => rows.add('$code ${jsonEncode(fields)}');
  @override
  Future<void> prune({required int olderThan, required int keepAtMost}) async {}
}

final class _Server implements BackendTransport {
  /// Null: fail as offline. Else the reply for a request body.
  BackendResponse Function(Map<String, Object?> body)? reply;
  bool offline = false;
  final List<Map<String, Object?>> bodies = [];
  final List<String> raw = [];

  @override
  Future<BackendResponse> send(BackendRequest r) async {
    if (r.uri.path == '/v1/installs') {
      return jsonResponse(201, {
        'installToken': fakeToken(1),
        'serverTime': '2026-11-26T10:00:00Z',
      });
    }
    if (offline) throw const TransportException(TransportFailureKind.offline);
    raw.add(utf8.decode(r.body!));
    final b = bodyJson(r);
    bodies.add(b);
    return reply!(b);
  }
}

final class _Prover implements LlmProver {
  int proofs = 0;
  @override
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  }) async {
    proofs++;
    return const LlmPlayIntegrityProof(token: 'synthetic.integrity-token.0001');
  }
}

Map<String, Object?> _result(
  String m, {
  String status = 'ok',
  String? category = 'food',
}) => {
  'merchant': m,
  'status': status,
  'category': status == 'ok' ? category : null,
  'confidence': status == 'ok' ? 88 : null,
  'source': status == 'ok' ? 'llm' : null,
};

BackendResponse _ok(List<Map<String, Object?>> results, {int remaining = 9}) =>
    jsonResponse(200, {
      'serverTime': '2026-11-26T10:00:00Z',
      'counted': results.where((r) => r['status'] == 'ok').length,
      'results': results,
      'quota': {
        'limit': 15,
        'used': 15 - remaining,
        'remaining': remaining,
        'resetsAt': _resets,
      },
    });

void main() {
  final lexicon = _lexicon();
  late EncryptedDb edb;
  late AppDatabase db;
  late TransactionsDao txns;
  late LlmCatQueueDao queue;
  late _Server server;
  late _Prover prover;
  late _Diag diag;
  late LlmConsentStore consent;
  late LlmQuotaStore quota;
  late LlmCatSender sender;
  late LlmCatQueueFiller filler;
  var flagOn = true;
  LlmTerms? terms = _terms;
  var batchMax = 20;
  var ids = 0;
  const amount = 7654321;
  var clock = _now;

  const events = {
    'bank.card': TemplateEvent.cardPurchase,
    'wal.pay': TemplateEvent.cardPurchase,
    'ipa': TemplateEvent.instapayOut,
    'wallet': TemplateEvent.transferOut,
  };

  Future<void> put(
    String id,
    String norm, {
    String source = 'sms',
    String direction = 'expense',
    String? cpKind,
    String template = 'bank.card',
    int createdAt = t0,
  }) => txns.insert(
    txn(
      id,
      merchantNorm: norm,
      direction: direction,
      amountMinor: amount,
    ).copyWith(
      source: Value(source),
      merchantRaw: Value(norm.toUpperCase()),
      counterpartyKind: Value(cpKind),
      counterpartyValue: Value(cpKind == null ? null : 'cp'),
      createdAt: Value(createdAt),
      templateId: Value(template),
    ),
  );

  setUp(() async {
    flagOn = true;
    terms = _terms;
    batchMax = 20;
    ids = 0;
    clock = _now;
    edb = await EncryptedDb.open();
    db = edb.db;
    txns = TransactionsDao(db);
    queue = LlmCatQueueDao(db);
    server = _Server();
    prover = _Prover();
    diag = _Diag();
    await AccountsDao(db).insert(account('acc1'));
    for (final c in ['food', 'bills']) {
      await CategoriesDao(db).upsertSystem(
        code: c,
        nameAr: 'ا',
        nameEn: c,
        icon: 'i',
        color: '#0F7A55',
        bucket: 'needs',
        sort: 1,
      );
    }
    final repo = SettingsRepository(SettingsDao(db), nowMs: () => 1);
    consent = LlmConsentStore(repo, nowMs: () => 2);
    quota = LlmQuotaStore(repo);
    await consent.grant(LlmFeature.categorise, 'openai-luna', 1);
    final backend = BackendClient(
      config: BackendConfig(
        baseUri: Uri.parse('https://api.test.invalid'),
        verifier: ResponseSignatureVerifier([
          TestSigningKey('s2026a').publicKey,
        ]),
      ),
      identity: ClientIdentity(
        platform: ClientPlatform.android,
        appVersion: '1.0.0',
        build: '7',
      ),
      transport: server,
      store: FakeBackendStore([]),
      diag: DiagLogger(diag),
      random: Random(5),
      now: () => _now,
    );
    final gateway = LlmGatewayClient(
      backend: backend,
      prover: prover,
      consent: consent,
      quota: quota,
      isFlagOn: (f) => flagOn,
      now: () => clock,
    );
    filler = LlmCatQueueFiller(
      db,
      gate: LlmCatGate(
        isFlagOn: () => flagOn,
        hasConsent: () async =>
            await consent.grantFor(LlmFeature.categorise, 'openai-luna', 1) !=
            null,
        quota: quota,
      ),
      lexicon: () async => lexicon,
      templateEvents: () => events,
      businessTemplates: const {'bank.card'},
    );
    final rules = DriftRulesRepository(MerchantRulesDao(db), CategoriesDao(db));
    sender = LlmCatSender(
      db,
      filler: filler,
      applier: AiSuggestionApplier(
        db,
        newCategorizer: () => Categorizer(driftCategorizerPorts(db, rules)),
      ),
      call:
          ({
            required merchants,
            required lang,
            required terms,
            required requestId,
          }) => gateway.categorise(
            merchants: merchants,
            lang: lang,
            terms: terms,
            requestId: requestId,
          ),
      newRequestId: () => '0AAAAAAAAAAAAAAAAAAAAAAAA${ids++}',
      terms: () => terms,
      batchMax: () => batchMax,
      allowedCategoryIds: () async => {'sys:food', 'sys:bills'},
    );
  });
  tearDown(() => edb.close());

  Future<LlmCatSendReport> run([DateTime? at]) =>
      sender.run(now: at ?? _now, lang: LlmLang.en);

  Future<List<String>> queued() async => [
    for (final q in await queue.all()) q.merchantNorm,
  ];

  Future<String?> catOf(String id) async => (await txns.byId(id))?.categoryId;

  group('AC1 queue and answers', () {
    test('offline: stays queued and costs no interval; back online: sent '
        'once and applied', () async {
      await put('a1', 'kosharyx');
      server.offline = true;
      final off = await run();
      expect(off.outcome, LlmCatSendOutcome.offline);
      expect(await queued(), ['kosharyx']);
      server.offline = false;
      server.reply = (b) => _ok([_result('kosharyx')]);
      final r = await run(_now.add(const Duration(seconds: 5)));
      expect(r.outcome, LlmCatSendOutcome.sent);
      expect(r.applied, 1);
      expect(server.bodies, hasLength(1));
      expect(await catOf('a1'), 'sys:food');
      expect(await queued(), isEmpty);
      // Nothing left: no second request.
      await run(_now.add(const Duration(minutes: 30)));
      expect(server.bodies, hasLength(1));
    });

    test('5 queued, server answers 2 ok + 3 quota: the 3 stay queued; after '
        'the reset date they are sent', () async {
      const names = [
        'kosharya',
        'kosharyb',
        'kosharyc',
        'kosharyd',
        'kosharye',
      ];
      for (var i = 0; i < names.length; i++) {
        await put('q$i', names[i]);
      }
      server.reply = (b) => _ok([
        _result(names[0]),
        _result(names[1]),
        _result(names[2], status: 'quota'),
        _result(names[3], status: 'quota'),
        _result(names[4], status: 'quota'),
      ], remaining: 0);
      final r = await run();
      expect(r.applied, 2);
      expect(r.stayed, 3);
      expect((await queued()).toSet(), names.sublist(2).toSet());
      // The snapshot says 0 before the reset: nothing is sent.
      await run(_now.add(const Duration(minutes: 20)));
      expect(server.bodies, hasLength(1));
      // After the reset the snapshot is stale: sent automatically.
      server.reply = (b) =>
          _ok([for (final m in b['merchants']! as List) _result('$m')]);
      final after = _now.add(const Duration(days: 4));
      clock = after;
      final r2 = await run(after);
      expect(r2.applied, 3);
      expect(server.bodies, hasLength(2));
    });

    test('101st merchant drops the oldest', () async {
      for (var i = 0; i < 101; i++) {
        await put(
          'm$i',
          'shop${String.fromCharCode(97 + i % 26)}${String.fromCharCode(97 + i ~/ 26)}x',
          createdAt: t0 + i,
        );
      }
      await filler.fill(now: _now);
      final q = await queued();
      expect(q, hasLength(100));
      expect(q, isNot(contains('shopaax')));
    });

    test(
      'order: most transactions, then most recent; batch_max caps',
      () async {
        await put('o1', 'kosharya', createdAt: t0 + 1);
        await put('o2', 'kosharyb', createdAt: t0 + 2);
        await put('o3', 'kosharyb', createdAt: t0 + 2);
        await put('o4', 'kosharyc', createdAt: t0 + 3);
        batchMax = 3;
        server.reply = (b) => _ok([]);
        await run();
        expect(server.bodies.single['merchants'], [
          'kosharyb',
          'kosharyc',
          'kosharya',
        ]);
      },
    );
  });

  group('AC2 scheduling', () {
    test('one send per 10 minutes; back-off after a failure; the request id '
        'is reused for the same batch inside the window', () async {
      await put('s1', 'kosharyx');
      server.reply = (b) =>
          problem(502, 'UPSTREAM_UNAVAILABLE', retryAfter: 90);
      final f = await run();
      expect(f.outcome, LlmCatSendOutcome.failed);
      final t = _now;
      // Inside the back-off (retry-after 90 s): nothing.
      expect(
        (await run(t.add(const Duration(seconds: 30)))).outcome,
        LlmCatSendOutcome.throttled,
      );
      expect(server.bodies, hasLength(1));
      // The queue row carries the back-off too.
      expect((await queue.all()).single.attempts, 1);
      // After it, inside the server's window: same request id.
      server.reply = (b) => _ok([_result('kosharyx')]);
      // interval is 10 minutes: use a sender with a shorter one to reach
      // the window (the id rule itself is what is tested).
      final s2 = LlmCatSender(
        db,
        filler: filler,
        applier: sender.applier,
        call: sender.call,
        newRequestId: sender.newRequestId,
        terms: sender.terms,
        batchMax: sender.batchMax,
        allowedCategoryIds: sender.allowedCategoryIds,
        minInterval: const Duration(seconds: 10),
      );
      server.reply = (b) =>
          problem(502, 'UPSTREAM_UNAVAILABLE', retryAfter: 60);
      await s2.run(now: t.add(const Duration(minutes: 5)), lang: LlmLang.en);
      await queue.markAttempt(['kosharyx'], nextAttemptAt: 0);
      server.reply = (b) => _ok([_result('kosharyx')]);
      await s2.run(
        now: t.add(const Duration(minutes: 5, seconds: 70)),
        lang: LlmLang.en,
      );
      expect(server.bodies, hasLength(3));
      expect(server.bodies[1]['requestId'], server.bodies[2]['requestId']);
    });

    test('a second run inside 10 minutes sends nothing', () async {
      await put('s2', 'kosharyx');
      await put('s3', 'kosharyy');
      server.reply = (b) => _ok([_result('kosharyx')]);
      batchMax = 1;
      await run();
      final r = await run(_now.add(const Duration(minutes: 9)));
      expect(r.outcome, LlmCatSendOutcome.throttled);
      expect(server.bodies, hasLength(1));
      await run(_now.add(const Duration(minutes: 11)));
      expect(server.bodies, hasLength(2));
    });

    test('409 clears consent, keeps the queue, resets the config cursor and '
        'never stores the 409 provider (FU-425)', () async {
      await put('c1', 'kosharyx');
      var resets = 0;
      final s2 = LlmCatSender(
        db,
        filler: filler,
        applier: sender.applier,
        call: sender.call,
        newRequestId: sender.newRequestId,
        terms: sender.terms,
        batchMax: sender.batchMax,
        allowedCategoryIds: sender.allowedCategoryIds,
        onConsentRequired: () async => resets++,
      );
      server.reply = (b) => problem(409, 'LLM_CONSENT_REQUIRED');
      await s2.run(now: _now, lang: LlmLang.en);
      expect(resets, 1);
      expect(await consent.read(LlmFeature.categorise), isNull);
      expect(await queued(), ['kosharyx']);
      // Nothing more is sent until the user agrees again.
      final n = server.bodies.length;
      await s2.run(
        now: _now.add(const Duration(minutes: 11)),
        lang: LlmLang.en,
      );
      expect(server.bodies, hasLength(n));
    });

    test('409 clears consent; 503 pauses until sync', () async {
      await put('c1', 'kosharyx');
      server.reply = (b) => problem(409, 'LLM_CONSENT_REQUIRED');
      await run();
      expect(await consent.read(LlmFeature.categorise), isNull);
      expect(await queued(), ['kosharyx']);
      await consent.grant(LlmFeature.categorise, 'openai-luna', 1);
      server.reply = (b) => problem(503, 'LLM_SERVICE_PAUSED');
      await run(_now.add(const Duration(minutes: 11)));
      expect(await quota.isPaused(LlmFeature.categorise), isTrue);
      final n = server.bodies.length;
      await run(_now.add(const Duration(hours: 3)));
      expect(server.bodies, hasLength(n));
    });

    test('switching off empties the queue', () async {
      await put('x1', 'kosharyx');
      await filler.fill(now: _now);
      expect(await queued(), isNotEmpty);
      await sender.switchedOff();
      expect(await queued(), isEmpty);
    });
  });

  group('untrusted replies', () {
    test('category outside the closed set, echoed stranger, repeat and '
        'wrong status are never applied', () async {
      await put('u1', 'kosharya');
      await put('u2', 'kosharyb');
      await put('u3', 'kosharyc');
      server.reply = (b) => _ok([
        _result('kosharya', category: 'crypto_casino'),
        _result('some stranger'),
        _result('kosharyb'),
        _result('kosharyb', category: 'bills'),
        _result('kosharyc', status: 'rejected'),
      ]);
      final r = await run();
      expect(await catOf('u1'), isNull);
      expect(await catOf('u2'), 'sys:food');
      expect(await catOf('u3'), isNull);
      expect(r.applied, 1);
      expect(r.noAnswer, 2);
      final s = AiMerchantSuggestionsDao(db);
      expect((await s.byMerchant('kosharya'))!.state, 'no_answer');
      expect(await s.byMerchant('some stranger'), isNull);
      // no_answer is never re-sent.
      expect(await queued(), isEmpty);
    });

    test('a malformed body is a failure, nothing applied', () async {
      await put('u1', 'kosharya');
      server.reply = (b) => jsonResponse(200, {'results': 'x'});
      final r = await run();
      expect(r.outcome, LlmCatSendOutcome.failed);
      expect(await catOf('u1'), isNull);
      expect(await queued(), ['kosharya']);
    });

    test('an AI answer fills only "needs classification" rows', () async {
      await put('v1', 'kosharya');
      await put('v2', 'kosharya', createdAt: t0 + 1);
      await db.customStatement(
        "UPDATE transactions SET category_id = 'sys:bills', "
        "category_source = 'user', is_user_verified = 1 WHERE id = 'v2'",
      );
      server.reply = (b) => _ok([_result('kosharya')]);
      await run();
      expect(await catOf('v1'), 'sys:food');
      expect(await catOf('v2'), 'sys:bills');
    });
  });

  group('negative proof 2: nothing is sent', () {
    Future<void> expectSilent() async {
      server.reply = (b) => _ok([_result('kosharyx')]);
      final r = await run(_now.add(const Duration(hours: 1)));
      expect(r.outcome, LlmCatSendOutcome.idle);
      expect(server.bodies, isEmpty);
      expect(prover.proofs, 0);
    }

    setUp(() => put('n1', 'kosharyx'));

    test('flag off', () async {
      flagOn = false;
      await expectSilent();
    });
    test('no consent', () async {
      await consent.clear(LlmFeature.categorise);
      await expectSilent();
    });
    test(
      'terms unknown (no provider id or names in the synced config, FU-425)',
      () async {
        terms = null;
        await expectSilent();
      },
    );
    test('paused until sync', () async {
      await quota.pause(LlmFeature.categorise);
      await expectSilent();
    });
    test('local quota 0 before the reset', () async {
      await quota.record(
        LlmFeature.categorise,
        LlmQuota(limit: 15, used: 15, remaining: 0, resetsAt: _resets),
      );
      await expectSilent();
    });
  });

  group('negative proof 1: the outgoing body', () {
    test('only eligible business merchants, closed fields, no amount, date, '
        'account or text; no name is logged', () async {
      // Eligible.
      await put('e1', 'kosharyx');
      // Person payees on wallet / InstaPay / transfer rows.
      await put('p1', 'rahul sharma', template: 'wal.pay');
      await put('p2', 'priya', template: 'wal.pay');
      await put('p3', 'mona hassan', template: 'ipa', cpKind: 'person');
      await put('p4', 'ahmed samir', template: 'wallet', cpKind: 'person');
      await put('p5', 'rahul sharma');
      // Manual entries.
      await put(
        'm1',
        'handmade bakery',
        source: 'manual',
        template: 'bank.card',
      );
      await put('m2', 'kosharym', source: 'manual');
      // Names with digits.
      await put('d1', 'order 000000 cafe');
      await put('d2', 'shop 0100 123 4567');
      // Mixed evidence: one business row, one wallet row.
      await put('x1', 'mixedshop');
      await put('x2', 'mixedshop', template: 'wal.pay');
      server.reply = (b) =>
          _ok([for (final m in b['merchants']! as List) _result('$m')]);
      await run();

      final body = server.bodies.single;
      expect(body.keys.toSet(), {
        'v',
        'requestId',
        'lang',
        'merchants',
        'consent',
        'attestation',
      });
      expect(body['merchants'], ['kosharyx']);
      expect(body['consent'], {'provider': 'openai-luna', 'v': 1});
      final wire = server.raw.single.toLowerCase();
      for (final leak in [
        'rahul',
        'sharma',
        'priya',
        'mona',
        'ahmed',
        'handmade',
        'bakery',
        'kosharym',
        '000000',
        '0100',
        '4567',
        'mixedshop',
        '7654321',
        '76543.21',
        'acc1',
        '2026',
        'sms',
        'egp',
      ]) {
        expect(wire, isNot(contains(leak)), reason: leak);
      }
      // No merchant name in any log line.
      expect(diag.rows.join(' ').toLowerCase(), isNot(contains('kosharyx')));
    });
  });
}
