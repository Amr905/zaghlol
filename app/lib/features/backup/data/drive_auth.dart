// T-150 (design note §1, §7): Drive authorization with google_sign_in 7 and
// the `drive.appdata` scope only. Interactive steps (account picker,
// consent) run only when the caller says the user is present. The access
// token lives in a local variable and the request header only: it is never
// stored, logged or interpolated (google_sign_in's authorization object
// prints the token in toString, so it is never passed to a string).

import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'drive_backup_exception.dart';
import 'drive_files.dart';

/// Gives a short-lived Drive access token.
abstract interface class DriveAuthorizer {
  /// A token for [driveAppDataScope]. With [interactive] false, a needed
  /// sign-in or consent throws signInRequired instead of showing UI.
  Future<String> accessToken({required bool interactive});

  /// Drops a token Drive refused (401) so the next call gets a fresh one.
  Future<void> clearToken(String token);
}

/// OAuth client IDs (Google Cloud console), injected at build time. Empty →
/// notConfigured (fail closed). iOS also needs the reversed client ID as a
/// URL scheme in Info.plist (PO setup, task T-150 design note §8).
const String googleIosClientId = String.fromEnvironment(
  'ZAGHLOL_GOOGLE_IOS_CLIENT_ID',
);
const String googleServerClientId = String.fromEnvironment(
  'ZAGHLOL_GOOGLE_SERVER_CLIENT_ID',
);

final class GoogleSignInDriveAuthorizer implements DriveAuthorizer {
  GoogleSignInDriveAuthorizer({
    GoogleSignIn? signIn,
    this.clientId = googleIosClientId,
    this.serverClientId = googleServerClientId,
    required this.isIos,
  }) : _signIn = signIn ?? GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  final String clientId;
  final String serverClientId;
  final bool isIos;
  Future<void>? _init;

  static const List<String> _scopes = [driveAppDataScope];

  Future<void> _ensureInit() {
    if (isIos ? clientId.isEmpty : serverClientId.isEmpty) {
      throw DriveBackupException(DriveBackupErrorCode.notConfigured);
    }
    return _init ??= _signIn
        .initialize(
          clientId: isIos ? clientId : null,
          serverClientId: serverClientId.isEmpty ? null : serverClientId,
        )
        .catchError((Object _) {
          _init = null;
          throw DriveBackupException(DriveBackupErrorCode.notConfigured);
        });
  }

  @override
  Future<String> accessToken({required bool interactive}) async {
    await _ensureInit();
    try {
      var account = await _signIn.attemptLightweightAuthentication();
      if (account == null) {
        if (!interactive || !_signIn.supportsAuthenticate()) {
          throw DriveBackupException(DriveBackupErrorCode.signInRequired);
        }
        account = await _signIn.authenticate(scopeHint: _scopes);
      }
      final client = account.authorizationClient;
      final existing = await client.authorizationForScopes(_scopes);
      if (existing != null) return existing.accessToken;
      if (!interactive) {
        throw DriveBackupException(DriveBackupErrorCode.signInRequired);
      }
      final granted = await client.authorizeScopes(_scopes);
      return granted.accessToken;
    } on DriveBackupException {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw DriveBackupException(switch (e.code) {
        GoogleSignInExceptionCode.canceled ||
        GoogleSignInExceptionCode.interrupted =>
          DriveBackupErrorCode.signInCancelled,
        GoogleSignInExceptionCode.uiUnavailable =>
          DriveBackupErrorCode.signInRequired,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          DriveBackupErrorCode.notConfigured,
        _ => DriveBackupErrorCode.authorizationDenied,
      });
    } on Object catch (e) {
      throw DriveBackupException(classifyDriveError(e));
    }
  }

  @override
  Future<void> clearToken(String token) async {
    try {
      await _signIn.authorizationClient.clearAuthorizationToken(
        accessToken: token,
      );
    } on Object {
      // Best effort: the next authorization asks Google again anyway.
    }
  }
}

/// Adds the bearer token to every request; nothing else.
final class BearerClient extends http.BaseClient {
  BearerClient(this._token, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final String _token;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();

  @override
  String toString() => 'BearerClient';
}

/// Opens a Drive session for one store operation.
abstract interface class DriveConnector {
  /// A session and the token it uses (for [DriveAuthorizer.clearToken]).
  Future<(DriveFiles, String)> connect({required bool interactive});

  Future<void> refused(String token);
}

final class GoogleDriveConnector implements DriveConnector {
  GoogleDriveConnector(this._auth);

  final DriveAuthorizer _auth;

  @override
  Future<(DriveFiles, String)> connect({required bool interactive}) async {
    final token = await _auth.accessToken(interactive: interactive);
    return (GoogleapisDriveFiles(BearerClient(token)), token);
  }

  @override
  Future<void> refused(String token) => _auth.clearToken(token);
}
