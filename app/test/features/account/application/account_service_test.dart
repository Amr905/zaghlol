// T-147: sign-in, sign-out and delete against fakes (backend, provider,
// seat prover) and the real EntitlementService (T-144). Synthetic data only.

import 'dart:convert';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/features/account/application/account_service.dart';
import 'package:zaghlol/features/account/application/id_token_source.dart';
import 'package:zaghlol/features/account/domain/sign_in_outcome.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';

import '../../gold/application/entitlement_harness.dart';
import '../../gold/application/gold_test_support.dart';

const _jws = 'eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln';

final class _Tokens implements IdTokenSource {
  final List<String> hashed = [];
  Object? error;
  @override
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  }) async {
    hashed.add(hashedNonce);
    if (error != null) throw error!;
    return const ProviderCredential(idToken: _jws);
  }
}

final class _Backend implements AccountBackend {
  _Backend(this.h);
  final Harness h;
  final List<SignInRequest> requests = [];
  Future<SignInResponse> Function(SignInRequest r, TimeNonce n)? onSignIn;
  Future<void> Function()? onDelete;
  int deletes = 0;

  @override
  Future<String> ensureInstalled() async => installA;
  @override
  Future<SignInResponse> signIn(SignInRequest r, TimeNonce n) {
    requests.add(r);
    return onSignIn!(r, n);
  }

  @override
  Future<void> deleteAccount() {
    deletes++;
    return onDelete!();
  }
}

SignInResponse _ok(
  Harness h,
  TimeNonce n, {
  String iid = installA,
  bool? moveRefused,
  bool? restoreSuggested,
  bool? moved,
  String? nextMoveAt,
}) => SignInResponse(
  accountId: 'acct-1',
  accountToken: h.token(acctClaims(sub: 'acct-1', iid: iid, iatMs: t0)),
  entitlement: Entitlement(
    token: h.token(entClaims(iatMs: t0, acct: 'acct-1')),
  ),
  linkedInstalls: 1,
  moveRefused: moveRefused,
  restoreSuggested: restoreSuggested,
  movedFromOtherPhone: moved,
  nextMoveAt: nextMoveAt,
  serverTime: iso(h.clock.wall),
  timeNonce: n.value,
);

final class _Rig {
  _Rig({
    ClientPlatform platform = ClientPlatform.ios,
    Set<String> storeKit = const {},
  }) {
    h = Harness(boot: 1);
    backend = _Backend(h);
    service = AccountService(
      backend: backend,
      entitlement: h.service,
      seats: seats,
      tokens: tokens,
      platform: platform,
      hasStoreKitTransaction: (p) async => storeKit.contains(p),
    );
  }
  late final Harness h;
  late final _Backend backend;
  late final AccountService service;
  final seats = FakeSeatProver();
  final tokens = _Tokens();

  bool get hasAccountToken =>
      h.store.values[BackendStateKeys.accountToken] != null;
}

String _hex(String raw) => c.sha256.convert(ascii.encode(raw)).toString();

