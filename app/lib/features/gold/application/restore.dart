// T-145: restore (backend-api §4.3 Restore, ADR-012 Part B (d), D-45, D-52…
// D-55, R2-1, R3-8, R4-1(1)(3), R5-3(b), R5-6) and the D-55 warning data.
//
// Order of work for one restore:
//  1. Body from the store's purchases (no attestation yet).
//  2. `bodyHash` over exactly that text with THIS install's ID (T-183). The
//     strict parser runs first: a body it rejects is never sent.
//  3. Android: Play Integrity `prepare()` (only now), then `attest(bodyHash)`.
//     iOS: seat-key signatures over `bodyHash` FIRST, then
//     `clientDataHash` over the public keys in that order, then `attest`.
//  4. `POST /v1/purchases/restore` through the time anchor. Never without a
//     proof.
// Retries (each at most once): `DEVICE_ATTESTATION_FAILED` (iOS: new key;
// Android: fresh token), `SEAT_KEY_MISMATCH` (without seatKeys; success sets
// the R5-6 flag). `MOVE_COOLDOWN` is stored and never retried.
//
// Nothing here logs; no token, key, assertion or purchase reaches an error.

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../../core/platform/pigeon_attestation.dart';
import '../../../core/platform/seat_key_api.g.dart' show SeatSignature;
import '../domain/binding/binding_exceptions.dart';
import '../domain/binding/request_binding.dart';
import '../domain/restore_outcome.dart';
import 'entitlement.dart';
import 'gating.dart';
import 'gold_ports.dart';
import 'gold_store.dart';

/// `secure_state` key: the last `MOVE_COOLDOWN` `nextMoveAt` (ISO text).
const String restoreNextMoveAtStateKey = 'restore_next_move_at';

/// Platform attestation hiccups are retried 3 times within about a minute.
const List<Duration> attestRetryDelays = [
  Duration(seconds: 5),
  Duration(seconds: 20),
];

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

final class RestoreService {
  RestoreService({
    required this._store,
    required this._backend,
    required this._entitlement,
    required this._seats,
    required this._attestation,
    required this._state,
    required this._platform,
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  }) : _delay = delay ?? ((d) => Future<void>.delayed(d)),
       _now = now ?? DateTime.now;

  final GoldStore _store;
  final GoldBackend _backend;
  final EntitlementService _entitlement;
  final SeatProver _seats;
  final PigeonAttestation _attestation;
  final BackendStateStore _state;
  final ClientPlatform _platform;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

  /// The stored `nextMoveAt` of the last `MOVE_COOLDOWN`, while still ahead.
  Future<DateTime?> storedNextMoveAt() async {
    final raw = await _state.read(restoreNextMoveAtStateKey);
    if (raw == null) return null;
    final t = DateTime.tryParse(utf8.decode(raw, allowMalformed: true));
    if (t == null || !t.isAfter(_now())) return null;
    return t.toUtc();
  }

  Future<RestoreOutcome> restore() async {
    final String installId;
    final List<OwnedPurchase> owned;
    try {
      installId = await _backend.ensureInstalled();
      owned = await _store.queryOwned();
    } on BackendFailure catch (f) {
      return _tryLater(f);
    } on StoreQueryException {
      return const RestoreStoreUnavailable();
    }
    if (owned.isEmpty) return const RestoreNothingToRestore();
    final items = owned.take(20).toList();

    // 1-2. Body without attestation, hashed exactly as it will be sent.
    final Uint8List bodyHash;
    try {
      final body = _bodyWithoutAttestation(items);
      bodyHash = restoreBodyHashFromJson(installId, jsonEncode(body));
    } on BindingException {
      return const RestoreBodyRejected();
    } on ApiModelException {
      return const RestoreBodyRejected();
    }

    if (_platform == ClientPlatform.android) {
      try {
        await _withTransientRetry(_attestation.prepare);
      } on AttestationException catch (e) {
        return _attestationFailure(e);
      }
    }

    var withSeatKeys = _platform == ClientPlatform.ios;
    var mismatchRetried = false;
    var attestRetried = false;
    var forceNewKey = false;
    while (true) {
      _Sent sent;
      try {
        sent = await _buildRequest(
          items,
          bodyHash,
          withSeatKeys: withSeatKeys,
          forceNewKey: forceNewKey,
        );
      } on AttestationException catch (e) {
        return _attestationFailure(e);
      } on ApiModelException {
        return const RestoreBodyRejected();
      }
      try {
        final resp = await _entitlement.anchored(
          (nonce) => _backend.restore(sent.request, nonce),
          SignedBody.fromRestore,
        );
        await _state.delete(restoreNextMoveAtStateKey);
        final out = await _map(resp);
        if (out is RestoreGold && mismatchRetried && !withSeatKeys) {
          // R5-6: the retry without seatKeys worked, so the own key is the
          // problem. Stop sending it from this install.
          await _seats.markOwnKeyUnusable();
        }
        return out;
      } on BackendFailure catch (f) {
        if (f.kind == BackendFailureKind.problem) {
          switch (f.problem) {
            case ProblemCode.seatKeyMismatch
                when withSeatKeys && !mismatchRetried:
              withSeatKeys = false;
              mismatchRetried = true;
              continue;
            case ProblemCode.deviceAttestationFailed:
              if (attestRetried || sent.hadAttestationObject) {
                return const RestoreAttestationHelp();
              }
              attestRetried = true;
              forceNewKey = _platform == ClientPlatform.ios;
              continue;
            case ProblemCode.moveCooldown:
              final next = f.nextMoveAt;
              if (next != null) {
                await _state.write(
                  restoreNextMoveAtStateKey,
                  Uint8List.fromList(utf8.encode(next)),
                );
              }
              return RestoreMoveCooldown(
                nextMoveAt: next == null ? null : DateTime.tryParse(next),
              );
            default:
              break;
          }
        }
        return _failure(f);
      }
    }
  }

