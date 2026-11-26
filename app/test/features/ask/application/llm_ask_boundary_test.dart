// T-343: the data boundary of the online Ask flow, over the REAL gateway
// client and masker on an encrypted fixture database (synthetic data).
//
//  AC2  'NEGATIVE PROOF 1 ...': every request body has exactly the FR-LLM-02
//       fields; no body, header or URL holds a fixture merchant, account
//       label, last-4, registry alias or amount the user didn't type.
//  AC3  'NEGATIVE PROOF 2 ...': local answer, clarification, declined
//       consent, quota 0, offline and flag off make zero requests (the
//       transport saw nothing, not even the install call).
//  AC4  'AC4 ...': after an answer no table, setting or log holds sentText
//       or a placeholder.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/misc_daos.dart' show DiagLevel;
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/data/llm_ask_client.dart';
import 'package:zaghlol/features/ask/data/mask_sources_drift.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/domain/llm_answer_models.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/backend/backend_test_support.dart';
import '../../../core/db/financial_fixtures.dart';

final _now = DateTime.utc(2026, 11, 26, 10);
const _terms = LlmTerms(provider: 'openai-luna', v: askLlmConsentVersion);

Map<String, dynamic> _fallbackBody() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File(
      '${dir.path}/backend/contracts/fixtures/ask-plan-responses-v1.json',
    );
    if (f.existsSync()) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return ((j['ok'] as List).cast<Map<String, dynamic>>().firstWhere(
            (p) => p['name'] == 'PL-FALLBACK',
          ))['body']
          as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('fixture not found');
}

final class _Server implements BackendTransport {
  final List<BackendRequest> all = [];
  Object reply = _fallbackBody();

  @override
  Future<BackendResponse> send(BackendRequest r) async {
    all.add(r);
    if (r.uri.path == '/v1/installs') {
      return jsonResponse(201, {
        'installToken': fakeToken(1),
        'serverTime': '2026-11-26T10:00:00Z',
      });
    }
    return jsonResponse(200, reply);
  }
}

final class _Prover implements LlmProver {
  @override
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  }) async =>
      const LlmPlayIntegrityProof(token: 'synthetic.integrity-token.0001');
}

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

// ------------------------------------------------------------- fixture

Account _acc(
  String id,
  AccountKind kind,
  String label,
  String last4,
  String inst,
) => Account(
  id: id,
  kind: kind,
  label: label,
  defaultCurrency: Currency.of('EGP'),
  isHidden: false,
  isDefaultCash: false,
  createdAt: _now,
  updatedAt: _now,
  institutionCode: inst,
  last4: last4,
);

final _accounts = [
  _acc('acc1', AccountKind.debit, 'Ahmed Salary Card', '4321', 'cib'),
  _acc('acc2', AccountKind.account, 'Savings Zenith', '8765', 'banque_misr'),
  _acc('acc3', AccountKind.credit, 'Gold Shopping Visa', '1111', 'cib'),
];

const _registry = [
  InstitutionNames(code: 'cib', nameAr: 'البنك التجاري الدولي', nameEn: 'CIB'),
  InstitutionNames(
    code: 'banque_misr',
    nameAr: 'بنك مصر',
    nameEn: 'Banque Misr',
  ),
  InstitutionNames(
    code: 'vodafone_cash',
    nameAr: 'فودافون كاش',
    nameEn: 'Vodafone Cash',
  ),
];

/// Names that must never be in a request (merchants, account labels,
/// non-everyday registry aliases).
const _secretNames = [
  'carrefour',
  'Carrefour Maadi',
  'talabat',
  'TALABAT*EG',
  'zawya coffee',
  'Zawya Coffee Zamalek',
  'مكتبة النور',
  'مكتبة النور - وسط البلد',
  'Ahmed Salary Card',
  'Savings Zenith',
  'Gold Shopping Visa',
  'Banque Misr',
  'البنك التجاري الدولي',
  'فودافون كاش',
];
const _lastFours = ['4321', '8765', '1111'];
const _amounts = ['15600.00', '87.50', '3249.99'];

