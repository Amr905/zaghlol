// T-145: the purchase flow against fakes (store, backend, seat prover) and the
// real EntitlementService (T-144). Synthetic data only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/application/gold_store.dart';
import 'package:zaghlol/features/gold/application/purchase.dart';
import 'package:zaghlol/features/gold/application/purchase_outbox.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';
import 'package:zaghlol/features/gold/domain/purchase_outcome.dart';

import '../../../core/backend/backend_test_support.dart';
import 'entitlement_harness.dart';
import 'gold_test_support.dart';

const _tokenSentinel = 'SENTINEL-PLAY-TOKEN-0001';
const _jws = 'eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln';

final class _Rig {
  _Rig({ClientPlatform platform = ClientPlatform.android}) {
    h = Harness();
    h.backend.id = installA;
    backend = FakeGoldBackend(h);
    outbox = PurchaseOutbox(h.store);
    service = PurchaseService(
      store: store,
      backend: backend,
      entitlement: h.service,
      seats: seats,
      outbox: outbox,
      platform: platform,
      now: () => DateTime.fromMillisecondsSinceEpoch(h.clock.wall, isUtc: true),
    );
    service.outcomes.listen(outcomes.add);
  }

  late final Harness h;
  late final FakeGoldBackend backend;
  late final PurchaseOutbox outbox;
  late final PurchaseService service;
  final store = FakeGoldStore();
  final seats = FakeSeatProver();
  final List<PurchaseOutcome> outcomes = [];

  PurchaseOutcome get last => outcomes.last;

  /// Backend answers verify with an active, signed entitlement.
  void backendOk({bool? held, bool? account, String? next}) {
    backend.onVerify = (r, k, n) async => verifyAnswer(
      h,
      n,
      seatHeldElsewhere: held,
      accountRequired: account,
      nextMoveAt: next,
    );
  }

  Future<void> started() async {
    backendOk();
    await service.start();
  }

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  test('buy passes StoreBindingRef(installId) to the store', () async {
    final r = _Rig();
    await r.started();
    expect(await r.service.buy('zaghlol_gold_yearly'), isTrue);
    expect(r.store.lastBindingRef, matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(r.store.lastBindingRef![14], '8'); // RFC 9562 version 8
  });

  test('verified purchase: Gold only from the signed entitlement, completed '
      'after verify', () async {
    final r = _Rig();
    await r.started();
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.backend.log, ['verify']);
    expect(r.h.sink.last, EntitlementPhase.active);
    expect(r.store.completed, hasLength(1));
    expect(r.last, isA<PurchaseGold>());
    expect(await r.outbox.load(), isEmpty);
    final req = r.backend.verifies.single as PurchaseVerifyAndroidRequest;
    expect(req.productId, 'zaghlol_gold_yearly');
    expect(req.purchaseToken, _tokenSentinel);
  });

