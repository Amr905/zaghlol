// T-141: BackendClient against a scripted fake server. Synthetic data only.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/debug/recording_transport.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/backend/transport.dart';
import 'package:zaghlol/core/db/daos/misc_daos.dart' show DiagLevel;
import 'package:zaghlol/core/logging/diag_logger.dart';

import 'backend_test_support.dart';

const _serverTime = '2026-11-13T10:00:00Z';
final _nonce = TimeNonce('kq3V9w0bQ2FwdGFpblphZw');

final class _CapturingDiag implements DiagStore {
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

final class _Harness {
  _Harness({ClientPlatform platform = ClientPlatform.android, Random? random}) {
    store = FakeBackendStore(log);
    transport = FakeTransport(log, (r) async => throw StateError('no route'));
    client = BackendClient(
      config: BackendConfig(
        baseUri: Uri.parse('https://api.test.invalid'),
        verifier: ResponseSignatureVerifier([key.publicKey]),
      ),
      identity: ClientIdentity(
        platform: platform,
        appVersion: '1.2.3',
        build: '42',
      ),
      transport: transport,
      store: store,
      diag: DiagLogger(diag),
      random: random,
      now: () => DateTime.utc(2026, 11, 13, 10),
    );
  }

  final List<String> log = [];
  final key = TestSigningKey('s2026a');
  final diag = _CapturingDiag();
  late final FakeBackendStore store;
  late final FakeTransport transport;
  late final BackendClient client;
  int tokens = 0;

  /// Default server: registers installs; answers [routes] by path.
  void serve(Map<String, Handler> routes) {
    transport.handler = (r) async {
      final h = routes[r.uri.path];
      if (h != null) return h(r);
      if (r.uri.path == '/v1/installs') {
        return jsonResponse(201, {
          'installToken': fakeToken(++tokens),
          'serverTime': _serverTime,
        });
      }
      throw StateError('no route');
    };
  }

  BackendResponse signedEntitlement({String? rotate}) => jsonResponse(200, {
    'entitlement': {'token': 'aGVhZGVy.cGF5bG9hZA.c2ln'},
    'serverTime': _serverTime,
    'timeNonce': _nonce.value,
    'rotateInstallToken': ?rotate,
  }, signWith: key);

