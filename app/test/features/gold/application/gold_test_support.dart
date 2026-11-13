// T-145 test support: fake store, fake backend, fake seat prover, fake
// attestation host. Everything is synthetic: no real token, key or store
// account.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;

import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/platform/attestation_api.g.dart';
import 'package:zaghlol/core/platform/seat_key_api.g.dart';
import 'package:zaghlol/features/gold/application/gold_ports.dart';
import 'package:zaghlol/features/gold/application/gold_store.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';

import 'entitlement_harness.dart';

final class FakeGoldStore implements GoldStore {
  final StreamController<List<StorePurchase>> ctl =
      StreamController<List<StorePurchase>>.broadcast();
  final List<StorePurchase> completed = [];
  final List<String> events = [];
  String? lastBindingRef;
  bool startCalled = false;
  bool failComplete = false;
  List<OwnedPurchase> owned = [];
  Object? ownedError;
  final Set<String> storeKit = {};

  @override
  Stream<List<StorePurchase>> get updates => ctl.stream;
  @override
  Future<void> start() async => startCalled = true;
  @override
  Future<void> dispose() async {}

  @override
  Future<bool> buy(String productId, {required String bindingRef}) async {
    lastBindingRef = bindingRef;
    return true;
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    events.add('complete');
    if (failComplete) throw PlatformException(code: 'STORE_DOWN');
    completed.add(purchase);
  }

  @override
  Future<List<OwnedPurchase>> queryOwned() async {
    if (ownedError != null) throw ownedError!;
    return owned;
  }

  @override
  Future<bool> hasStoreKitTransactionFor(String productId) async =>
      storeKit.contains(productId);

