// T-340 AC3 (error table, 12 s timeout, Stop), AC4 (no request/response text
// in any log) and negative proof 3 (no send without flag, consent and local
// quota). The backend is a scripted transport answering with the contract
// fixtures (backend/contracts/fixtures/*-responses-v1.json). Synthetic data.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart' show DiagLevel;
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/logging/diag_logger.dart';
import 'package:zaghlol/core/platform/pigeon_attestation.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show MaskMap, MaskResult;

import '../backend/backend_test_support.dart';

const _marker = 'MARKER-Q-7f3a صرفت كام ⟦CARD_1⟧';
const _terms = LlmTerms(provider: 'openai-luna', v: 1);
final _now = DateTime.utc(2026, 11, 26, 10);

Map<String, dynamic> _fixtures(String name) {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/backend/contracts/fixtures/$name');
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('fixture $name not found');
}

final _ask = _fixtures('ask-plan-responses-v1.json');
final _cat = _fixtures('categorise-responses-v1.json');

Map<String, dynamic> _problemBody(Map<String, dynamic> f, String code) =>
    ((f['problems'] as List).cast<Map<String, dynamic>>().firstWhere(
          (p) => p['code'] == code,
        ))['body']
        as Map<String, dynamic>;

Map<String, dynamic> _okBody(Map<String, dynamic> f, String name) =>
    ((f['ok'] as List).cast<Map<String, dynamic>>().firstWhere(
          (p) => p['name'] == name,
        ))['body']
        as Map<String, dynamic>;

final class _MemDao implements SettingsDao {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value, {required int at}) async =>
      values[key] = value;
  @override
  Future<int> delete(String key) async => values.remove(key) == null ? 0 : 1;
  @override
  Stream<String?> watch(String key) => Stream.value(values[key]);
  @override
  Future<Map<String, String>> all() async => Map.of(values);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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

/// Answers installs itself; LLM calls with [reply] (or never, when null).
final class _Server implements BackendTransport {
  BackendResponse Function(BackendRequest r)? reply;
  final List<BackendRequest> llm = [];
  final List<BackendRequest> all = [];
  Completer<BackendResponse>? hang;

  @override
  Future<BackendResponse> send(BackendRequest r) async {
    all.add(r);
    if (r.uri.path == '/v1/installs') {
      return jsonResponse(201, {
        'installToken': fakeToken(1),
        'serverTime': '2026-11-26T10:00:00Z',
      });
    }
    llm.add(r);
    final h = hang;
    if (h != null) return h.future;
    return reply!(r);
  }
}

final class _Prover implements LlmProver {
  final List<Uint8List> hashes = [];
  final List<bool> forced = [];
  AttestationFailure? fail;

  @override
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  }) async {
    hashes.add(bodyHash);
    forced.add(forceNewKey);
    final f = fail;
    if (f != null) throw AttestationException(f);
    return const LlmPlayIntegrityProof(token: 'synthetic.integrity-token.0001');
  }
}

