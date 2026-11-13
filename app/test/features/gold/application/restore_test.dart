// T-145: restore against fakes (store, backend, seat prover, attestation
// host) and the real EntitlementService. Vectors: restore-binding-v1.json.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/platform/pigeon_attestation.dart';
import 'package:zaghlol/core/platform/seat_key_api.g.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/application/gold_store.dart';
import 'package:zaghlol/features/gold/application/restore.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';
import 'package:zaghlol/features/gold/domain/restore_outcome.dart';

import 'entitlement_harness.dart';
import 'gold_test_support.dart';

Map<String, dynamic> _vectors() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File(
      '${dir.path}/backend/tests/Zaghlol.Contract.Tests/vectors/'
      'restore-binding-v1.json',
    );
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('restore-binding-v1.json not found');
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _b64u(String s) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

final class _Rig {
  _Rig({
    ClientPlatform platform = ClientPlatform.android,
    String installId = installA,
  }) : id = installId {
    h = Harness();
    h.backend.id = installId;
    backend = FakeGoldBackend(h)..id = installId;
    host.type = platform == ClientPlatform.ios
        ? 'app_attest'
        : 'play_integrity';
    host.order = order;
    seats.order = order;
    service = RestoreService(
      store: store,
      backend: backend,
      entitlement: h.service,
      seats: seats,
      attestation: PigeonAttestation(api: host),
      state: h.store,
      platform: platform,
      delay: (d) async => delays.add(d),
      now: () => DateTime.fromMillisecondsSinceEpoch(h.clock.wall, isUtc: true),
    );
    store.owned = [
      platform == ClientPlatform.ios
          ? const OwnedPurchase(
              productId: 'zaghlol_gold_yearly',
              reference: 'eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln',
            )
          : const OwnedPurchase(
              productId: 'zaghlol_gold_lifetime',
              reference: 'synthetic-play-token/0001',
            ),
    ];
  }

  final String id;
  late final Harness h;
  late final FakeGoldBackend backend;
  late final RestoreService service;
  final store = FakeGoldStore();
  final seats = FakeSeatProver();
  final host = FakeAttestHost();
  final List<String> order = [];
  final List<Duration> delays = [];

  void ok({bool? moved}) {
    backend.onRestore = (r, n) async =>
        restoreAnswer(h, n, moved: moved, sub: id);
  }
}

