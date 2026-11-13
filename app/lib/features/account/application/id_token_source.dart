// T-147: where the provider's ID token comes from. The service only knows
// this port; the production classes wrap google_sign_in 7.x and
// sign_in_with_apple. No class here prints, logs or stores a token.

import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/backend/backend_client.dart'
    show ClientPlatform, SignInRequestProvider;
import '../../backup/data/drive_auth.dart'
    show googleIosClientId, googleServerClientId;
import 'apple_state.dart';

/// What the provider gave back. [authorizationCode] is Apple's (the backend
/// uses it only to revoke on account deletion).
final class ProviderCredential {
  const ProviderCredential({required this.idToken, this.authorizationCode});
  final String idToken;
  final String? authorizationCode;

  @override
  String toString() => 'ProviderCredential';
}

/// The user closed the provider's sheet.
final class SignInCancelledException implements Exception {
  const SignInCancelledException();
  @override
  String toString() => 'SignInCancelledException';
}

/// Anything else that kept a credential from arriving (not configured,
/// provider error, unknown or expired `state`). Carries no provider text.
final class SignInProviderException implements Exception {
  const SignInProviderException();
  @override
  String toString() => 'SignInProviderException';
}

abstract interface class IdTokenSource {
  /// Runs the provider flow with [hashedNonce] (`hex(SHA-256(raw))`) and
  /// returns the credential. Throws [SignInCancelledException] or
  /// [SignInProviderException].
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  });
}

// ---- Google (google_sign_in 7.x) --------------------------------------------

/// The two google_sign_in calls the app makes, so a test can stand in for the
/// plugin.
abstract interface class GoogleSignInPort {
  /// `GoogleSignIn.instance.initialize(...)`.
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
  });

  /// `authenticate()`; the ID token, or null when the plugin gave none.
  /// Throws [SignInCancelledException] when the user cancelled.
  Future<String?> authenticateIdToken();
}

final class PluginGoogleSignInPort implements GoogleSignInPort {
  PluginGoogleSignInPort({GoogleSignIn? signIn})
    : _signIn = signIn ?? GoogleSignIn.instance;
  final GoogleSignIn _signIn;

  @override
  Future<void> initialize({
    String? clientId,
    String? serverClientId,
    String? nonce,
  }) => _signIn.initialize(
    clientId: clientId,
    serverClientId: serverClientId,
    nonce: nonce,
  );

  @override
  Future<String?> authenticateIdToken() async {
    if (!_signIn.supportsAuthenticate()) {
      throw const SignInProviderException();
    }
    try {
      final account = await _signIn.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const SignInCancelledException();
      }
      throw const SignInProviderException();
    }
  }
}

/// google_sign_in 7.x holds the nonce in `initialize`, so a **fresh nonce per
/// attempt** means one `initialize(nonce:)` per attempt (R2-9). In 7.2.0
/// (google_sign_in_android 7.2.19, google_sign_in_ios 6.4.0) `init` only
/// stores the nonce (iOS also re-runs `configure`), so repeating it is safe in
/// code; the package docs say "exactly once", so the T-172 device check
/// ("two Google sign-ins, two different `nonce` claims") stays open.
///
/// Attempts are serialized: a second one waits for the first.
final class GoogleIdTokenSource implements IdTokenSource {
  GoogleIdTokenSource({
    required this._port,
    required this.isIos,
    this.clientId = googleIosClientId,
    this.serverClientId = googleServerClientId,
  });

  final GoogleSignInPort _port;
  final bool isIos;
  final String clientId;
  final String serverClientId;
  Future<void> _tail = Future<void>.value();

  @override
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  }) {
    if (provider != SignInRequestProvider.google) {
      throw const SignInProviderException();
    }
    final run = _tail.then((_) => _attempt(hashedNonce));
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<ProviderCredential> _attempt(String hashedNonce) async {
    if (isIos ? clientId.isEmpty : serverClientId.isEmpty) {
      throw const SignInProviderException();
    }
    try {
      await _port.initialize(
        clientId: isIos ? clientId : null,
        serverClientId: serverClientId.isEmpty ? null : serverClientId,
        nonce: hashedNonce,
      );
    } on Object {
      throw const SignInProviderException();
    }
    final token = await _port.authenticateIdToken();
    if (token == null || token.isEmpty) {
      throw const SignInProviderException();
    }
    return ProviderCredential(idToken: token);
  }
}

