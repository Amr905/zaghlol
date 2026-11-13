// T-147: the provider sources (fake plugins) and the Apple `state` guard.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/features/account/application/apple_state.dart';
import 'package:zaghlol/features/account/application/id_token_source.dart';

final class _FakeGoogle implements GoogleSignInPort {
  final List<String?> nonces = [];
  int order = 0;
  final List<String> events = [];
  String? token = 'a.b.c';
  Object? cancel;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
  }) async {
    nonces.add(nonce);
    events.add('init');
  }

  @override
  Future<String?> authenticateIdToken() async {
    events.add('auth');
    if (cancel != null) throw cancel!;
    return token;
  }
}

final class _FakeApple implements ApplePort {
  final List<String?> states = [];
  final List<String> nonces = [];
  String? echoState;
  bool echoWhatWasSent = true;
  String? identityToken = 'a.b.c';
  Object? error;
  @override
  Future<AppleCredentialResult> authorize({
    required String hashedNonce,
    String? state,
  }) async {
    nonces.add(hashedNonce);
    states.add(state);
    if (error != null) throw error!;
    return AppleCredentialResult(
      identityToken: identityToken,
      authorizationCode: 'code1',
      state: echoWhatWasSent ? state : echoState,
    );
  }
}

void main() {
  group('Google: a fresh nonce is set for every attempt (R2-9)', () {
    test('initialize(nonce:) runs before each authenticate with that '
        "attempt's value", () async {
      final p = _FakeGoogle();
      final s = GoogleIdTokenSource(
        port: p,
        isIos: false,
        serverClientId: 'server-id',
      );
      await s.obtain(SignInRequestProvider.google, hashedNonce: 'aa');
      await s.obtain(SignInRequestProvider.google, hashedNonce: 'bb');
      expect(p.nonces, ['aa', 'bb']);
      expect(p.events, ['init', 'auth', 'init', 'auth']);
    });

    test('not configured, cancel and an empty token are typed', () async {
      final p = _FakeGoogle();
      await expectLater(
        GoogleIdTokenSource(
          port: p,
          isIos: true,
          clientId: '',
          serverClientId: 'x',
        ).obtain(SignInRequestProvider.google, hashedNonce: 'aa'),
        throwsA(isA<SignInProviderException>()),
      );
      final s = GoogleIdTokenSource(port: p, isIos: false, serverClientId: 'x');
      p.cancel = const SignInCancelledException();
      await expectLater(
        s.obtain(SignInRequestProvider.google, hashedNonce: 'aa'),
        throwsA(isA<SignInCancelledException>()),
      );
      p.cancel = null;
      p.token = '';
      await expectLater(
        s.obtain(SignInRequestProvider.google, hashedNonce: 'aa'),
        throwsA(isA<SignInProviderException>()),
      );
    });
  });

  group('AppleStateGuard', () {
    test('accepts the issued value once', () {
      final g = AppleStateGuard();
      final s = g.issue();
      expect(s, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
      expect(g.consume(s), isTrue);
      expect(g.consume(s), isFalse); // reused
    });

    test('rejects an unknown, a missing and an expired value', () {
      var now = DateTime.utc(2026, 11, 14, 10);
      final g = AppleStateGuard(now: () => now);
      g.issue();
      expect(g.consume('not-the-issued-value-aaaaaaaa'), isFalse);
      final s = g.issue();
      expect(g.consume(null), isFalse);
      expect(g.consume(s), isFalse); // a wrong try burns it
      final s2 = g.issue();
      now = now.add(appleStateLifetime + const Duration(seconds: 1));
      expect(g.consume(s2), isFalse);
      final s3 = g.issue();
      now = now.add(appleStateLifetime);
      expect(g.consume(s3), isTrue); // exactly 10 minutes is still valid
    });

    test('two issues give different values; a new one replaces the old', () {
      final g = AppleStateGuard();
      final a = g.issue();
      final b = g.issue();
      expect(a, isNot(b));
      expect(g.consume(a), isFalse);
    });
  });

  group('AppleIdTokenSource', () {
    test('Android: sends a state and accepts its echo', () async {
      final p = _FakeApple();
      final s = AppleIdTokenSource(
        platform: ClientPlatform.android,
        port: p,
        guard: AppleStateGuard(),
        servicesId: 'svc',
      );
      final c = await s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh');
      expect(p.states.single, isNotNull);
      expect(p.nonces.single, 'hh');
      expect(c.idToken, 'a.b.c');
      expect(c.authorizationCode, 'code1');
    });

    test(
      'Android: an unknown or missing state on return is rejected',
      () async {
        final p = _FakeApple()
          ..echoWhatWasSent = false
          ..echoState = 'forged-state-forged-state';
        final s = AppleIdTokenSource(
          platform: ClientPlatform.android,
          port: p,
          guard: AppleStateGuard(),
          servicesId: 'svc',
        );
        await expectLater(
          s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh'),
          throwsA(isA<SignInProviderException>()),
        );
        p.echoState = null;
        await expectLater(
          s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh'),
          throwsA(isA<SignInProviderException>()),
        );
      },
    );

    test(
      'Android: a state older than 10 minutes on return is rejected',
      () async {
        var now = DateTime.utc(2026, 11, 14, 10);
        final p = _LatePort(() => now = now.add(const Duration(minutes: 11)));
        final s = AppleIdTokenSource(
          platform: ClientPlatform.android,
          port: p,
          guard: AppleStateGuard(now: () => now),
          servicesId: 'svc',
        );
        await expectLater(
          s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh'),
          throwsA(isA<SignInProviderException>()),
        );
      },
    );

    test('iOS: no state, native sheet; cancel is typed', () async {
      final p = _FakeApple();
      final s = AppleIdTokenSource(
        platform: ClientPlatform.ios,
        port: p,
        guard: AppleStateGuard(),
      );
      await s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh');
      expect(p.states.single, isNull);
      p.error = const SignInCancelledException();
      await expectLater(
        s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh'),
        throwsA(isA<SignInCancelledException>()),
      );
    });

    test('a missing identity token is a failure', () async {
      final p = _FakeApple()..identityToken = null;
      final s = AppleIdTokenSource(
        platform: ClientPlatform.ios,
        port: p,
        guard: AppleStateGuard(),
      );
      await expectLater(
        s.obtain(SignInRequestProvider.apple, hashedNonce: 'hh'),
        throwsA(isA<SignInProviderException>()),
      );
    });
  });
}

/// Echoes the state it was given, but only after the clock passed 10 minutes.
final class _LatePort implements ApplePort {
  _LatePort(this._advance);
  final void Function() _advance;
  @override
  Future<AppleCredentialResult> authorize({
    required String hashedNonce,
    String? state,
  }) async {
    _advance();
    return AppleCredentialResult(
      identityToken: 'a.b.c',
      authorizationCode: 'c',
      state: state,
    );
  }
}