  // ---- request ----

  Map<String, Object?> _bodyWithoutAttestation(List<OwnedPurchase> items) {
    if (_platform == ClientPlatform.android) {
      return {
        'platform': 'android',
        'purchases': [
          for (final p in items)
            AndroidPurchaseRef(
              productId: p.productId,
              purchaseToken: p.reference,
            ).toJson(),
        ],
      };
    }
    return {
      'platform': 'ios',
      'signedTransactions': [for (final p in items) p.reference],
    };
  }

  Future<_Sent> _buildRequest(
    List<OwnedPurchase> items,
    Uint8List bodyHash, {
    required bool withSeatKeys,
    required bool forceNewKey,
  }) async {
    if (_platform == ClientPlatform.android) {
      final proof = await _withTransientRetry(
        () => _attestation.attest(bodyHash),
      );
      final req = PurchaseRestoreAndroidRequest(
        purchases: [
          for (final p in items)
            AndroidPurchaseRef(
              productId: p.productId,
              purchaseToken: p.reference,
            ),
        ],
        attestation: PlayIntegrityProof(token: proof.token!),
      );
      req.toJson(); // validates before anything is sent
      return _Sent(req, hadAttestationObject: false);
    }
    // iOS: seat signatures over bodyHash first (R4-1(3)), then the digest of
    // their public keys goes into clientDataHash, then App Attest.
    final sigs = withSeatKeys
        ? await _seats.prove(SeatOp.restore, bodyHash)
        : const <SeatSignature>[];
    final clientDataHash = restoreClientDataHash(bodyHash, [
      for (final s in sigs) s.publicKey,
    ]);
    final proof = await _withTransientRetry(
      () => _attestation.attest(clientDataHash, forceNewKey: forceNewKey),
    );
    final req = PurchaseRestoreIosRequest(
      signedTransactions: [for (final p in items) p.reference],
      attestation: AppAttestProof(
        keyId: proof.keyId!,
        assertion: proof.assertion!,
        attestationObject: proof.attestationObject,
        seatKeys: sigs.isEmpty
            ? null
            : [
                for (final s in sigs)
                  SeatKeyProof(
                    publicKey: _b64u(s.publicKey),
                    signature: _b64u(s.signature),
                  ),
              ],
      ),
    );
    req.toJson();
    return _Sent(req, hadAttestationObject: proof.attestationObject != null);
  }

  Future<T> _withTransientRetry<T>(Future<T> Function() call) async {
    var i = 0;
    while (true) {
      try {
        return await call();
      } on AttestationException catch (e) {
        if (e.failure != AttestationFailure.transient ||
            i >= attestRetryDelays.length) {
          rethrow;
        }
        await _delay(attestRetryDelays[i++]);
      }
    }
  }

  // ---- results ----

  Future<RestoreOutcome> _map(PurchaseRestoreResponse r) async {
    switch (r.status) {
      case PurchaseStatus.active:
        final phase = await _entitlement.evaluate();
        final gold =
            phase == EntitlementPhase.active || phase == EntitlementPhase.grace;
        if (gold && r.entitlement != null) {
          return RestoreGold(
            movedFromOtherPhone: r.movedFromOtherPhone == true,
          );
        }
        return const RestoreTryLater(); // fail closed: nothing verified
      case PurchaseStatus.pending:
        return const RestorePending();
      case PurchaseStatus.accountRequired:
        return const RestoreAccountRequired();
      case PurchaseStatus.expired ||
          PurchaseStatus.refunded ||
          PurchaseStatus.invalid:
        return const RestoreNotGold();
      case PurchaseStatus.unknown:
        return const RestoreTryLater();
    }
  }

  RestoreOutcome _attestationFailure(AttestationException e) =>
      switch (e.failure) {
        AttestationFailure.transient => const RestoreTryLater(),
        AttestationFailure.playServicesOutdated => const RestoreTryLater(
          playServicesOutdated: true,
        ),
        AttestationFailure.unavailable => const RestoreAttestationHelp(),
      };

  RestoreOutcome _failure(BackendFailure f) {
    if (f.retryable) return _tryLater(f);
    return const RestoreFailed();
  }

  RestoreOutcome _tryLater(BackendFailure f) =>
      RestoreTryLater(retryAfter: f.retryAfter);

  @override
  String toString() => 'RestoreService';
}

final class _Sent {
  _Sent(this.request, {required this.hadAttestationObject});
  final PurchaseRestoreRequest request;
  final bool hadAttestationObject;
}

// ---- D-55 / EC-69: the "Delete everything" warning -------------------------

/// What the Delete-everything confirmation needs (T-166): whether this
/// install holds a seat, and when the seat could move again.
final class DeleteEverythingWarning {
  const DeleteEverythingWarning({required this.holdsSeat, this.nextMoveAt});
  final bool holdsSeat;
  final DateTime? nextMoveAt;
}

/// From the cached, verified entitlement token: this install holds a seat
/// when the token is for this install and covers a purchase (a plan, and
/// `active` or `grace`).
Future<DeleteEverythingWarning> deleteEverythingWarning({
  required EntitlementService entitlement,
  required Future<String?> Function() installId,
}) async {
  final claims = await entitlement.cachedClaims();
  final id = await installId();
  if (claims == null || id == null || claims.sub != id) {
    return const DeleteEverythingWarning(holdsSeat: false);
  }
  final holds =
      claims.plan != 'none' &&
      (claims.status == 'active' || claims.status == 'grace');
  return DeleteEverythingWarning(
    holdsSeat: holds,
    nextMoveAt: holds ? claims.nextMoveAt : null,
  );
}