/// The adversarial questions: names, last-4s, banks, merchants, amounts,
/// phone numbers (SRS 10.1 style).
const _questions = [
  'how much did I spend at Carrefour Maadi last month',
  'what is my balance on Ahmed Salary Card',
  'balance of my card ending 4321',
  'صرفت كام بكارت 4321 في Talabat',
  'compare Zawya Coffee and Carrefour this month vs last month',
  'did I pay more than 15600 at Carrefour',
  'show spending on my CIB card',
  'how much in my Banque Misr savings account',
  'ايه رصيدي في Savings Zenith',
  'مكتبة النور صرفت فيها كام الشهر ده',
  'كام صرفت بفودافون كاش',
  'send 3249.99 to 01001234567 how much is left',
  'average spend on visa 1111 per month',
  'spend on TALABAT*EG last week',
  'how much did i spend on gold shopping visa',
  'how much did i spend on food last month',
];

class _Rig {
  _Rig._();

  late EncryptedDb edb;
  late AppDatabase db;
  final server = _Server();
  final diag = _Diag();
  final logs = <String>[];
  bool flagOn = true;
  bool online = true;
  late LlmConsentStore consent;
  late LlmQuotaStore quota;
  late LlmAskFlow flow;
  late SettingsDao dao;
  final List<Plan> executed = [];
  var understood = false;
  var allow = true;

  static Future<_Rig> create() async {
    final r = _Rig._();
    r.edb = await EncryptedDb.open(background: false);
    r.db = r.edb.db;
    await r.db.into(r.db.accounts).insert(account('acc1'));
    var n = 0;
    Future<void> add(String norm, String raw, int minor) => r.db
        .into(r.db.transactions)
        .insert(
          txn('t${n++}', amountMinor: minor, merchant: raw, merchantNorm: norm),
        );
    await add('carrefour', 'Carrefour Maadi', 1560000);
    await add('talabat', 'TALABAT*EG', 8750);
    await add('zawya coffee', 'Zawya Coffee Zamalek', 324999);
    await add('مكتبة النور', 'مكتبة النور - وسط البلد', 8750);
    r.dao = SettingsDao(r.db);
    final repo = SettingsRepository(r.dao, nowMs: () => 1);
    r.consent = LlmConsentStore(repo, nowMs: () => 2);
    r.quota = LlmQuotaStore(repo);
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
      transport: r.server,
      store: FakeBackendStore([]),
      diag: DiagLogger(r.diag),
      random: Random(5),
      now: () => _now,
    );
    final gateway = LlmGatewayClient(
      backend: backend,
      prover: _Prover(),
      consent: r.consent,
      quota: r.quota,
      isFlagOn: (f) => r.flagOn,
      now: () => _now,
    );
    r.flow = LlmAskFlow(
      local: (q) async => r.understood
          ? const AskUnavailableAnswer()
          : const AskFallbackAnswer(
              AskUnrecognizedReason.noIntent,
              askFallbackChips,
            ),
      sources: () => MaskSourcesDrift.load(
        r.db,
        accounts: () async => _accounts,
        registry: _registry,
      ),
      client: GatewayLlmAskClient(gateway),
      execute: (plan, map) async {
        r.executed.add(plan);
        return const LlmSafeSpendAnswer(daysRemaining: 1, figures: []);
      },
      consent: r.consent,
      quota: r.quota,
      prompter: _Prompter(r),
      isFlagOn: () => r.flagOn,
      terms: () => _terms,
      now: () => _now,
      isOnline: () async => r.online,
    );
    return r;
  }

  Future<List<AskLlmState>> ask(String q) => runZoned(
    () => _askNow(q),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => logs.add(line),
    ),
  );

  Future<List<AskLlmState>> _askNow(String q) => flow.ask(q).toList();

  Future<void> close() => edb.close();
}

final class _Prompter implements ConsentPrompter {
  _Prompter(this.r);
  final _Rig r;
  @override
  Future<bool> prompt(ConsentPrompt request) async => r.allow;
}

String _folded(String s) => foldKey(s.replaceAll(RegExp('⟦[A-Z_0-9]+⟧'), ' '));

Future<void> _grant(_Rig r) =>
    r.consent.grant(LlmFeature.ask, 'openai-luna', askLlmConsentVersion);