void main() {
  group('vectors (R2-1, R4-1(3))', () {
    final valid = (_vectors()['valid'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    for (final v in valid) {
      test(
        '${v['name']}: the platform host gets exactly the vector hash',
        () async {
          final body = v['body'] as Map<String, dynamic>;
          final ios = body['platform'] == 'ios';
          final id = v['installId'] as String;
          final r = _Rig(
            platform: ios ? ClientPlatform.ios : ClientPlatform.android,
            installId: id,
          );
          r.ok();
          final att = body['attestation'] as Map<String, dynamic>;
          final keys = <Map<String, dynamic>>[
            for (final k in (att['seatKeys'] as List<dynamic>?) ?? [])
              k as Map<String, dynamic>,
          ];
          r.seats.sigs = [
            for (final k in keys)
              SeatSignature(
                publicKey: _b64u(k['publicKey'] as String),
                signature: _b64u(k['signature'] as String),
              ),
          ];
          r.store.owned = ios
              ? [
                  for (final t in body['signedTransactions'] as List<dynamic>)
                    OwnedPurchase(
                      productId: 'zaghlol_gold_yearly',
                      reference: t as String,
                    ),
                ]
              : [
                  for (final p in body['purchases'] as List<dynamic>)
                    OwnedPurchase(
                      productId: (p as Map)['productId'] as String,
                      reference: p['purchaseToken'] as String,
                    ),
                ];
          final out = await r.service.restore();
          expect(out, isA<RestoreGold>());
          expect(r.host.hashes, hasLength(1));
          expect(
            _hex(r.host.hashes.single),
            ios ? v['clientDataHashHex'] : v['bodyHashHex'],
          );
          expect(
            base64Url.encode(r.host.hashes.single).replaceAll('=', ''),
            ios ? isNot(v['requestHashB64u']) : v['requestHashB64u'],
          );
          // The proof carries the same keys, in the same order.
          if (ios) {
            final sent = r.backend.restores.single as PurchaseRestoreIosRequest;
            final sentKeys = sent.attestation.seatKeys ?? const [];
            expect(
              [for (final k in sentKeys) k.publicKey],
              [for (final k in keys) k['publicKey']],
            );
          }
        },
      );
    }
  });

  test('R4-1(3): iOS seat signatures are produced before the attestation '
      'call; Android prepares only when a restore starts', () async {
    final ios = _Rig(platform: ClientPlatform.ios)..ok();
    ios.seats.sigs = FakeSeatProver.two();
    await ios.service.restore();
    expect(ios.order, ['seat:restore', 'attest']);
    expect(ios.seats.challenges.single.length, 32);

    final and = _Rig()..ok();
    expect(and.host.calls, isEmpty); // nothing before the user starts
    await and.service.restore();
    expect(and.order, ['prepare', 'attest']);
  });

  test('R3-8: a body the strict parser rejects is never sent', () async {
    final r = _Rig()..ok();
    r.store.owned = const [
      OwnedPurchase(
        productId: 'zaghlol_gold_lifetime',
        reference: 'token-with-lone-surrogate-\uD800',
      ),
    ];
    final out = await r.service.restore();
    expect(out, isA<RestoreBodyRejected>());
    expect(r.backend.restores, isEmpty);
    expect(r.host.calls, isNot(contains('attest')));
  });

  test('R3-8: every invalid vector is rejected before a hash exists', () {
    final invalid = (_vectors()['invalid'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(invalid, hasLength(6));
    for (final v in invalid) {
      expect(
        () => restoreBodyHashFromJson(installA, v['raw'] as String),
        throwsA(anything),
        reason: v['name'] as String,
      );
    }
  });

  test('nothing to restore: nothing is sent', () async {
    final r = _Rig()..ok();
    r.store.owned = [];
    expect(await r.service.restore(), isA<RestoreNothingToRestore>());
    expect(r.backend.restores, isEmpty);
    expect(r.host.calls, isEmpty);
  });

  test('success applies Gold only through the signed entitlement and reports '
      'a move', () async {
    final r = _Rig()..ok(moved: true);
    final out = await r.service.restore() as RestoreGold;
    expect(out.movedFromOtherPhone, isTrue);
    expect(r.h.sink.last, EntitlementPhase.active);
  });

  test('an unverifiable entitlement is never Gold', () async {
    final r = _Rig();
    r.backend.onRestore = (_, n) async =>
        restoreAnswer(r.h, n, withToken: false);
    expect(await r.service.restore(), isA<RestoreTryLater>());
    expect(r.h.sink.phases.where((p) => p == EntitlementPhase.active), isEmpty);
  });

  group('attestation retries', () {
    test('AC: DEVICE_ATTESTATION_FAILED -> exactly one retry (Android: fresh '
        'token), then help', () async {
      final r = _Rig();
      r.backend.onRestore = (_, _) async =>
          throw goldProblem(ProblemCode.deviceAttestationFailed, 422);
      expect(await r.service.restore(), isA<RestoreAttestationHelp>());
      expect(r.backend.restores, hasLength(2));
      expect(r.host.hashes, hasLength(2));
      final t = r.backend.restores.map(
        (x) => ((x as PurchaseRestoreAndroidRequest).attestation).token,
      );
      expect(t.toSet(), hasLength(2)); // a fresh token each time
    });

    test('AC: iOS retries once with a new App Attest key, then help', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = FakeSeatProver.two();
      r.backend.onRestore = (_, _) async =>
          throw goldProblem(ProblemCode.deviceAttestationFailed, 422);
      expect(await r.service.restore(), isA<RestoreAttestationHelp>());
      expect(r.backend.restores, hasLength(2));
      expect(r.host.forced, [false, true]);
    });

    test('iOS: no retry when the failed request already carried an '
        'attestationObject', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.host.withObject = true;
      r.backend.onRestore = (_, _) async =>
          throw goldProblem(ProblemCode.deviceAttestationFailed, 422);
      expect(await r.service.restore(), isA<RestoreAttestationHelp>());
      expect(r.backend.restores, hasLength(1));
    });

    test('platform transients: 3 tries then "try later"; Play services '
        'outdated is flagged', () async {
      final r = _Rig()..ok();
      r.host.attestErrors.addAll([
        PlatformException(code: 'ATTEST_TRANSIENT'),
        PlatformException(code: 'ATTEST_TRANSIENT'),
        PlatformException(code: 'ATTEST_TRANSIENT'),
      ]);
      expect(await r.service.restore(), isA<RestoreTryLater>());
      expect(r.host.hashes, hasLength(3));
      expect(r.delays, attestRetryDelays);
      expect(r.backend.restores, isEmpty); // never without a proof

      final o = _Rig()..ok();
      o.host.prepareErrors.add(
        PlatformException(code: 'ATTEST_PLAY_SERVICES_OUTDATED'),
      );
      final out = await o.service.restore() as RestoreTryLater;
      expect(out.playServicesOutdated, isTrue);
      expect(o.backend.restores, isEmpty);
    });

    test(
      'an unavailable attestation is the help state, nothing sent',
      () async {
        final r = _Rig()..ok();
        r.host.attestErrors.add(PlatformException(code: 'ATTEST_UNAVAILABLE'));
        expect(await r.service.restore(), isA<RestoreAttestationHelp>());
        expect(r.backend.restores, isEmpty);
      },
    );
  });

  group('SEAT_KEY_MISMATCH (R4-1(1), R5-6)', () {
    test('retries once without seatKeys over a fresh attestation, then sets '
        'the unusable flag', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = FakeSeatProver.two();
      var n = 0;
      r.backend.onRestore = (_, nonce) async {
        if (n++ == 0) throw goldProblem(ProblemCode.seatKeyMismatch, 400);
        return restoreAnswer(r.h, nonce);
      };
      expect(await r.service.restore(), isA<RestoreGold>());
      final first = r.backend.restores[0] as PurchaseRestoreIosRequest;
      final second = r.backend.restores[1] as PurchaseRestoreIosRequest;
      expect(first.attestation.seatKeys, hasLength(2));
      expect(second.attestation.seatKeys, isNull);
      expect(r.host.hashes, hasLength(2));
      expect(r.host.hashes[0], isNot(r.host.hashes[1])); // digest changed
      expect(r.seats.unusableMarked, isTrue);
    });

    test('a retry that also fails does not set the flag; a second mismatch '
        'is not retried', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = FakeSeatProver.two();
      r.backend.onRestore = (_, _) async =>
          throw goldProblem(ProblemCode.seatKeyMismatch, 400);
      expect(await r.service.restore(), isA<RestoreFailed>());
      expect(r.backend.restores, hasLength(2));
      expect(r.seats.unusableMarked, isFalse);
    });

    test('once flagged, later restores send no seatKeys', () async {
      final r = _Rig(platform: ClientPlatform.ios)..ok();
      r.seats.sigs = FakeSeatProver.two();
      r.seats.unusableMarked = true; // FakeSeatProver then returns none
      await r.service.restore();
      final sent = r.backend.restores.single as PurchaseRestoreIosRequest;
      expect(sent.attestation.seatKeys, isNull);
    });
  });

  test('AC: MOVE_COOLDOWN stores nextMoveAt and is never retried', () async {
    final r = _Rig();
    r.backend.onRestore = (_, _) async => throw goldProblem(
      ProblemCode.moveCooldown,
      409,
      nextMoveAt: '2027-12-06T10:00:00Z',
    );
    final out = await r.service.restore() as RestoreMoveCooldown;
    expect(out.nextMoveAt, DateTime.utc(2027, 12, 6, 10));
    expect(r.backend.restores, hasLength(1));
    expect(await r.service.storedNextMoveAt(), DateTime.utc(2027, 12, 6, 10));
  });

  test('outage answers are "try later" with the server back-off', () async {
    final r = _Rig();
    r.backend.onRestore = (_, _) async => throw goldProblem(
      ProblemCode.upstreamUnavailable,
      503,
      retryAfter: const Duration(seconds: 90),
    );
    final out = await r.service.restore() as RestoreTryLater;
    expect(out.retryAfter, const Duration(seconds: 90));
    expect(r.backend.restores, hasLength(1));
  });

  test('account-required and pending map to their own states', () async {
    final a = _Rig();
    a.backend.onRestore = (_, n) async => restoreAnswer(
      a.h,
      n,
      status: PurchaseStatus.accountRequired,
      withToken: false,
    );
    expect(await a.service.restore(), isA<RestoreAccountRequired>());
    final p = _Rig();
    p.backend.onRestore = (_, n) async =>
        restoreAnswer(p.h, n, status: PurchaseStatus.pending, withToken: false);
    expect(await p.service.restore(), isA<RestorePending>());
  });

  test('a store that cannot list purchases sends nothing', () async {
    final r = _Rig()..ok();
    r.store.ownedError = const StoreQueryException();
    expect(await r.service.restore(), isA<RestoreStoreUnavailable>());
    expect(r.backend.restores, isEmpty);
  });

  group('D-55 Delete-everything warning', () {
    test('holds a seat and nextMoveAt when the cached token covers a '
        'purchase', () async {
      final r = _Rig()..ok();
      await r.h.online(
        r.h.token(
          entClaims(iatMs: r.h.clock.wall, nextMoveAt: '2026-12-06T10:00:00Z'),
        ),
      );
      final w = await deleteEverythingWarning(
        entitlement: r.h.service,
        installId: r.backend.installId,
      );
      expect(w.holdsSeat, isTrue);
      expect(w.nextMoveAt, DateTime.utc(2026, 12, 6, 10));
    });

    test('no seat without a token, for a "none" plan, or for another '
        'install', () async {
      final r = _Rig();
      expect(
        (await deleteEverythingWarning(
          entitlement: r.h.service,
          installId: r.backend.installId,
        )).holdsSeat,
        isFalse,
      );
      await r.h.online(
        r.h.token(
          entClaims(iatMs: r.h.clock.wall, plan: 'none', status: 'none'),
        ),
      );
      expect(
        (await deleteEverythingWarning(
          entitlement: r.h.service,
          installId: r.backend.installId,
        )).holdsSeat,
        isFalse,
      );
      expect(
        (await deleteEverythingWarning(
          entitlement: r.h.service,
          installId: () async => installB,
        )).holdsSeat,
        isFalse,
      );
    });
  });

  test(
    'R5-3(b): the store port answers per product; Android is always false',
    () async {
      final s = FakeGoldStore()..storeKit.add('zaghlol_gold_yearly');
      expect(await s.hasStoreKitTransactionFor('zaghlol_gold_yearly'), isTrue);
      expect(
        await s.hasStoreKitTransactionFor('zaghlol_gold_lifetime'),
        isFalse,
      );
      final android = InAppPurchaseGoldStore(platform: ClientPlatform.android);
      expect(
        await android.hasStoreKitTransactionFor('zaghlol_gold_yearly'),
        isFalse,
      );
    },
  );
}
