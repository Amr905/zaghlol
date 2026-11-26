// T-171 check 2 (testing-strategy §1 "Privacy", §6), client level: every
// operation BackendClient can send, with every optional member filled in,
// on both platforms, recorded by RecordingBackendTransport and checked
// against the hand-written BR-SYNC-03 allow-list (support/br_sync_03.dart).
// The app-flow level is data_boundary_flows_test.dart. Synthetic data only.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/debug/recording_transport.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/features/settings/presentation/server_allow_list.dart';

import '../core/backend/backend_test_support.dart';
import 'support/br_sync_03.dart';
import 'support/fake_server.dart';

final int _t0 = DateTime.utc(2026, 11, 13, 10).millisecondsSinceEpoch;
const _jws = 'eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln';

String _b64u(int seed, int n) => base64Url
    .encode(List<int>.generate(n, (i) => (seed * 31 + i) & 0xff))
    .replaceAll('=', '');

/// `B[A-P]` + 85 chars: a 65-byte uncompressed P-256 point.
String _pk(int seed) => base64Url
    .encode([4, for (var i = 0; i < 64; i++) (seed + i) & 0xff])
    .replaceAll('=', '');
SeatKeyProof _seat(int seed) =>
    SeatKeyProof(publicKey: _pk(seed), signature: _b64u(seed, 64));

final class _Session {
  _Session(this.platform) {
    server = FakeZaghlolServer(
      nowMs: () => _t0,
      entitlementToken: (_) => _jws,
      accountToken: (_) => _jws,
    );
    recorder = RecordingBackendTransport(server);
    client = BackendClient(
      config: BackendConfig(
        baseUri: Uri.parse('https://api.test.invalid'),
        verifier: ResponseSignatureVerifier([server.responseKey.publicKey]),
      ),
      identity: ClientIdentity(
        platform: platform,
        appVersion: '1.0.0',
        build: '7',
      ),
      transport: recorder,
      store: store,
      random: Random(17),
      now: () => DateTime.fromMillisecondsSinceEpoch(_t0, isUtc: true),
    );
  }

  final ClientPlatform platform;
  late final FakeZaghlolServer server;
  late final RecordingBackendTransport recorder;
  late final BackendClient client;
  final store = FakeBackendStore([]);
  int _n = 0;

  TimeNonce nonce() => TimeNonce('${'n${_n++}'.padRight(21, 'x')}A');

  /// Every operation, all optional members set.
  Future<void> everything() async {
    final ios = platform == ClientPlatform.ios;
    await client.ensureInstalled();
    await client.sync(
      const SyncRequest(
        catalogVersion: 4,
        flagsVersion: 2,
        pricesAsOf: '2026-11-13T09:00:00Z',
        entitlementIssuedAt: '2026-11-13T08:00:00Z',
        registryVersion: 12,
        contributions: [
          ContributionInput(
            merchantNorm: 'synthetic cafe',
            institutionCode: 'cib',
            categoryCode: 'food',
          ),
        ],
        bankRequests: [
          BankRequestInput(
            institutionName: 'Synthetic Bank',
            country: 'EG',
            channel: BankRequestInputChannel.sms,
          ),
        ],
      ),
      timeNonce: nonce(),
    );
    try {
      await client.getFullCatalog(5);
    } on BackendFailure {
      // The fake has no snapshot; only the request matters here.
    }
    await client.verifyPurchase(
      client.prepareVerify(
        ios
            ? PurchaseVerifyIosRequest(
                signedTransaction: _jws,
                seatKeys: [_seat(1)],
              )
            : const PurchaseVerifyAndroidRequest(
                productId: 'zaghlol_gold_yearly',
                purchaseToken: 'synthetic-play-token-0001',
              ),
      ),
      timeNonce: nonce(),
    );
    await client.restorePurchases(
      ios
          ? PurchaseRestoreIosRequest(
              signedTransactions: const [_jws],
              attestation: AppAttestProof(
                keyId: '${'A' * 43}=',
                assertion: 'c3ludGhldGljLWFzc2VydGlvbg==',
                attestationObject: 'c3ludGhldGljLW9iamVjdA==',
                seatKeys: [for (var i = 1; i <= 5; i++) _seat(i)],
              ),
            )
          : const PurchaseRestoreAndroidRequest(
              purchases: [
                AndroidPurchaseRef(
                  productId: 'zaghlol_gold_yearly',
                  purchaseToken: 'synthetic-play-token-0001',
                ),
              ],
              attestation: PlayIntegrityProof(
                token: 'synthetic.integrity-token.0001',
              ),
            ),
      timeNonce: nonce(),
    );
    await client.getEntitlement(timeNonce: nonce());
    await client.signIn(
      client.prepareSignIn(
        SignInRequest(
          provider: ios
              ? SignInRequestProvider.apple
              : SignInRequestProvider.google,
          idToken: _jws,
          nonce: _b64u(9, 24),
          authorizationCode: 'synthetic-auth-code',
          replaceLink: true,
          seatKeys: ios ? [for (var i = 1; i <= 5; i++) _seat(i)] : null,
        ),
      ),
      timeNonce: nonce(),
    );
    // The account token is stored by the account service in production;
    // set it here so the account-scoped calls can run.
    await store.write(
      BackendStateKeys.accountToken,
      Uint8List.fromList(utf8.encode(_jws)),
    );
    await client.getEntitlement(timeNonce: nonce());
    // T-340: the LLM gateway calls, every member filled (iOS with the
    // first-use attestation object), with the account token present.
    final LlmAttestation llmProof = ios
        ? LlmAppAttestProof(
            keyId: '${'A' * 43}=',
            assertion: 'c3ludGhldGljLWFzc2VydGlvbg==',
            attestationObject: 'c3ludGhldGljLW9iamVjdA==',
          )
        : const LlmPlayIntegrityProof(token: 'synthetic.integrity-token.0001');
    await client.askPlan(
      AskPlanRequest(
        planVersion: 1,
        requestId: client.newIdempotencyKey().value,
        q: 'صرفت كام بكارت ⟦CARD_1⟧ في ⟦MERCHANT_1⟧؟',
        lang: AskPlanRequestLang.ar,
        consent: const LlmConsent(provider: 'openai-luna', v: 1),
        attestation: llmProof,
      ),
    );
    await client.categorise(
      CategoriseRequest(
        v: 1,
        requestId: client.newIdempotencyKey().value,
        lang: CategoriseRequestLang.en,
        merchants: const ['zawya coffee', 'مكتبة النور'],
        consent: const LlmConsent(provider: 'openai-luna', v: 1),
        attestation: llmProof,
      ),
    );
    await client.signOut(timeNonce: nonce());
    await client.deleteAccount();
    await client.deleteInstall();
  }
}