// ---- Apple (sign_in_with_apple) ---------------------------------------------

/// What Apple's flow returned; [state] is echoed back on the Android web flow.
final class AppleCredentialResult {
  const AppleCredentialResult({
    required this.identityToken,
    required this.authorizationCode,
    this.state,
  });
  final String? identityToken;
  final String authorizationCode;
  final String? state;

  @override
  String toString() => 'AppleCredentialResult';
}

abstract interface class ApplePort {
  /// Native sheet on iOS; Custom Tab to `appleid.apple.com` on Android (the
  /// backend callback hands the result back, backend-api §4.6). Throws
  /// [SignInCancelledException] on cancel.
  Future<AppleCredentialResult> authorize({
    required String hashedNonce,
    String? state,
  });
}

const String appleServicesId = String.fromEnvironment(
  'ZAGHLOL_APPLE_SERVICES_ID',
);
const String appleAndroidRedirect = String.fromEnvironment(
  'ZAGHLOL_APPLE_REDIRECT',
  defaultValue: 'https://api.zaghlol.app/v1/apple/android-callback',
);

final class PluginApplePort implements ApplePort {
  PluginApplePort({required this.isAndroid});
  final bool isAndroid;

  @override
  Future<AppleCredentialResult> authorize({
    required String hashedNonce,
    String? state,
  }) async {
    try {
      final c = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
        state: state,
        webAuthenticationOptions: isAndroid
            ? WebAuthenticationOptions(
                clientId: appleServicesId,
                redirectUri: Uri.parse(appleAndroidRedirect),
              )
            : null,
      );
      return AppleCredentialResult(
        identityToken: c.identityToken,
        authorizationCode: c.authorizationCode,
        state: c.state,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const SignInCancelledException();
      }
      throw const SignInProviderException();
    } on SignInWithAppleException {
      throw const SignInProviderException();
    }
  }
}

/// iOS: the native sheet. Android: the web flow with a random single-use
/// `state` (<= 10 min) that is checked on return (backend-api §4.6 step 4).
/// The plugin never resolves when the user closes the Custom Tab, so the
/// wait ends with the state's lifetime and counts as a cancel.
final class AppleIdTokenSource implements IdTokenSource {
  AppleIdTokenSource({
    required this.platform,
    required this._port,
    required this._guard,
    this.servicesId = appleServicesId,
  });

  final ClientPlatform platform;
  final ApplePort _port;
  final AppleStateGuard _guard;
  final String servicesId;

  @override
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  }) async {
    if (provider != SignInRequestProvider.apple) {
      throw const SignInProviderException();
    }
    final android = platform == ClientPlatform.android;
    if (android && servicesId.isEmpty) throw const SignInProviderException();
    final state = android ? _guard.issue() : null;
    final AppleCredentialResult r;
    try {
      final call = _port.authorize(hashedNonce: hashedNonce, state: state);
      r = android
          ? await call.timeout(
              appleStateLifetime,
              onTimeout: () => throw const SignInCancelledException(),
            )
          : await call;
    } on SignInCancelledException {
      _guard.consume(null);
      rethrow;
    }
    if (android && !_guard.consume(r.state)) {
      throw const SignInProviderException();
    }
    final token = r.identityToken;
    if (token == null || token.isEmpty) throw const SignInProviderException();
    return ProviderCredential(
      idToken: token,
      authorizationCode: r.authorizationCode.isEmpty
          ? null
          : r.authorizationCode,
    );
  }
}

/// Routes to the provider's source.
final class RoutingIdTokenSource implements IdTokenSource {
  RoutingIdTokenSource({required this.google, required this.apple});
  final IdTokenSource google;
  final IdTokenSource apple;

  @override
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  }) => switch (provider) {
    SignInRequestProvider.google => google.obtain(
      provider,
      hashedNonce: hashedNonce,
    ),
    SignInRequestProvider.apple => apple.obtain(
      provider,
      hashedNonce: hashedNonce,
    ),
    SignInRequestProvider.unknown => throw const SignInProviderException(),
  };
}