  test('AC: backend down at purchase -> queued, same key, Gold after it '
      'returns', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, _) async =>
        throw BackendFailure(BackendFailureKind.offline);
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.last, isA<PurchaseQueued>());
    expect(r.h.sink.phases.where((p) => p == EntitlementPhase.active), isEmpty);
    expect(r.store.completed, isEmpty);
    final queued = await r.outbox.load();
    expect(queued.single.stage, OutboxStage.queued);

    // Not due yet: nothing is sent.
    await r.service.retryDue();
    expect(r.backend.verifies, hasLength(1));

    // The backend returns two days later (inside Google's 3-day window).
    r.h.clock.pass(2 * day);
    r.backendOk();
    await r.service.retryDue();
    expect(r.backend.verifies, hasLength(2));
    expect(r.backend.verifyKeys.toSet(), hasLength(1)); // same Idempotency-Key
    expect(r.h.sink.last, EntitlementPhase.active);
    expect(r.store.completed, hasLength(1));
    expect(await r.outbox.load(), isEmpty);
  });

  test('AC: a store-pending (cash) purchase shows pending, no Gold, no '
      'verify, no completion', () async {
    final r = _Rig();
    await r.started();
    await r.store.deliver(
      const StorePurchase(
        productId: 'zaghlol_gold_yearly',
        state: StorePurchaseState.pending,
        reference: '',
      ),
    );
    expect(r.last, isA<PurchasePending>());
    expect(r.backend.verifies, isEmpty);
    expect(r.store.completed, isEmpty);
    expect(r.h.sink.phases, isEmpty);
  });

  test('server `pending` keeps the purchase, polls later, never acknowledges '
      'early', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, n) async =>
        verifyAnswer(r.h, n, status: PurchaseStatus.pending, withToken: false);
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.last, isA<PurchasePending>());
    expect(r.store.completed, isEmpty);
    expect((await r.outbox.load()).single.stage, OutboxStage.pendingServer);
    r.h.clock.pass(20 * minute);
    r.backendOk();
    await r.service.retryDue();
    expect(r.last, isA<PurchaseGold>());
    expect(r.store.completed, hasLength(1));
  });

  // Negative proof 1 (§2a): the backend said "active" but this app cannot
  // verify the entitlement (token signed by an unknown key): no Gold, no
  // acknowledgement, retried.
  test('NEG: a purchase whose entitlement the app cannot verify never '
      'yields Gold', () async {
    final r = _Rig();
    await r.started();
    final forged = mintJws(
      TestSigningKeyFor.other,
      entClaims(iatMs: r.h.clock.wall),
    );
    r.backend.onVerify = (_, _, n) async =>
        verifyAnswer(r.h, n, tokenText: forged);
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.h.sink.phases.where((p) => p == EntitlementPhase.active), isEmpty);
    expect(r.store.completed, isEmpty);
    expect(r.last, isA<PurchaseQueued>());
    expect((await r.outbox.load()).single.stage, OutboxStage.queued);
  });

  // Negative proof 2: a failed verification is retried and the store purchase
  // is not acknowledged; only a verified one is.
  test('NEG: failed verification is retried, never acknowledged early; a '
      'store replay does not skip the backend', () async {
    final r = _Rig();
    await r.started();
    var calls = 0;
    r.backend.onVerify = (_, _, n) async {
      calls++;
      if (calls < 3) throw goldProblem(ProblemCode.storeUnavailable, 502);
      return verifyAnswer(r.h, n);
    };
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.store.completed, isEmpty);
    // The store redelivers right away (app restart): not due, no second call.
    await r.store.deliver(paid(_tokenSentinel));
    expect(calls, 1);
    r.h.clock.pass(2 * minute);
    await r.service.retryDue();
    expect(calls, 2);
    expect(r.store.completed, isEmpty);
    r.h.clock.pass(10 * minute);
    await r.service.retryDue();
    expect(calls, 3);
    expect(r.store.completed, hasLength(1));
    expect(r.store.events, ['complete']);
  });

  test('Retry-After longer than the back-off is honoured', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, _) async => throw goldProblem(
      ProblemCode.upstreamUnavailable,
      503,
      retryAfter: const Duration(minutes: 30),
    );
    await r.store.deliver(paid(_tokenSentinel));
    expect(
      (await r.outbox.load()).single.nextAtMs,
      r.h.clock.wall + 30 * minute,
    );
  });

  test('PURCHASE_NOT_OWNED is final: offer Restore, no Gold, not completed, '
      'a replay is not re-verified', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, _) async =>
        throw goldProblem(ProblemCode.purchaseNotOwned, 422);
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.last, isA<PurchaseNotOwned>());
    expect(r.store.completed, isEmpty);
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.backend.verifies, hasLength(1));
  });

  test('expired / refunded / invalid are final and grant nothing', () async {
    for (final s in [
      PurchaseStatus.expired,
      PurchaseStatus.refunded,
      PurchaseStatus.invalid,
    ]) {
      final r = _Rig();
      await r.started();
      r.backend.onVerify = (_, _, n) async =>
          verifyAnswer(r.h, n, status: s, withToken: false);
      await r.store.deliver(paid(_tokenSentinel));
      expect(r.last, isA<PurchaseInvalid>());
      expect(r.store.completed, isEmpty);
    }
  });

  test('seat held elsewhere (+ accountRequired, nextMoveAt): paid and '
      'acknowledged, but this phone is not Gold', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, n) async => verifyAnswer(
      r.h,
      n,
      seatHeldElsewhere: true,
      accountRequired: true,
      nextMoveAt: '2026-12-06T10:00:00Z',
      tokenText: r.h.token(
        entClaims(iatMs: r.h.clock.wall, status: 'none', plan: 'none'),
      ),
    );
    await r.store.deliver(paid(_tokenSentinel));
    final o = r.last as PurchaseSeatHeldElsewhere;
    expect(o.accountRequired, isTrue);
    expect(o.nextMoveAt, DateTime.utc(2026, 12, 6, 10));
    expect(r.store.completed, hasLength(1));
    expect(r.h.sink.phases.where((p) => p == EntitlementPhase.active), isEmpty);
  });

  test('the outbox survives a restart and the retry resumes with the same '
      'key', () async {
    final r = _Rig();
    await r.started();
    r.backend.onVerify = (_, _, _) async =>
        throw BackendFailure(BackendFailureKind.timeout);
    await r.store.deliver(paid(_tokenSentinel));
    final firstKey = r.backend.verifyKeys.single;

    final r2 = _Rig();
    // Same encrypted store, new service (process restart).
    r2.h.store.values.addAll(r.h.store.values);
    r2.h.clock.wall = r.h.clock.wall + day;
    r2.backendOk();
    await r2.service.retryDue();
    expect(r2.backend.verifyKeys.single, firstKey);
    expect(r2.last, isA<PurchaseGold>());
  });

  test('verified but completion failed: the replay completes without a '
      'second verify', () async {
    final r = _Rig();
    await r.started();
    r.store.failComplete = true;
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.last, isA<PurchaseGold>());
    expect((await r.outbox.load()).single.stage, OutboxStage.verified);
    r.store.failComplete = false;
    await r.store.deliver(paid(_tokenSentinel));
    expect(r.backend.verifies, hasLength(1));
    expect(r.store.completed, hasLength(1));
    expect(await r.outbox.load(), isEmpty);
  });

  group('iOS seat keys on verify (R4-1, T-179)', () {
    test('element 0 only, challenge = SHA-256(signedTransaction), signed once '
        'and resent byte-identical', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = FakeSeatProver.two();
      await r.started();
      r.backend.onVerify = (_, _, _) async =>
          throw BackendFailure(BackendFailureKind.offline);
      await r.store.deliver(paid(_jws));
      r.h.clock.pass(2 * minute);
      await r.service.retryDue();

      expect(r.seats.calls, ['verify']); // signed once
      expect(r.seats.challenges.single, verifySeatChallenge(_jws));
      final a = r.backend.verifies[0] as PurchaseVerifyIosRequest;
      final b = r.backend.verifies[1] as PurchaseVerifyIosRequest;
      expect(a.seatKeys, hasLength(1));
      expect(jsonEncode(a.toJson()), jsonEncode(b.toJson()));
      expect(a.signedTransaction, _jws);
    });

    test('no seatKeys when T-179 has no usable key', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = const [];
      await r.started();
      await r.store.deliver(paid(_jws));
      final a = r.backend.verifies.single as PurchaseVerifyIosRequest;
      expect(a.seatKeys, isNull);
      expect(a.toJson().containsKey('seatKeys'), isFalse);
    });

    test('after R5-6 later verifies send no seatKeys', () async {
      final r = _Rig(platform: ClientPlatform.ios);
      r.seats.sigs = FakeSeatProver.two();
      r.seats.unusableMarked = true;
      await r.started();
      await r.store.deliver(paid(_jws));
      expect(
        (r.backend.verifies.single as PurchaseVerifyIosRequest).seatKeys,
        isNull,
      );
    });
  });

  test('no purchase token reaches toString of any public value', () async {
    final r = _Rig();
    await r.started();
    await r.store.deliver(paid(_tokenSentinel));
    final e = OutboxEntry(
      id: 'x',
      productId: 'p',
      reference: _tokenSentinel,
      purchaseId: '1',
      needsCompletion: true,
      key: 'k',
      firstAtMs: 0,
    );
    for (final s in [
      '${r.service}',
      '$e',
      '${paid(_tokenSentinel)}',
      '${r.outcomes}',
    ]) {
      expect(s, isNot(contains(_tokenSentinel)));
    }
  });
}

/// A signing key the app does not trust.
abstract final class TestSigningKeyFor {
  static final other = TestSigningKey('e2026a', seed: 6);
}
