// T-147: optional sign-in (FR-ACCT-*, FR-GOLD-07, backend-api §4.6), sign-out
// (D-61(c)) and account deletion. Sign-in exists only to carry Gold across
// phones; no financial data is ever sent.
//
// One sign-in:
//  1. A fresh raw nonce (>= 128 bits, CSPRNG, in memory) per provider
//     attempt; the provider gets hex(SHA-256(raw)), the backend gets raw.
//  2. iOS only: seat proofs (op = signin, challenge = SHA-256(raw)) from
//     T-179, own key first; none when T-179 says so. Android never sends
//     `seatKeys` (also refused by BackendClient).
//  3. POST /v1/accounts/signin through the T-144 time anchor, whose handler
//     applies the install-binding check (R5-1) before storing the account
//     token. A token that was not stored is a failed sign-in, never a success.
// Retries: `SEAT_KEY_MISMATCH` once, with a fresh ID token and nonce and no
// `seatKeys`; a success then sets the R5-6 flag. The 409 for another account
// asks the user first and then repeats the whole flow with `replaceLink`
// (the first ID token is spent: the server commits its replay guard first).
//
// Nothing here logs; no token, nonce, key or account ID reaches an error.

import 'dart:convert';
import 'dart:math';

import '../../../core/backend/backend_client.dart';
import '../../../core/platform/seat_key_api.g.dart' show SeatSignature;
import '../../gold/application/entitlement.dart';
import '../../gold/application/gold_ports.dart' show SeatProver;
import '../../gold/application/gold_store.dart';
import '../../gold/domain/binding/request_binding.dart';
import '../domain/sign_in_outcome.dart';
import 'id_token_source.dart';
import 'nonce.dart';

/// The backend calls the account service makes (`BackendClient` in
/// production, a fake in tests).
abstract interface class AccountBackend {
  Future<String> ensureInstalled();
  Future<SignInResponse> signIn(SignInRequest request, TimeNonce nonce);
  Future<void> deleteAccount();
}

final class BackendClientAccountBackend implements AccountBackend {
  BackendClientAccountBackend(this._client);
  final BackendClient _client;

  @override
  Future<String> ensureInstalled() => _client.ensureInstalled();

  @override
  Future<SignInResponse> signIn(SignInRequest request, TimeNonce nonce) =>
      _client.signIn(_client.prepareSignIn(request), timeNonce: nonce);

  @override
  Future<void> deleteAccount() => _client.deleteAccount();
}

/// R5-3(b): whether this device's Apple ID has a StoreKit transaction for a
/// Gold product (T-145). Always false on Android.
typedef StoreKitCheck = Future<bool> Function(String productId);

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

final class AccountService {
  AccountService({
    required this._backend,
    required this._entitlement,
    required this._seats,
    required this._tokens,
    required this._platform,
    required this._hasStoreKitTransaction,
    Random? random,
  }) : _rng = random ?? Random.secure();

  final AccountBackend _backend;
  final EntitlementService _entitlement;
  final SeatProver _seats;
  final IdTokenSource _tokens;
  final ClientPlatform _platform;
  final StoreKitCheck _hasStoreKitTransaction;
  final Random _rng;

  /// True while a valid account token for this install is cached.
  Future<bool> isSignedIn() async {
    final installId = await _backend.ensureInstalled();
    final a = await _entitlement.cachedAccount();
    return a != null && a.iid == installId;
  }

