// T-145: ports the purchase and restore services need, so tests need no HTTP
// and no native host.

import 'dart:typed_data';

import '../../../core/backend/backend_client.dart';
import '../../../core/platform/seat_key_api.g.dart';
import '../domain/binding/request_binding.dart';
import 'seat_keys.dart';

abstract interface class GoldBackend {
  Future<String?> installId();
  Future<String> ensureInstalled();
  IdempotencyKey newKey();
  Future<PurchaseVerifyResponse> verify(
    PurchaseVerifyRequest request,
    IdempotencyKey key,
    TimeNonce nonce,
  );
  Future<PurchaseRestoreResponse> restore(
    PurchaseRestoreRequest request,
    TimeNonce nonce,
  );
}

final class BackendClientGoldBackend implements GoldBackend {
  BackendClientGoldBackend(this._client);
  final BackendClient _client;

  @override
  Future<String?> installId() => _client.installId();
  @override
  Future<String> ensureInstalled() => _client.ensureInstalled();
  @override
  IdempotencyKey newKey() => _client.newIdempotencyKey();

  @override
  Future<PurchaseVerifyResponse> verify(
    PurchaseVerifyRequest request,
    IdempotencyKey key,
    TimeNonce nonce,
  ) => _client.verifyPurchase(
    _client.prepareVerify(request, reuseKey: key),
    timeNonce: nonce,
  );

  @override
  Future<PurchaseRestoreResponse> restore(
    PurchaseRestoreRequest request,
    TimeNonce nonce,
  ) => _client.restorePurchases(request, timeNonce: nonce);
}

/// The seat-key operations of T-179 that purchase and restore use.
abstract interface class SeatProver {
  /// Seat proofs for [op] over [challenge], own key first; empty when none
  /// may be sent (Android, unavailable, R5-6 flag).
  Future<List<SeatSignature>> prove(SeatOp op, Uint8List challenge);

  /// R5-6: the own key proved unusable for this install.
  Future<void> markOwnKeyUnusable();
}

final class SeatKeyServiceProver implements SeatProver {
  SeatKeyServiceProver(this._service);
  final SeatKeyService _service;

  @override
  Future<List<SeatSignature>> prove(SeatOp op, Uint8List challenge) =>
      _service.prove(op, challenge);

  @override
  Future<void> markOwnKeyUnusable() => _service.markOwnKeyUnusable();
}

/// Wakes the app to retry the outbox at [at]. The in-process implementation
/// is a timer; see the T-145 task file for the native wake-up.
abstract interface class PurchaseRetryScheduler {
  void scheduleAt(DateTime at);
  void cancel();
}