  void seedInstall({String id = '00000000-0000-4000-8000-000000000001'}) {
    store.values[BackendStateKeys.installId] = _b(id);
    store.values[BackendStateKeys.installToken] = _b(fakeToken(900));
  }
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

const _syncReq = SyncRequest(catalogVersion: 1, flagsVersion: 1);

Map<String, Object?> _syncBody() => {
  'serverTime': _serverTime,
  'nextSyncNotBefore': '2026-11-14T10:00:00Z',
  'timeNonce': _nonce.value,
};

void main() {
  group('response signatures (AC: unsigned or tampered response rejected)', () {
    test('a correctly signed sync answer is decoded', () async {
      final h = _Harness();
      h.serve({
        '/v1/sync': (r) async =>
            jsonResponse(200, _syncBody(), signWith: h.key),
      });
      final out = await h.client.sync(_syncReq, timeNonce: _nonce);
      expect(out.timeNonce, _nonce.value);
    });

    for (final c in <String, BackendResponse Function(TestSigningKey)>{
      'unsigned': (k) => jsonResponse(200, _syncBody()),
      'tampered': (k) {
        final good = jsonResponse(200, _syncBody(), signWith: k);
        final body = Uint8List.fromList(good.body)..[3] ^= 0x01;
        return BackendResponse(status: 200, headers: good.headers, body: body);
      },
      'signed twice': (k) {
        final good = jsonResponse(200, _syncBody(), signWith: k);
        final sig = good.single('zaghlol-signature')!;
        return BackendResponse(
          status: 200,
          headers: {
            'zaghlol-signature': [sig, sig],
          },
          body: good.body,
        );
      },
      'signed by an unpinned key': (k) => jsonResponse(
        200,
        _syncBody(),
        signWith: TestSigningKey('s2026b', seed: 9),
      ),
    }.entries) {
      test('${c.key} answer is dropped', () async {
        final h = _Harness();
        h.serve({'/v1/sync': (r) async => c.value(h.key)});
        await expectLater(
          h.client.sync(_syncReq, timeNonce: _nonce),
          throwsA(
            isA<BackendFailure>().having(
              (f) => f.kind,
              'kind',
              BackendFailureKind.badSignature,
            ),
          ),
        );
        expect(h.diag.rows.single, startsWith('BACKEND_BAD_SIGNATURE'));
      });
    }
  });

  group('lazy registration (backend-api §4.1, R3-6)', () {
    test(
      'the first sync registers; only allowed headers and members are sent',
      () async {
        final h = _Harness();
        h.serve({
          '/v1/sync': (r) async =>
              jsonResponse(200, _syncBody(), signWith: h.key),
        });
        await h.client.sync(_syncReq, timeNonce: _nonce);
        final reg = h.transport.requests[0];
        final sync = h.transport.requests[1];
        expect(reg.uri.toString(), 'https://api.test.invalid/v1/installs');
        expect(reg.headers.keys.toSet(), {
          'zaghlol-app',
          'accept',
          'content-type',
          'idempotency-key',
        });
        expect(reg.headers['zaghlol-app'], 'android/1.2.3 (42)');
        final body = bodyJson(reg);
        expect(body.keys.toSet(), {'installId', 'platform', 'appVersion'});
        expect(body['platform'], 'android');
        expect(sync.headers.keys.toSet(), {
          'zaghlol-app',
          'accept',
          'content-type',
          'zaghlol-time-nonce',
          'authorization',
          'zaghlol-install',
        });
        expect(sync.headers['zaghlol-install'], body['installId']);
        expect(sync.headers['authorization'], 'Bearer ${fakeToken(1)}');
        expect(await h.client.installId(), body['installId']);
        expect(
          h.store.values.containsKey(BackendStateKeys.registration),
          isFalse,
        );
      },
    );

    test('409 INSTALL_EXISTS gives a new install ID and a new key', () async {
      final h = _Harness();
      var n = 0;
      h.serve({
        '/v1/installs': (r) async => ++n == 1
            ? problem(409, 'INSTALL_EXISTS')
            : jsonResponse(201, {
                'installToken': fakeToken(5),
                'serverTime': _serverTime,
              }),
      });
      final id = await h.client.ensureInstalled();
      final a = h.transport.requests[0];
      final b = h.transport.requests[1];
      expect(bodyJson(a)['installId'], isNot(bodyJson(b)['installId']));
      expect(a.headers['idempotency-key'], isNot(b.headers['idempotency-key']));
      expect(id, bodyJson(b)['installId']);
    });

    test(
      'a lost 201 is retried with the same key and the same body bytes',
      () async {
        final h = _Harness();
        var n = 0;
        h.serve({
          '/v1/installs': (r) async {
            if (++n == 1) {
              // The server registered, but the answer never arrived.
              throw const TransportException(TransportFailureKind.timeout);
            }
            return jsonResponse(201, {
              'installToken': fakeToken(6),
              'serverTime': _serverTime,
            });
          },
        });
        await expectLater(
          h.client.ensureInstalled(),
          throwsA(
            isA<BackendFailure>().having(
              (f) => f.kind,
              'kind',
              BackendFailureKind.timeout,
            ),
          ),
        );
        expect(
          h.store.values.containsKey(BackendStateKeys.installToken),
          isFalse,
        );
        await h.client.ensureInstalled();
        final a = h.transport.requests[0];
        final b = h.transport.requests[1];
        expect(b.headers['idempotency-key'], a.headers['idempotency-key']);
        expect(b.body, a.body);
        expect(h.store.text(BackendStateKeys.installToken), fakeToken(6));
      },
    );

    test('two concurrent callers share one registration', () async {
      final h = _Harness()..serve({});
      final ids = await Future.wait([
        h.client.ensureInstalled(),
        h.client.ensureInstalled(),
      ]);
      expect(ids[0], ids[1]);
      expect(
        h.transport.requests.where((r) => r.uri.path == '/v1/installs'),
        hasLength(1),
      );
    });
  });

  group('R5-1 re-registration', () {
    test('entitlement and account tokens are deleted before the new '
        'POST /v1/installs, and InstallReregistered fires', () async {
      final h = _Harness()..seedInstall();
      h.store.values[BackendStateKeys.entitlementToken] = _b('ent');
      h.store.values[BackendStateKeys.accountToken] = _b('acct');
      final events = <BackendEvent>[];
      h.client.events.listen(events.add);
      h.serve({
        '/v1/entitlement': (r) async => problem(401, 'INSTALL_TOKEN_INVALID'),
      });
      h.log.clear();
      await expectLater(
        h.client.getEntitlement(timeNonce: _nonce),
        throwsA(
          isA<BackendFailure>().having(
            (f) => f.kind,
            'kind',
            BackendFailureKind.installReset,
          ),
        ),
      );
      await pumpEventQueue();
      final ent = h.log.indexOf('delete ${BackendStateKeys.entitlementToken}');
      final acct = h.log.indexOf('delete ${BackendStateKeys.accountToken}');
      final reg = h.log.indexOf('send POST /v1/installs');
      expect(ent, greaterThanOrEqualTo(0));
      expect(acct, greaterThanOrEqualTo(0));
      expect(reg, greaterThan(ent));
      expect(reg, greaterThan(acct));
      expect(events, [isA<InstallReregistered>()]);
      expect(
        await h.client.installId(),
        isNot('00000000-0000-4000-8000-000000000001'),
      );
      expect(
        h.store.values.containsKey(BackendStateKeys.reregistration),
        isFalse,
      );
      expect(
        h.diag.rows.any((r) => r.startsWith('INSTALL_REREGISTERED')),
        isTrue,
      );
    });

    test('an unknown 401 code deletes nothing', () async {
      final h = _Harness()..seedInstall();
      h.store.values[BackendStateKeys.entitlementToken] = _b('ent');
      h.serve({'/v1/entitlement': (r) async => problem(401, 'SOMETHING_NEW')});
      await expectLater(
        h.client.getEntitlement(timeNonce: _nonce),
        throwsA(isA<BackendFailure>()),
      );
      expect(h.store.text(BackendStateKeys.entitlementToken), 'ent');
      expect(h.log.where((l) => l.startsWith('delete')), isEmpty);
    });

    test(
      'a 401 for a token that was already replaced deletes nothing',
      () async {
        final h = _Harness()..seedInstall();
        h.store.values[BackendStateKeys.entitlementToken] = _b('ent');
        h.serve({
          '/v1/entitlement': (r) async {
            // Another actor re-registered while this call was in flight.
            h.store.values[BackendStateKeys.installToken] = _b(fakeToken(77));
            return problem(401, 'INSTALL_TOKEN_INVALID');
          },
        });
        await expectLater(
          h.client.getEntitlement(timeNonce: _nonce),
          throwsA(isA<BackendFailure>()),
        );
        expect(h.store.text(BackendStateKeys.entitlementToken), 'ent');
        expect(h.store.text(BackendStateKeys.installToken), fakeToken(77));
      },
    );
  });

  group('Idempotency-Key (R3-6)', () {
    test(
      'built from the injected CSPRNG: 80 random bits after the time',
      () async {
        final rng = ScriptedRandom([0xff]);
        final h = _Harness(random: rng);
        final key = h.client.newIdempotencyKey();
        expect(rng.calls, 10);
        // 80 one-bits are 16 Crockford 'Z's.
        expect(key.value.substring(10), 'Z' * 16);
        final other = _Harness(random: ScriptedRandom([0])).client
            .newIdempotencyKey();
        expect(other.value.substring(10), '0' * 16);
        expect(other.value.substring(0, 10), key.value.substring(0, 10));
      },
    );

    test('never appears in the diag log or in any toString', () async {
      final h = _Harness()..seedInstall();
      h.serve({
        '/v1/purchases/verify': (r) async => problem(503, 'STORE_UNAVAILABLE'),
        '/v1/installs': (r) async => problem(500, 'INTERNAL'),
      });
      final body = h.client.prepareVerify(
        const PurchaseVerifyAndroidRequest(
          productId: 'gold.monthly',
          purchaseToken: 'synthetic',
        ),
      );
      Object? failure;
      try {
        await h.client.verifyPurchase(body, timeNonce: _nonce);
      } on BackendFailure catch (e) {
        failure = e;
      }
      // A registration failure goes through the same paths.
      h.store.values.remove(BackendStateKeys.installToken);
      Object? regFailure;
      try {
        await h.client.ensureInstalled();
      } on BackendFailure catch (e) {
        regFailure = e;
      }
      final keys = h.transport.requests
          .map((r) => r.headers['idempotency-key']!)
          .toList();
      expect(keys, hasLength(2));
      expect(h.diag.rows, isNotEmpty);
      final everything = [
        ...h.diag.rows,
        '$failure',
        '$regFailure',
        '$body',
        '${body.key}',
        ...h.transport.requests.map((r) => '$r'),
      ].join('\n');
      for (final k in keys) {
        expect(everything.contains(k), isFalse);
      }
      expect(everything.contains(fakeToken(900)), isFalse);
    });

    test(
      'a retried verify reuses its key and bytes only through reuseKey',
      () async {
        final h = _Harness()..seedInstall();
        h.serve({
          '/v1/purchases/verify': (r) async => jsonResponse(200, {
            'status': 'active',
            'serverTime': _serverTime,
            'timeNonce': _nonce.value,
          }, signWith: h.key),
        });
        const req = PurchaseVerifyAndroidRequest(
          productId: 'gold.monthly',
          purchaseToken: 'synthetic',
        );
        final first = h.client.prepareVerify(req);
        final again = h.client.prepareVerify(req, reuseKey: first.key);
        final fresh = h.client.prepareVerify(req);
        expect(again.key, first.key);
        expect(fresh.key, isNot(first.key));
        await h.client.verifyPurchase(first, timeNonce: _nonce);
        await h.client.verifyPurchase(again, timeNonce: _nonce);
        final sent = h.transport.requests;
        expect(
          sent[0].headers['idempotency-key'],
          sent[1].headers['idempotency-key'],
        );
        expect(sent[0].body, sent[1].body);
      },
    );
  });

  group('anchoring (R4-2)', () {
    test(
      'an anchoring call without a time nonce fails fast (assert)',
      () async {
        final h = _Harness()..seedInstall();
        h.serve({});
        await expectLater(
          h.client.getEntitlement(),
          throwsA(isA<AssertionError>()),
        );
        expect(h.transport.requests, isEmpty);
      },
    );

    test('the nonce is sent as Zaghlol-Time-Nonce', () async {
      final h = _Harness()..seedInstall();
      h.serve({'/v1/entitlement': (r) async => h.signedEntitlement()});
      await h.client.getEntitlement(timeNonce: _nonce);
      expect(
        h.transport.requests.single.headers['zaghlol-time-nonce'],
        _nonce.value,
      );
    });
  });

  group('platform boundary (iOS-only members)', () {
    test('an Android build cannot send seatKeys or iOS request types', () {
      final h = _Harness()..seedInstall();
      final seat = SeatKeyProof(
        publicKey: 'BA${'A' * 85}',
        signature: 'A' * 86,
      );
      final notSent = throwsA(
        isA<BackendFailure>().having(
          (f) => f.kind,
          'kind',
          BackendFailureKind.clientBug,
        ),
      );
      expect(
        () => h.client.prepareSignIn(
          SignInRequest(
            provider: SignInRequestProvider.google,
            idToken: 'a.b.c',
            nonce: 'n' * 22,
            seatKeys: [seat],
          ),
        ),
        notSent,
      );
      expect(
        () => h.client.prepareVerify(
          PurchaseVerifyIosRequest(
            signedTransaction: 'a.b.c',
            seatKeys: [seat],
          ),
        ),
        notSent,
      );
      expect(h.transport.requests, isEmpty);
    });

    test('an iOS build may send seatKeys but not Android variants', () {
      final h = _Harness(platform: ClientPlatform.ios);
      expect(
        h.client.prepareSignIn(
          SignInRequest(
            provider: SignInRequestProvider.apple,
            idToken: 'a.b.c',
            nonce: 'n' * 22,
            seatKeys: [
              SeatKeyProof(publicKey: 'BA${'A' * 85}', signature: 'A' * 86),
            ],
          ),
        ),
        isA<IdempotentBody>(),
      );
      expect(
        () => h.client.prepareVerify(
          const PurchaseVerifyAndroidRequest(
            productId: 'gold.monthly',
            purchaseToken: 't',
          ),
        ),
        throwsA(isA<BackendFailure>()),
      );
    });
  });

  group('error mapping (backend-api §6)', () {
    Future<BackendFailure> failWith(BackendResponse res) async {
      final h = _Harness()..seedInstall();
      h.serve({'/v1/entitlement': (r) async => res});
      try {
        await h.client.getEntitlement(timeNonce: _nonce);
      } on BackendFailure catch (f) {
        return f;
      }
      throw StateError('no failure');
    }

    test(
      'known codes are kept; unknown codes fall back to the status class',
      () async {
        final rate = await failWith(
          problem(429, 'RATE_LIMITED', retryAfter: 7),
        );
        expect(rate.problem, ProblemCode.rateLimited);
        expect(rate.retryAfter, const Duration(seconds: 7));
        expect(rate.retryable, isTrue);

        final unknown5xx = await failWith(problem(503, 'BRAND_NEW'));
        expect(unknown5xx.problem, ProblemCode.unknown);
        expect(unknown5xx.retryable, isTrue);

        final unknown4xx = await failWith(problem(400, 'BRAND_NEW'));
        expect(unknown4xx.problem, ProblemCode.unknown);
        expect(unknown4xx.retryable, isFalse);

        final notJson = await failWith(
          BackendResponse(status: 502, headers: const {}, body: Uint8List(3)),
        );
        expect(notJson.problem, ProblemCode.unknown);
        expect(notJson.retryable, isTrue);

        final mismatch = await failWith(
          jsonResponse(500, {
            'type': 't',
            'title': 't',
            'status': 401,
            'code': 'INSTALL_TOKEN_INVALID',
          }),
        );
        expect(mismatch.problem, ProblemCode.unknown);
      },
    );

    test('offline is a typed failure', () async {
      final h = _Harness()..seedInstall();
      h.transport.handler = (r) async =>
          throw const TransportException(TransportFailureKind.offline);
      await expectLater(
        h.client.getEntitlement(timeNonce: _nonce),
        throwsA(
          isA<BackendFailure>().having(
            (f) => f.kind,
            'kind',
            BackendFailureKind.offline,
          ),
        ),
      );
    });

    test('ACCOUNT_TOKEN_EXPIRED clears only the account token', () async {
      final h = _Harness()..seedInstall();
      h.store.values[BackendStateKeys.accountToken] = _b('acct');
      h.store.values[BackendStateKeys.entitlementToken] = _b('ent');
      h.serve({
        '/v1/entitlement': (r) async {
          expect(r.headers['zaghlol-account'], 'acct');
          return problem(401, 'ACCOUNT_TOKEN_EXPIRED');
        },
      });
      await expectLater(
        h.client.getEntitlement(timeNonce: _nonce),
        throwsA(isA<BackendFailure>()),
      );
      expect(
        h.store.values.containsKey(BackendStateKeys.accountToken),
        isFalse,
      );
      expect(h.store.text(BackendStateKeys.entitlementToken), 'ent');
    });
  });

  group('tokens', () {
    test(
      'rotateInstallToken from a verified answer replaces the token',
      () async {
        final h = _Harness()..seedInstall();
        h.serve({
          '/v1/entitlement': (r) async =>
              h.signedEntitlement(rotate: fakeToken(321)),
        });
        await h.client.getEntitlement(timeNonce: _nonce);
        expect(h.store.text(BackendStateKeys.installToken), fakeToken(321));
      },
    );

    test(
      'sign-in never sends the account token; sign-out requires it',
      () async {
        final h = _Harness()..seedInstall();
        h.store.values[BackendStateKeys.accountToken] = _b('acct');
        h.serve({
          '/v1/accounts/signin': (r) async {
            expect(r.headers.containsKey('zaghlol-account'), isFalse);
            return problem(422, 'ID_TOKEN_INVALID');
          },
        });
        await expectLater(
          h.client.signIn(
            h.client.prepareSignIn(
              SignInRequest(
                provider: SignInRequestProvider.google,
                idToken: 'a.b.c',
                nonce: 'n' * 22,
              ),
            ),
            timeNonce: _nonce,
          ),
          throwsA(isA<BackendFailure>()),
        );
        h.store.values.remove(BackendStateKeys.accountToken);
        await expectLater(
          h.client.signOut(timeNonce: _nonce),
          throwsA(
            isA<BackendFailure>().having(
              (f) => f.kind,
              'kind',
              BackendFailureKind.notSignedIn,
            ),
          ),
        );
      },
    );

    test('deleteInstall never registers', () async {
      final h = _Harness()..serve({});
      await h.client.deleteInstall();
      expect(h.transport.requests, isEmpty);
    });
  });

  test(
    'privacy hook: a full session sends only allow-listed members',
    () async {
      final h = _Harness();
      h.serve({
        '/v1/sync': (r) async =>
            jsonResponse(200, _syncBody(), signWith: h.key),
        '/v1/entitlement': (r) async => h.signedEntitlement(),
      });
      final recorder = RecordingBackendTransport(h.transport);
      final client = BackendClient(
        config: BackendConfig(
          baseUri: Uri.parse('https://api.test.invalid'),
          verifier: ResponseSignatureVerifier([h.key.publicKey]),
        ),
        identity: ClientIdentity(
          platform: ClientPlatform.android,
          appVersion: '1.2.3',
          build: '42',
        ),
        transport: recorder,
        store: h.store,
      );
      await client.sync(
        const SyncRequest(
          catalogVersion: 3,
          flagsVersion: 1,
          contributions: [
            ContributionInput(
              merchantNorm: 'cafe x',
              institutionCode: 'cib',
              categoryCode: 'food',
            ),
          ],
        ),
        timeNonce: _nonce,
      );
      await client.getEntitlement(timeNonce: _nonce);
      const allowed = {
        'installId',
        'platform',
        'appVersion',
        'catalogVersion',
        'flagsVersion',
        'contributions',
        'merchantNorm',
        'institutionCode',
        'categoryCode',
      };
      void keys(Object? v) {
        if (v is Map) {
          for (final e in v.entries) {
            expect(allowed, contains(e.key));
            keys(e.value);
          }
        } else if (v is List) {
          v.forEach(keys);
        }
      }

      expect(recorder.requests, hasLength(3));
      for (final r in recorder.requests) {
        expect(r.headers.containsKey('accept-language'), isFalse);
        if (r.body != null) keys(jsonDecode(utf8.decode(r.body!)));
      }
    },
  );
}