  Future<SignInOutcome> signIn(
    SignInRequestProvider provider, {
    bool replaceLink = false,
  }) async {
    final String installId;
    try {
      installId = await _backend.ensureInstalled();
    } on BackendFailure catch (f) {
      return _later(f);
    }
    var withSeatKeys = _platform == ClientPlatform.ios;
    var mismatchRetried = false;
    while (true) {
      final raw = newRawNonce(_rng);
      final ProviderCredential cred;
      try {
        cred = await _tokens.obtain(provider, hashedNonce: providerNonce(raw));
      } on SignInCancelledException {
        return const SignInCancelled();
      } on SignInProviderException {
        return const SignInFailed();
      }
      final List<SeatSignature> sigs = withSeatKeys
          ? await _seats.prove(SeatOp.signin, signinSeatChallenge(raw))
          : const [];
      final SignInRequest request;
      try {
        request = SignInRequest(
          provider: provider,
          idToken: cred.idToken,
          nonce: raw,
          authorizationCode: cred.authorizationCode,
          replaceLink: replaceLink ? true : null,
          seatKeys: sigs.isEmpty
              ? null
              : [
                  for (final s in sigs)
                    SeatKeyProof(
                      publicKey: _b64u(s.publicKey),
                      signature: _b64u(s.signature),
                    ),
                ],
        );
        request.toJson(); // validates before anything is sent
      } on ApiModelException {
        return const SignInFailed();
      }
      try {
        final resp = await _entitlement.anchored(
          (n) => _backend.signIn(request, n),
          SignedBody.fromSignIn,
        );
        // The anchor stored the token only if it is bound to this install.
        final stored = await _entitlement.cachedAccount();
        if (stored == null ||
            stored.iid != installId ||
            stored.sub != resp.accountId) {
          return const SignInFailed();
        }
        if (mismatchRetried && !withSeatKeys) {
          // R5-6: the retry without seatKeys worked, so the own key is the
          // problem. Stop sending it from this install.
          await _seats.markOwnKeyUnusable();
        }
        return await _outcome(resp);
      } on BackendFailure catch (f) {
        if (f.kind == BackendFailureKind.problem) {
          switch (f.problem) {
            case ProblemCode.seatKeyMismatch
                when withSeatKeys && !mismatchRetried:
              withSeatKeys = false;
              mismatchRetried = true;
              continue;
            case ProblemCode.installLinkedToOtherAccount when !replaceLink:
              return const SignInNeedsReplaceConfirm();
            default:
              break;
          }
        }
        return f.retryable ? _later(f) : const SignInFailed();
      }
    }
  }

  Future<SignInOutcome> _outcome(SignInResponse r) async {
    final next = r.nextMoveAt == null ? null : DateTime.tryParse(r.nextMoveAt!);
    var hint = RestoreHint.none;
    if (r.restoreSuggested == true) {
      hint = await _anyStoreKitTransaction()
          ? RestoreHint.offerRestore
          : RestoreHint.supportPath;
    }
    return SignedIn(
      movedFromOtherPhone: r.movedFromOtherPhone == true,
      moveRefused: r.moveRefused == true,
      nextMoveAt: next?.toUtc(),
      restoreHint: hint,
    );
  }

  Future<bool> _anyStoreKitTransaction() async {
    for (final id in GoldProducts.all) {
      try {
        if (await _hasStoreKitTransaction(id)) return true;
      } on Object {
        // An unreadable store counts as "no transaction": no Restore button.
      }
    }
    return false;
  }

  /// D-61(c): T-144 drops the cached entitlement and account tokens first,
  /// so a failed call (offline) still signs out. Local data stays.
  Future<SignOutOutcome> signOut() async {
    try {
      await _entitlement.signOut();
      return const SignedOut(serverConfirmed: true);
    } on BackendFailure {
      return const SignedOut(serverConfirmed: false);
    }
  }

  /// `DELETE /v1/accounts/me`. The account token is cleared only after the
  /// server confirmed (204): until then the user can retry.
  Future<DeleteAccountOutcome> deleteAccount() async {
    try {
      await _backend.deleteAccount();
    } on BackendFailure catch (f) {
      if (f.kind == BackendFailureKind.notSignedIn ||
          f.problem == ProblemCode.accountTokenExpired) {
        return const DeleteAccountNeedsSignIn();
      }
      return f.retryable
          ? const DeleteAccountTryLater()
          : const DeleteAccountFailed();
    }
    await _entitlement.clearAccountToken();
    return const AccountDeleted();
  }

  SignInOutcome _later(BackendFailure f) => f.retryable
      ? SignInTryLater(retryAfter: f.retryAfter)
      : const SignInFailed();

  @override
  String toString() => 'AccountService';
}