void main() {
  late _Rig r;
  final oldDebugPrint = debugPrint;
  setUp(() async {
    r = await _Rig.create();
    debugPrint = (m, {wrapWidth}) => r.logs.add(m ?? '');
  });
  tearDown(() async {
    debugPrint = oldDebugPrint;
    await r.close();
  });

  test('NEGATIVE PROOF 1: the only user-derived bytes in any request are '
      'MaskResult.sentText (+ lang, consent, ids, proof)', () async {
    await _grant(r);
    final sources = await MaskSourcesDrift.load(
      r.db,
      accounts: () async => _accounts,
      registry: _registry,
    );
    var sentCount = 0;
    for (final q in _questions) {
      final before = r.server.all.where((x) => x.uri.path == '/v1/ask/plan');
      final n = before.length;
      await r.ask(q);
      final reqs = r.server.all
          .where((x) => x.uri.path == '/v1/ask/plan')
          .toList();
      final expected = ReferenceMasker.mask(ClientScrub.apply(q).text, sources);
      if (expected is! MaskResult) {
        expect(reqs.length, n, reason: 'unresolved question was sent');
        continue;
      }
      expect(reqs.length, n + 1, reason: 'resolved question not sent');
      sentCount++;
      final req = reqs.last;
      final body = bodyJson(req);
      expect(body.keys.toSet(), {
        'planVersion',
        'requestId',
        'q',
        'lang',
        'consent',
        'attestation',
      });
      expect(body['q'], expected.sentText);
      expect(body['lang'], anyOf('ar', 'en'));
      expect(body['consent'], {'provider': 'openai-luna', 'v': 1});

      final wire = _folded(
        [
          req.uri.toString(),
          ...req.headers.values,
          utf8.decode(req.body!),
        ].join('\n'),
      );
      for (final name in _secretNames) {
        expect(
          wire.contains(foldKey(name)),
          isFalse,
          reason: 'a request carried a fixture name for: $q',
        );
      }
      final text = body['q']! as String;
      for (final d in _lastFours) {
        expect(
          RegExp('(?<![0-9])$d(?![0-9])').hasMatch(text),
          isFalse,
          reason: 'a last-4 was sent for: $q',
        );
      }
      for (final a in _amounts) {
        if (!q.contains(a)) {
          expect(text.contains(a), isFalse);
        }
      }
      // The phone number never travels either.
      expect(text.contains('01001234567'), isFalse);
    }
    expect(
      sentCount,
      greaterThanOrEqualTo(8),
      reason: 'proof must not be vacuous',
    );
  });

  test('NEGATIVE PROOF 2: no request for local, clarify, declined consent, '
      'quota 0, offline, flag off, paused, too long', () async {
    // Local answer.
    r.understood = true;
    await _grant(r);
    await r.ask('how much did I spend');
    r.understood = false;
    // Clarification: a card no account has.
    await r.ask('how much did I spend on my card ending 9999');
    // Offline.
    r.online = false;
    await r.ask('how much did i spend on food last month');
    r.online = true;
    // Flag off.
    r.flagOn = false;
    await r.ask('how much did i spend on food last month');
    r.flagOn = true;
    // Too long.
    await r.ask('x' * 301);
    // Paused.
    await r.quota.pause(LlmFeature.ask);
    await r.ask('how much did i spend on food last month');
    await r.quota.resumeAll();
    // Quota 0.
    await r.dao.write(
      'ask.llm_quota',
      LlmQuotaSnapshot(
        limit: 5,
        remaining: 0,
        resetsAt: DateTime.utc(2026, 11, 30, 22),
      ).toJson(),
      at: 1,
    );
    await r.ask('how much did i spend on food last month');
    await r.dao.delete('ask.llm_quota');
    // Declined consent.
    await r.consent.clear(LlmFeature.ask);
    r.allow = false;
    await r.ask('how much did i spend on food last month');
    expect(r.server.all, isEmpty);
  });

  test('AC4: after an answer no table, setting or log holds sentText or a '
      'placeholder', () async {
    await _grant(r);
    const q = 'how much did I spend at Carrefour Maadi on card ending 4321';
    final states = await r.ask(q);
    final a = states.last as AskLlmAnswered;
    expect(a.sentText, contains('⟦'));
    final dump = StringBuffer();
    final tables = await r.db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    for (final t in tables) {
      final rows = await r.db
          .customSelect('SELECT * FROM "${t.read<String>('name')}"')
          .get();
      for (final row in rows) {
        dump.writeln(row.data);
      }
    }
    dump.writeln(await r.dao.all());
    dump.writeAll(r.logs, '\n');
    dump.writeAll(r.diag.rows, '\n');
    final text = dump.toString();
    expect(text.contains(a.sentText), isFalse);
    expect(text.contains('⟦'), isFalse);
    // The question itself is not persisted either.
    expect(text.contains('how much did I spend at'), isFalse);
    // A consent and a quota snapshot were stored (the dump is not empty).
    expect(text, contains('ask.llm_consent'));
  });
}
