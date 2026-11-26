// T-348: the device test's fake backend, checked on the host with the app's
// own BackendClient: it signs like the backend (the pinned dev key verifies
// it), serves the fixture config and plans, counts quota and checks the dev
// proof. Synthetic keys made here; nothing real.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/llm/llm_attestation.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';

import '../../integration_test/support/fake_llm_backend.dart';
import '../core/backend/backend_test_support.dart' show FakeBackendStore;

Uint8List _b32(BigInt v) {
  final out = Uint8List(32);
  var r = v;
  for (var i = 31; i >= 0; i--) {
    out[i] = (r & BigInt.from(255)).toInt();
    r >>= 8;
  }
  return out;
}

String _file(String p) => File(p).readAsStringSync();

void main() {
  late FakeLlmBackend fake;
  late BackendClient client;
  late String devKey;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final p256 = ECDomainParameters('prime256v1');
    final rng = Random(7);
    var d = BigInt.zero;
    for (var i = 0; i < 32; i++) {
      d = (d << 8) | BigInt.from(rng.nextInt(256));
    }
    d = d % (p256.n - BigInt.one) + BigInt.one;
    final q = (p256.G * d)!;
    final pub = ResponseKey(
      kid: 's0000a',
      x: _b32(q.x!.toBigInteger()!),
      y: _b32(q.y!.toBigInteger()!),
    );
    devKey = base64.encode(List<int>.generate(40, (i) => (i * 3 + 1) & 255));
    fake = await FakeLlmBackend.start(
      port: 0,
      signKeyD: base64Url.encode(_b32(d)).replaceAll('=', ''),
      devProofKey: devKey,
      askPlanFixture: _file(
        '../backend/contracts/fixtures/ask-plan-responses-v1.json',
      ),
      syncConfigFixture: _file(
        'test/fixtures/llm/sync-config-provider-v1.json',
      ),
    );
    client = BackendClient(
      config: BackendConfig(
        baseUri: Uri.parse('http://127.0.0.1:${fake.port}'),
        verifier: ResponseSignatureVerifier([pub], allowDevKeys: true),
        allowInsecureLocalhost: true,
      ),
      identity: ClientIdentity(
        platform: ClientPlatform.android,
        appVersion: '1.2.3',
        build: '42',
      ),
      transport: IoBackendTransport(),
      store: FakeBackendStore([]),
    );
  });

  tearDown(() async {
    unawaited(Future.sync(client.dispose));
    await fake.close();
  });

  Future<AskPlanResponse> ask(String q, {String? key}) async {
    final installId = await client.ensureInstalled();
    final base = {
      'planVersion': 1,
      'requestId': '01JD5Z8K3M7Q2R4T6V8W0X1Y2Z',
      'q': q,
      'lang': 'en',
      'consent': {'provider': 'openai-luna', 'v': 1},
    };
    final hash = llmBodyHash(LlmFeature.ask, installId, jsonEncode(base));
    final proof = await DevLlmProver(key ?? devKey).prove(LlmFeature.ask, hash);
    return client.askPlan(
      AskPlanRequest(
        planVersion: 1,
        requestId: '01JD5Z8K3M7Q2R4T6V8W0X1Y2Z',
        q: q,
        lang: AskPlanRequestLang.en,
        consent: const LlmConsent(provider: 'openai-luna', v: 1),
        attestation: proof,
      ),
    );
  }

  test('sync is signed and carries the flag and the provider block', () async {
    final r = await client.sync(
      const SyncRequest(catalogVersion: 0, flagsVersion: 0),
      timeNonce: TimeNonce('A' * 22),
    );
    expect(r.flags!.values['ask_llm'], isTrue);
    expect(r.config!.values['llm.provider'], 'openai-luna');
    expect(r.config!.providerName!.en, 'Luna AI');
  });

  test('ask: fixture plan, own quota, proof checked', () async {
    fake.script([const AskReply.plan('PL-WHATIF-SAVE')]);
    final r = await ask('hello');
    expect(r.plan, isNotNull);
    expect(r.counted, isTrue);
    expect(r.quota.remaining, 4);
    expect(fake.proofOk, 1);
    expect(fake.askRequests, hasLength(1));
  });

  test('ask: a wrong proof key is DEVICE_ATTESTATION_FAILED', () async {
    fake.script([const AskReply.plan('PL-WHATIF-SAVE')]);
    final other = base64.encode(List<int>.filled(40, 9));
    await expectLater(
      ask('hello', key: other),
      throwsA(
        isA<BackendFailure>().having(
          (f) => f.problem,
          'problem',
          ProblemCode.deviceAttestationFailed,
        ),
      ),
    );
    expect(fake.proofBad, 1);
  });

  test('ask: quota, consent and paused problems', () async {
    fake.script([
      const AskReply.problem('LLM_QUOTA_EXHAUSTED'),
      const AskReply.providerSwitched409(),
      const AskReply.problem('LLM_SERVICE_PAUSED'),
    ]);
    await expectLater(
      ask('a'),
      throwsA(
        isA<BackendFailure>()
            .having((f) => f.problem, 'problem', ProblemCode.llmQuotaExhausted)
            .having((f) => f.llmQuota?.remaining, 'remaining', 0),
      ),
    );
    await expectLater(
      ask('b'),
      throwsA(
        isA<BackendFailure>().having(
          (f) => f.problem,
          'problem',
          ProblemCode.llmConsentRequired,
        ),
      ),
    );
    expect(fake.configVariant, 'switched');
    await expectLater(
      ask('c'),
      throwsA(
        isA<BackendFailure>().having(
          (f) => f.problem,
          'problem',
          ProblemCode.llmServicePaused,
        ),
      ),
    );
  });
}