final class _Rig {
  _Rig({bool flagOn = true, Duration? timeout}) {
    flags = {FeatureFlag.askLlm: flagOn, FeatureFlag.llmCategorise: flagOn};
    backend = BackendClient(
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
    final repo = SettingsRepository(dao, nowMs: () => 1);
    consent = LlmConsentStore(repo, nowMs: () => 2);
    quota = LlmQuotaStore(repo);
    gateway = LlmGatewayClient(
      backend: backend,
      prover: prover,
      consent: consent,
      quota: quota,
      isFlagOn: (f) => flags[f] ?? false,
      now: () => _now,
      timeout: timeout ?? LlmGatewayClient.defaultTimeout,
    );
  }

  final server = _Server();
  final prover = _Prover();
  final dao = _MemDao();
  final diag = _Diag();
  late final Map<FeatureFlag, bool> flags;
  late final BackendClient backend;
  late final LlmConsentStore consent;
  late final LlmQuotaStore quota;
  late final LlmGatewayClient gateway;

  Future<void> allow() async {
    await consent.grant(LlmFeature.ask, 'openai-luna', 1);
    await consent.grant(LlmFeature.categorise, 'openai-luna', 1);
  }

  Future<AskPlanResponse> ask({AbortSignal? stop}) => gateway.askPlan(
    masked: const MaskResult(sentText: _marker, map: MaskMap({}), tokens: []),
    lang: LlmLang.ar,
    terms: _terms,
    stop: stop,
  );

  Future<CategoriseResponse> cat() => gateway.categorise(
    merchants: const ['zawya coffee', 'مكتبة النور'],
    lang: LlmLang.en,
    terms: _terms,
  );
}

void main() {
  group('happy path', () {
    test('ask: exactly the OpenAPI members, q = sentText, bound to the '
        'install, quota snapshot stored', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) => jsonResponse(200, _okBody(_ask, 'PL-SPEND'));
      final res = await r.ask();
      expect(res.plan.plan, AskPlanPlan.plSpend);
      final req = r.server.llm.single;
      expect(req.uri.path, '/v1/ask/plan');
      final body = bodyJson(req);
      expect(body.keys.toSet(), {
        'planVersion',
        'requestId',
        'q',
        'lang',
        'consent',
        'attestation',
      });
      expect(body['q'], _marker);
      expect(body['lang'], 'ar');
      expect(body['consent'], {'provider': 'openai-luna', 'v': 1});
      expect(
        body['requestId'],
        matches(RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$')),
      );
      // The prover got the hash of the very body that was sent.
      final installId = req.headers['zaghlol-install']!;
      expect(
        r.prover.hashes.single,
        llmBodyHash(LlmFeature.ask, installId, utf8.decode(req.body!)),
      );
      expect(
        await r.quota.current(LlmFeature.ask, _now),
        LlmQuotaSnapshot(
          limit: 5,
          remaining: 2,
          resetsAt: DateTime.utc(2026, 11, 30, 22),
        ),
      );
    });

    test('categorise: exactly the OpenAPI members; quota snapshot stored; '
        'duplicate names refused before anything is sent', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) =>
          jsonResponse(200, _okBody(_cat, 'mixed-batch-quota-trimmed'));
      final res = await r.cat();
      expect(res.results, hasLength(4));
      final body = bodyJson(r.server.llm.single);
      expect(body.keys.toSet(), {
        'v',
        'requestId',
        'lang',
        'merchants',
        'consent',
        'attestation',
      });
      expect(body['merchants'], ['zawya coffee', 'مكتبة النور']);
      expect(await r.quota.exhausted(LlmFeature.categorise, _now), isTrue);
      await r.quota.clear(LlmFeature.categorise);
      final before = r.server.all.length;
      await expectLater(
        () => r.gateway.categorise(
          merchants: const ['a shop', 'a shop'],
          lang: LlmLang.en,
          terms: _terms,
        ),
        throwsA(isA<LlmRequestRejected>()),
      );
      expect(r.server.all.length, before);
    });
  });

  group('negative proof 3: the gate sends nothing', () {
    Future<void> expectBlocked(_Rig r, LlmBlockReason reason) async {
      await expectLater(
        r.ask(),
        throwsA(isA<LlmBlocked>().having((e) => e.reason, 'reason', reason)),
      );
      expect(r.server.all, isEmpty, reason: 'no request at all');
      expect(r.prover.hashes, isEmpty, reason: 'no attestation');
    }

    test('flag off (stale or never synced reads off)', () async {
      final r = _Rig(flagOn: false);
      await r.allow();
      await expectBlocked(r, LlmBlockReason.flagOff);
    });

    test('no consent, or consent for another provider / version', () async {
      final r = _Rig();
      await expectBlocked(r, LlmBlockReason.noConsent);
      await r.consent.grant(LlmFeature.ask, 'gemini-flash-lite', 1);
      await expectBlocked(r, LlmBlockReason.noConsent);
      await r.consent.grant(LlmFeature.ask, 'openai-luna', 2);
      await expectBlocked(r, LlmBlockReason.noConsent);
    });

    test('paused until sync', () async {
      final r = _Rig();
      await r.allow();
      await r.quota.pause(LlmFeature.ask);
      await expectBlocked(r, LlmBlockReason.paused);
    });

    test('local quota 0 before resetsAt (and sends again after it)', () async {
      final r = _Rig();
      await r.allow();
      await r.quota.record(
        LlmFeature.ask,
        const LlmQuota(
          limit: 5,
          used: 5,
          remaining: 0,
          resetsAt: '2026-11-30T22:00:00Z',
        ),
      );
      await expectBlocked(r, LlmBlockReason.quotaExhausted);
      await r.quota.record(
        LlmFeature.ask,
        const LlmQuota(
          limit: 5,
          used: 5,
          remaining: 0,
          resetsAt: '2026-11-26T09:00:00Z',
        ),
      );
      r.server.reply = (_) => jsonResponse(200, _okBody(_ask, 'PL-SPEND'));
      await r.ask();
      expect(r.server.llm, hasLength(1));
    });
  });

  group('AC3 error table (ask-llm §4.1)', () {
    test('403 LLM_QUOTA_EXHAUSTED → snapshot stored, next call blocked '
        'locally', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) =>
          jsonResponse(403, _problemBody(_ask, 'LLM_QUOTA_EXHAUSTED'));
      final e = await r.ask().then<Object>(
        (_) => fail('no error'),
        onError: (Object e) => e,
      );
      expect(e, isA<LlmQuotaExhausted>());
      expect((e as LlmQuotaExhausted).quota?.remaining, 0);
      expect(await r.quota.exhausted(LlmFeature.ask, _now), isTrue);
      await expectLater(r.ask(), throwsA(isA<LlmBlocked>()));
      expect(r.server.llm, hasLength(1));
    });

    test('409 LLM_CONSENT_REQUIRED → consent cleared; the body\'s providerId '
        'is dropped (FU-425)', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) =>
          jsonResponse(409, _problemBody(_ask, 'LLM_CONSENT_REQUIRED'));
      await expectLater(r.ask(), throwsA(isA<LlmConsentRequired>()));
      expect(await r.consent.read(LlmFeature.ask), isNull);
      // A later grant is the app's own terms, never the 409's.
      expect(await r.consent.read(LlmFeature.categorise), isNotNull);
    });

    test('503 LLM_SERVICE_PAUSED → paused until sync', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) =>
          jsonResponse(503, _problemBody(_cat, 'LLM_SERVICE_PAUSED'));
      await expectLater(r.cat(), throwsA(isA<LlmServicePaused>()));
      expect(await r.quota.isPaused(LlmFeature.categorise), isTrue);
      expect(await r.quota.isPaused(LlmFeature.ask), isFalse);
    });

    final simple = <String, (int, Matcher)>{
      'DEVICE_ATTESTATION_FAILED': (
        422,
        isA<LlmAttestationFailed>().having(
          (e) => e.hadAttestationObject,
          'hadObject',
          false,
        ),
      ),
      'RATE_LIMITED': (
        429,
        isA<LlmRateLimited>().having(
          (e) => e.retryAfter,
          'retryAfter',
          isNotNull,
        ),
      ),
      'UPSTREAM_UNAVAILABLE': (502, isA<LlmUpstreamUnavailable>()),
      'VALIDATION_FAILED': (400, isA<LlmRequestRejected>()),
      'UNKNOWN_FIELD': (400, isA<LlmRequestRejected>()),
    };
    for (final e in simple.entries) {
      for (final feature in LlmFeature.values) {
        test('${e.value.$1} ${e.key} (${feature.name})', () async {
          final r = _Rig();
          await r.allow();
          final f = feature == LlmFeature.ask ? _ask : _cat;
          r.server.reply = (_) =>
              jsonResponse(e.value.$1, _problemBody(f, e.key));
          await expectLater(
            feature == LlmFeature.ask ? r.ask() : r.cat(),
            throwsA(e.value.$2),
          );
          // None of these touches consent, pause or the snapshot.
          expect(await r.consent.read(feature), isNotNull);
          expect(await r.quota.isPaused(feature), isFalse);
          expect(await r.quota.current(feature, _now), isNull);
        });
      }
    }

    test('503 UPSTREAM_UNAVAILABLE and an unknown 5xx → upstream', () async {
      final r = _Rig();
      await r.allow();
      r.server.reply = (_) => problem(503, 'UPSTREAM_UNAVAILABLE');
      await expectLater(r.ask(), throwsA(isA<LlmUpstreamUnavailable>()));
      r.server.reply = (_) => problem(500, 'INTERNAL');
      await expectLater(r.ask(), throwsA(isA<LlmUpstreamUnavailable>()));
    });

    test('a local attestation failure sends nothing', () async {
      final r = _Rig();
      await r.allow();
      r.prover.fail = AttestationFailure.playServicesOutdated;
      await expectLater(
        r.ask(),
        throwsA(
          isA<LlmAttestationUnavailable>().having(
            (e) => e.failure,
            'failure',
            AttestationFailure.playServicesOutdated,
          ),
        ),
      );
      expect(r.server.llm, isEmpty);
    });

    testWidgets('timeout at 12 s: still waiting at 11.9 s, LlmTimeout at '
        '12 s, and the request\'s abort signal fired', (tester) async {
      final r = _Rig();
      await tester.runAsync(r.allow);
      r.server.hang = Completer<BackendResponse>();
      Object? error;
      unawaited(r.ask().then((_) {}, onError: (Object e) => error = e));
      await tester.pump(const Duration(milliseconds: 11900));
      expect(r.server.llm, hasLength(1));
      expect(error, isNull);
      expect(r.server.llm.single.abort!.aborted, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(error, isA<LlmTimeout>());
      expect(r.server.llm.single.abort!.aborted, isTrue);
      // A reply after the timeout changes nothing.
      r.server.hang!.complete(jsonResponse(200, _okBody(_ask, 'PL-SPEND')));
      await tester.pump();
      expect(
        await tester.runAsync(() => r.quota.current(LlmFeature.ask, _now)),
        isNull,
      );
    });

    test(
      'Stop aborts the in-flight request; a late reply is dropped',
      () async {
        final r = _Rig();
        await r.allow();
        r.server.hang = Completer<BackendResponse>();
        final stop = AbortSignal();
        final f = r.ask(stop: stop);
        await Future<void>.delayed(Duration.zero);
        while (r.server.llm.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        stop.abort();
        await expectLater(f, throwsA(isA<LlmCancelled>()));
        expect(r.server.llm.single.abort!.aborted, isTrue);
        r.server.hang!.complete(
          jsonResponse(403, _problemBody(_ask, 'LLM_QUOTA_EXHAUSTED')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(await r.quota.current(LlmFeature.ask, _now), isNull);
      },
    );

    test('Stop before sending: nothing goes out', () async {
      final r = _Rig();
      await r.allow();
      final stop = AbortSignal()..abort();
      await expectLater(r.ask(stop: stop), throwsA(isA<LlmCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(r.server.llm, isEmpty);
    });
  });

  test('AC4: the marker question and the reply text never reach print, '
      'debugPrint, the diag log or an error\'s text', () async {
    final printed = <String>[];
    final saved = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add('$m');
    final errors = <String>[];
    final r = _Rig();
    try {
      await runZoned(
        () async {
          await r.allow();
          final replies = <BackendResponse Function()>[
            () =>
                jsonResponse(200, _okBody(_ask, 'PL-WHATIF-CUT-with-template')),
            for (final p
                in (_ask['problems'] as List).cast<Map<String, dynamic>>())
              () => jsonResponse(p['status'] as int, p['body'] as Object),
            () => throw const TransportException(TransportFailureKind.timeout),
            () => throw const TransportException(TransportFailureKind.offline),
          ];
          for (final next in replies) {
            r.server.reply = (_) => next();
            await r.consent.grant(LlmFeature.ask, 'openai-luna', 1);
            await r.quota.clear(LlmFeature.ask);
            try {
              final res = await r.ask();
              errors.add('$res ${res.plan} ${res.plan.t}');
            } on Object catch (e) {
              errors.add('$e');
            }
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
    } finally {
      debugPrint = saved;
    }
    expect(r.server.llm.length, greaterThanOrEqualTo(10));
    final template =
        (_okBody(_ask, 'PL-WHATIF-CUT-with-template')['plan'] as Map)['t']
            as Map;
    final everything = [...printed, ...r.diag.rows, ...errors].join('\n');
    expect(r.diag.rows, isNotEmpty, reason: 'failures are recorded as codes');
    expect(everything, isNot(contains('MARKER-Q-7f3a')));
    expect(everything, isNot(contains('⟦CARD_1⟧')));
    expect(everything, isNot(contains(template['text'] as String)));
  });
}