  /// Delivers [p] and lets the service's serialized handler run.
  Future<void> deliver(StorePurchase p) async {
    ctl.add([p]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

StorePurchase paid(
  String ref, {
  String product = 'zaghlol_gold_yearly',
  StorePurchaseState state = StorePurchaseState.purchased,
}) => StorePurchase(
  productId: product,
  state: state,
  reference: ref,
  purchaseId: '1001',
);

final class FakeGoldBackend implements GoldBackend {
  FakeGoldBackend(this.h);
  final Harness h;
  String? id = installA;
  int keys = 0;
  final List<PurchaseVerifyRequest> verifies = [];
  final List<String> verifyKeys = [];
  final List<PurchaseRestoreRequest> restores = [];
  final List<String> log = [];
  Future<PurchaseVerifyResponse> Function(
    PurchaseVerifyRequest r,
    IdempotencyKey k,
    TimeNonce n,
  )?
  onVerify;
  Future<PurchaseRestoreResponse> Function(
    PurchaseRestoreRequest r,
    TimeNonce n,
  )?
  onRestore;

  @override
  Future<String?> installId() async => id;
  @override
  Future<String> ensureInstalled() async => id!;
  @override
  IdempotencyKey newKey() => IdempotencyKey.restore(
    '01JD0000000000000000${(keys++).toString().padLeft(6, '0')}',
  );

  @override
  Future<PurchaseVerifyResponse> verify(
    PurchaseVerifyRequest request,
    IdempotencyKey key,
    TimeNonce nonce,
  ) {
    verifies.add(request);
    verifyKeys.add(key.value);
    log.add('verify');
    return onVerify!(request, key, nonce);
  }

  @override
  Future<PurchaseRestoreResponse> restore(
    PurchaseRestoreRequest request,
    TimeNonce nonce,
  ) {
    restores.add(request);
    log.add('restore');
    return onRestore!(request, nonce);
  }
}

/// A verify answer echoing [n] at the harness clock, with a signed token.
PurchaseVerifyResponse verifyAnswer(
  Harness h,
  TimeNonce n, {
  PurchaseStatus status = PurchaseStatus.active,
  bool withToken = true,
  String? tokenText,
  bool? seatHeldElsewhere,
  bool? accountRequired,
  String? nextMoveAt,
}) => PurchaseVerifyResponse(
  status: status,
  entitlement: withToken
      ? Entitlement(
          token:
              tokenText ??
              h.token(entClaims(iatMs: h.clock.wall, status: 'active')),
        )
      : null,
  seatHeldElsewhere: seatHeldElsewhere,
  accountRequired: accountRequired,
  nextMoveAt: nextMoveAt,
  serverTime: iso(h.clock.wall),
  timeNonce: n.value,
);

PurchaseRestoreResponse restoreAnswer(
  Harness h,
  TimeNonce n, {
  PurchaseStatus status = PurchaseStatus.active,
  bool withToken = true,
  bool? moved,
  String sub = installA,
}) => PurchaseRestoreResponse(
  status: status,
  restoredCount: status == PurchaseStatus.active ? 1 : 0,
  movedFromOtherPhone: moved,
  entitlement: withToken
      ? Entitlement(
          token: h.token(
            entClaims(sub: sub, iatMs: h.clock.wall, status: 'active'),
          ),
        )
      : null,
  serverTime: iso(h.clock.wall),
  timeNonce: n.value,
);

BackendFailure goldProblem(
  ProblemCode code,
  int status, {
  Duration? retryAfter,
  String? nextMoveAt,
}) => BackendFailure(
  BackendFailureKind.problem,
  httpStatus: status,
  problem: code,
  retryAfter: retryAfter,
  nextMoveAt: nextMoveAt,
);

final class FakeSeatProver implements SeatProver {
  List<SeatSignature> sigs = [];
  final List<String> calls = [];
  final List<Uint8List> challenges = [];
  bool unusableMarked = false;
  List<String>? order;

  static Uint8List pk(int seed) =>
      Uint8List.fromList([4, for (var i = 0; i < 64; i++) (seed + i) & 0xff]);
  static Uint8List sig(int seed) =>
      Uint8List.fromList([for (var i = 0; i < 64; i++) (seed * 3 + i) & 0xff]);

  static List<SeatSignature> two() => [
    SeatSignature(publicKey: pk(1), signature: sig(1)),
    SeatSignature(publicKey: pk(2), signature: sig(2)),
  ];

  @override
  Future<List<SeatSignature>> prove(SeatOp op, Uint8List challenge) async {
    calls.add(op.name);
    order?.add('seat:${op.name}');
    challenges.add(challenge);
    return unusableMarked ? const [] : sigs;
  }

  @override
  Future<void> markOwnKeyUnusable() async {
    unusableMarked = true;
    calls.add('unusable');
  }
}

/// A fake native attestation host.
final class FakeAttestHost extends AttestationHostApi {
  final List<String> calls = [];
  final List<Uint8List> hashes = [];
  final List<bool> forced = [];
  List<String>? order;
  final List<Object> prepareErrors = [];
  final List<Object> attestErrors = [];
  String type = 'play_integrity';
  bool withObject = false;
  int n = 0;

  @override
  Future<void> prepare() async {
    calls.add('prepare');
    order?.add('prepare');
    if (prepareErrors.isNotEmpty) throw prepareErrors.removeAt(0);
  }

  @override
  Future<AttestationProof> attest(Uint8List bodyHash, bool forceNewKey) async {
    calls.add('attest');
    order?.add('attest');
    hashes.add(Uint8List.fromList(bodyHash));
    forced.add(forceNewKey);
    if (attestErrors.isNotEmpty) throw attestErrors.removeAt(0);
    n++;
    if (type == 'play_integrity') {
      return AttestationProof(type: type, token: 'synthetic.token-$n');
    }
    return AttestationProof(
      type: type,
      keyId: '${'A' * 43}=',
      assertion: 'c3ludGhldGljLWFzc2VydGlvbg',
      attestationObject: withObject || forceNewKey
          ? 'c3ludGhldGljLW9iag'
          : null,
    );
  }
}