void main() {
  group('R2-9 nonce', () {
    test('two attempts send different raw nonces; the provider gets '
        'hex(SHA-256(raw)) each time', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n);
      await r.service.signIn(SignInRequestProvider.google);
      await r.service.signIn(SignInRequestProvider.google);
      final raws = [for (final q in r.backend.requests) q.nonce];
      expect(raws[0], isNot(raws[1]));
      for (var i = 0; i < 2; i++) {
        expect(raws[i], matches(RegExp(r'^[A-Za-z0-9_-]{22,128}$')));
        expect(raws[i].length * 6, greaterThanOrEqualTo(128));
        expect(r.tokens.hashed[i], _hex(raws[i]));
        expect(r.tokens.hashed[i], isNot(raws[i]));
      }
    });
  });

  group('outcomes', () {
    test(
      'R3-5: moveRefused stores the account token and carries nextMoveAt',
      () async {
        final r = _Rig();
        r.backend.onSignIn = (req, n) async =>
            _ok(r.h, n, moveRefused: true, nextMoveAt: '2026-12-01T10:00:00Z');
        final o = await r.service.signIn(SignInRequestProvider.apple);
        expect(r.hasAccountToken, isTrue);
        o as SignedIn;
        expect(o.moveRefused, isTrue);
        expect(o.nextMoveAt, DateTime.utc(2026, 12, 1, 10));
        expect(o.restoreHint, RestoreHint.none);
        expect(o.linkedWithoutGold, isTrue);
      },
    );

    test('R5-3(b): restoreSuggested offers Restore only with a StoreKit '
        'transaction', () async {
      final with_ = _Rig(storeKit: {'zaghlol_gold_yearly'});
      with_.backend.onSignIn = (req, n) async =>
          _ok(with_.h, n, restoreSuggested: true);
      expect(
        (await with_.service.signIn(
          SignInRequestProvider.apple,
        ) as SignedIn).restoreHint,
        RestoreHint.offerRestore,
      );
      final without = _Rig();
      without.backend.onSignIn = (req, n) async => _ok(
        without.h,
        n,
        restoreSuggested: true,
        nextMoveAt: '2026-12-01T10:00:00Z',
      );
      final o =
          await without.service.signIn(SignInRequestProvider.apple) as SignedIn;
      expect(o.restoreHint, RestoreHint.supportPath);
      expect(o.nextMoveAt, isNotNull);
    });

    test('moved from another phone is reported without a hint', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n, moved: true);
      final o =
          await r.service.signIn(SignInRequestProvider.google) as SignedIn;
      expect(o.movedFromOtherPhone, isTrue);
      expect(o.linkedWithoutGold, isFalse);
    });

    test('cancel sends nothing', () async {
      final r = _Rig();
      r.tokens.error = const SignInCancelledException();
      expect(
        await r.service.signIn(SignInRequestProvider.google),
        isA<SignInCancelled>(),
      );
      expect(r.backend.requests, isEmpty);
    });

    test('offline is try-later and stores nothing', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async =>
          throw BackendFailure(BackendFailureKind.offline);
      expect(
        await r.service.signIn(SignInRequestProvider.google),
        isA<SignInTryLater>(),
      );
      expect(r.hasAccountToken, isFalse);
    });

    test('EC-46: 409 asks first; the confirmed repeat draws a fresh token '
        'and nonce and sets replaceLink', () async {
      final r = _Rig();
      var first = true;
      r.backend.onSignIn = (req, n) async {
        if (first) {
          first = false;
          throw goldProblem(ProblemCode.installLinkedToOtherAccount, 409);
        }
        return _ok(r.h, n);
      };
      expect(
        await r.service.signIn(SignInRequestProvider.google),
        isA<SignInNeedsReplaceConfirm>(),
      );
      expect(r.hasAccountToken, isFalse);
      expect(
        await r.service.signIn(SignInRequestProvider.google, replaceLink: true),
        isA<SignedIn>(),
      );
      expect(r.backend.requests[0].replaceLink, isNull);
      expect(r.backend.requests[1].replaceLink, isTrue);
      expect(r.backend.requests[0].nonce, isNot(r.backend.requests[1].nonce));
      expect(r.tokens.hashed, hasLength(2));
    });
  });

  group('seat keys', () {
    test(
      'iOS: own key first, signed over op=signin and SHA-256(raw nonce)',
      () async {
        final r = _Rig();
        r.seats.sigs = FakeSeatProver.two();
        r.backend.onSignIn = (req, n) async => _ok(r.h, n);
        await r.service.signIn(SignInRequestProvider.google);
        final q = r.backend.requests.single;
        expect(q.seatKeys, hasLength(2));
        expect(r.seats.calls, ['signin']);
        expect(r.seats.challenges.single, signinSeatChallenge(q.nonce));
      },
    );

    test('Android never sends seatKeys and never asks for proofs', () async {
      final r = _Rig(platform: ClientPlatform.android);
      r.seats.sigs = FakeSeatProver.two();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n);
      await r.service.signIn(SignInRequestProvider.google);
      expect(r.backend.requests.single.seatKeys, isNull);
      expect(r.seats.calls, isEmpty);
    });

    test(
      'R5-6: SEAT_KEY_MISMATCH retries once with a fresh token and nonce '
      'and no seatKeys; afterwards no seatKeys, one prompt, one request',
      () async {
        final r = _Rig();
        r.seats.sigs = FakeSeatProver.two();
        var calls = 0;
        r.backend.onSignIn = (req, n) async {
          calls++;
          if (req.seatKeys != null) {
            throw goldProblem(ProblemCode.seatKeyMismatch, 400);
          }
          return _ok(r.h, n);
        };
        expect(
          await r.service.signIn(SignInRequestProvider.google),
          isA<SignedIn>(),
        );
        expect(calls, 2);
        expect(r.tokens.hashed, hasLength(2));
        expect(r.backend.requests[0].nonce, isNot(r.backend.requests[1].nonce));
        expect(r.backend.requests[1].seatKeys, isNull);
        expect(r.seats.unusableMarked, isTrue);

        // Later sign-in: T-179 reports the key unusable, so no seatKeys, no
        // second 400 and no second provider prompt.
        await r.service.signIn(SignInRequestProvider.google);
        expect(calls, 3);
        expect(r.tokens.hashed, hasLength(3));
        expect(r.backend.requests[2].seatKeys, isNull);
      },
    );

    test('a second SEAT_KEY_MISMATCH is a failure and sets no flag', () async {
      final r = _Rig();
      r.seats.sigs = FakeSeatProver.two();
      r.backend.onSignIn = (req, n) async =>
          throw goldProblem(ProblemCode.seatKeyMismatch, 400);
      expect(
        await r.service.signIn(SignInRequestProvider.google),
        isA<SignInFailed>(),
      );
      expect(r.backend.requests, hasLength(2));
      expect(r.seats.unusableMarked, isFalse);
    });
  });

  group('negative proofs', () {
    test('an account token for another install is never stored', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n, iid: installB);
      expect(
        await r.service.signIn(SignInRequestProvider.google),
        isA<SignInFailed>(),
      );
      expect(r.hasAccountToken, isFalse);
      expect(await r.service.isSignedIn(), isFalse);
      expect(r.h.sink.last, isNot(EntitlementPhase.active));
    });

    test('sign-out removes the account and entitlement tokens even when the '
        'call fails; account-linked Gold shows paused at once', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n);
      await r.service.signIn(SignInRequestProvider.google);
      expect(r.hasAccountToken, isTrue);
      expect(await r.h.service.evaluate(), EntitlementPhase.active);

      r.h.backend.onSignOut = (n) async =>
          throw BackendFailure(BackendFailureKind.offline);
      final o = await r.service.signOut();
      expect((o as SignedOut).serverConfirmed, isFalse);
      expect(r.hasAccountToken, isFalse);
      expect(r.h.store.values[BackendStateKeys.entitlementToken], isNull);
      expect(r.h.sink.last, EntitlementPhase.paused);
      expect(await r.h.service.evaluate(), EntitlementPhase.paused);
      expect(await r.service.isSignedIn(), isFalse);
    });
  });

  group('delete account', () {
    test('the account token is cleared only after the server confirmed; '
        'linked Gold pauses', () async {
      final r = _Rig();
      r.backend.onSignIn = (req, n) async => _ok(r.h, n);
      await r.service.signIn(SignInRequestProvider.google);

      r.backend.onDelete = () async =>
          throw BackendFailure(BackendFailureKind.offline);
      expect(await r.service.deleteAccount(), isA<DeleteAccountTryLater>());
      expect(r.hasAccountToken, isTrue);

      r.backend.onDelete = () async {};
      expect(await r.service.deleteAccount(), isA<AccountDeleted>());
      expect(r.backend.deletes, 2);
      expect(r.hasAccountToken, isFalse);
      expect(r.h.sink.last, EntitlementPhase.paused);
    });

    test('no token, or a refused one, asks for sign-in first', () async {
      final r = _Rig();
      r.backend.onDelete = () async =>
          throw BackendFailure(BackendFailureKind.notSignedIn);
      expect(await r.service.deleteAccount(), isA<DeleteAccountNeedsSignIn>());
      r.backend.onDelete = () async =>
          throw goldProblem(ProblemCode.accountTokenExpired, 401);
      expect(await r.service.deleteAccount(), isA<DeleteAccountNeedsSignIn>());
    });
  });
}