/// Operations in the OpenAPI spec with no client call yet (T-340 added the
/// two LLM calls).
const _plannedNotInClient = <String>{};

void main() {
  for (final platform in ClientPlatform.values) {
    final name = platform.name;
    test('$name: every operation, fully populated, stays inside the '
        'BR-SYNC-03 allow-list (members, headers, time nonce on the six '
        'anchoring requests only)', () async {
      final s = _Session(platform);
      await s.everything();
      final seen = <String>{};
      final classes = <WireClass>{};
      for (final r in s.recorder.requests) {
        final c = checkRequest(r, platform: name);
        expect(c.violations, isEmpty, reason: c.op);
        seen.add(c.op);
        classes.addAll(c.classes);
      }
      // Every operation in the generated table was exercised, except the
      // spec-first M9 operations the client can't call yet. Each M9 client
      // task (docs/04-tasks/m9-llm-plan.md) removes its entry here and adds
      // the call to `everything()`; an entry the client does send fails.
      final all = {for (final o in ApiOperations.all) '${o.method} ${o.path}'};
      expect(all, containsAll(_plannedNotInClient));
      // T-340: both LLM classes went out and only on their own operation.
      expect(
        classes,
        containsAll([WireClass.llmQuestion, WireClass.llmMerchants]),
      );
      expect(seen.intersection(_plannedNotInClient), isEmpty);
      expect(seen, all.difference(_plannedNotInClient));
      // The six anchoring requests carried a time nonce (checked per
      // request above); seat keys travelled on iOS only.
      expect(classes.contains(WireClass.seatKeys), platform.name == 'ios');
      // Every wire class is disclosed on the privacy screen of this
      // platform (FR-ONB-07, security-model §2 item 5).
      final shown = serverAllowList(name).toSet();
      for (final c in classes) {
        if (c.disclosedAs != null) {
          expect(shown, contains(c.disclosedAs), reason: c.name);
        }
      }
    });
  }

  test('the allow-list holds the D-45/D-55/D-62 additions and nothing else '
      'device-related', () {
    Set<String> paths(Node n, String at) => switch (n) {
      Obj(:final members) => {
        for (final e in members.entries) ...{
          '$at.${e.key}',
          ...paths(e.value, '$at.${e.key}'),
        },
      },
      Arr(:final item) => paths(item, '$at[]'),
      Leaf() => const {},
    };
    Set<String> classed(Map<String, Obj> bodies, WireClass c) {
      final out = <String>{};
      void walk(String op, Node n, String at) {
        switch (n) {
          case Obj(:final members):
            members.forEach((k, v) => walk(op, v, '$at.$k'));
          case Arr(:final item):
            walk(op, item, '$at[]');
          case Leaf(:final cls):
            if (cls == c) out.add('$op $at');
        }
      }

      bodies.forEach((op, o) => walk(op, o, r'$'));
      return out;
    }

    // Attestation: restore (D-45) and the two LLM requests (FR-LLM-14).
    const attestedOps = {
      'POST /v1/purchases/restore',
      'POST /v1/ask/plan',
      'POST /v1/categorise',
    };
    expect(classed(androidBodies, WireClass.attestation), {
      for (final op in attestedOps) ...{
        '$op \$.attestation.type',
        '$op \$.attestation.token',
      },
    });
    expect(
      classed(
        iosBodies,
        WireClass.attestation,
      ).map((p) => p.split(r' $').first).toSet(),
      attestedOps,
    );
    // The question only on ask, merchant names only on categorise (D-90,
    // D-96), never anywhere else.
    for (final bodies in [androidBodies, iosBodies]) {
      expect(classed(bodies, WireClass.llmQuestion), {
        r'POST /v1/ask/plan $.q',
        r'POST /v1/ask/plan $.lang',
      });
      expect(classed(bodies, WireClass.llmMerchants), {
        r'POST /v1/categorise $.lang',
        r'POST /v1/categorise $.merchants[]',
      });
    }
    // seatKeys: iOS only, on verify, restore and sign-in (D-62 v1.8).
    expect(classed(androidBodies, WireClass.seatKeys), isEmpty);
    expect(
      {
        for (final p in classed(iosBodies, WireClass.seatKeys))
          p.split(r' $').first,
      },
      {
        'POST /v1/purchases/verify',
        'POST /v1/purchases/restore',
        'POST /v1/accounts/signin',
      },
    );
    for (final b in androidBodies.values) {
      expect(paths(b, r'$').where((p) => p.contains('seatKeys')), isEmpty);
    }
    // Time nonce: exactly the six anchoring requests.
    expect(
      anchoring,
      ApiOperations.all
          .where((o) => o.anchoring)
          .map((o) => '${o.method} ${o.path}')
          .toSet(),
    );
    expect(anchoring, hasLength(6));
    // No header beyond the protocol set: nothing device-related.
    expect(allowedHeaders, isNot(contains('user-agent')));
    expect(allowedHeaders, isNot(contains('accept-language')));
  });

  group('negative proofs', () {
    test('an Android client refuses seatKeys and every iOS variant before '
        'anything is sent', () async {
      final s = _Session(ClientPlatform.android);
      await s.client.ensureInstalled();
      final before = s.recorder.requests.length;
      Matcher bug() => throwsA(
        isA<BackendFailure>().having(
          (f) => f.kind,
          'kind',
          BackendFailureKind.clientBug,
        ),
      );
      expect(
        () => s.client.prepareSignIn(
          SignInRequest(
            provider: SignInRequestProvider.google,
            idToken: _jws,
            nonce: _b64u(9, 24),
            seatKeys: [_seat(1)],
          ),
        ),
        bug(),
      );
      expect(
        () => s.client.prepareVerify(
          PurchaseVerifyIosRequest(
            signedTransaction: _jws,
            seatKeys: [_seat(1)],
          ),
        ),
        bug(),
      );
      await expectLater(
        s.client.restorePurchases(
          PurchaseRestoreIosRequest(
            signedTransactions: const [_jws],
            attestation: AppAttestProof(
              keyId: '${'A' * 43}=',
              assertion: 'c3ludGhldGljLWFzc2VydGlvbg==',
              seatKeys: [_seat(1)],
            ),
          ),
          timeNonce: s.nonce(),
        ),
        bug(),
      );
      expect(s.recorder.requests.length, before);
    });

    test('the checker itself flags an extra member, an extra header, a '
        'misplaced time nonce and seatKeys on Android', () {
      BackendRequest req(
        String method,
        String path,
        Map<String, Object?>? body, {
        Map<String, String> extra = const {},
      }) => BackendRequest(
        method: method,
        uri: Uri.parse('https://api.test.invalid$path'),
        headers: {
          'zaghlol-app': 'android/1.0.0 (7)',
          'accept': 'application/json',
          if (body != null) 'content-type': 'application/json',
          'authorization': 'Bearer x',
          'zaghlol-install': '0b9f3c1e-aaaa-4aaa-8aaa-000000000001',
          ...extra,
        },
        body: body == null
            ? null
            : Uint8List.fromList(utf8.encode(jsonEncode(body))),
      );
      const n = {'zaghlol-time-nonce': 'abcdefghijklmnopqrstuA'};

      final amount = checkRequest(
        req('POST', '/v1/sync', {
          'catalogVersion': 1,
          'flagsVersion': 1,
          'contributions': [
            {
              'merchantNorm': 'x',
              'institutionCode': 'cib',
              'categoryCode': 'food',
              'amountMinor': 12050,
            },
          ],
        }, extra: n),
        platform: 'android',
      );
      expect(
        amount.violations.single,
        contains('contributions[0].amountMinor'),
      );

      final header = checkRequest(
        req(
          'GET',
          '/v1/entitlement',
          null,
          extra: {...n, 'accept-language': 'ar-EG'},
        ),
        platform: 'android',
      );
      expect(header.violations.single, contains('accept-language'));

      final misplaced = checkRequest(
        req('DELETE', '/v1/installs/me', null, extra: n),
        platform: 'android',
      );
      expect(misplaced.violations.single, contains('time nonce'));

      final seat = checkRequest(
        req(
          'POST',
          '/v1/accounts/signin',
          {
            'provider': 'google',
            'idToken': _jws,
            'nonce': _b64u(9, 24),
            'seatKeys': [
              {'publicKey': _pk(1), 'signature': _b64u(1, 64)},
            ],
          },
          extra: {...n, 'idempotency-key': 'k'},
        ),
        platform: 'android',
      );
      expect(seat.violations.single, contains(r'$.seatKeys'));
    });
  });
}
