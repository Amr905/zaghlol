// T-143: adapters from the sync's ports to BackendClient (T-141) and
// EntitlementService (T-144), plus a state store that waits for the database.

import 'dart:typed_data';

import '../../../core/backend/backend_client.dart';
import '../../../core/backend/backend_state.dart';
import '../../gold/application/entitlement.dart';
import 'sync_orchestrator.dart';

final class BackendClientSyncBackend implements SyncBackend {
  BackendClientSyncBackend(this._client);
  final BackendClient _client;

  @override
  Future<SyncResponse> sync(SyncRequest request, TimeNonce nonce) =>
      _client.sync(request, timeNonce: nonce);

  @override
  Future<CatalogSnapshot> getFullCatalog(int version) =>
      _client.getFullCatalog(version);
}

/// Sync is an anchoring request (R4-2): it runs through T-144's anchor and the
/// signed body is applied there first.
final class EntitlementSyncAnchor implements SyncAnchor {
  EntitlementSyncAnchor(this._service);
  final EntitlementService _service;

  @override
  Future<SyncResponse> run(Future<SyncResponse> Function(TimeNonce) request) =>
      _service.anchored(request, SignedBody.fromSync);

  @override
  Future<int?> issuedAtMs() async => (await _service.cachedClaims())?.iatMs;
}

/// A [BackendStateStore] that opens the real one on first use, so providers
/// that need a store can stay synchronous while the database is opening.
final class DeferredBackendStateStore implements BackendStateStore {
  DeferredBackendStateStore(this._open);
  final Future<BackendStateStore> Function() _open;

  @override
  Future<Uint8List?> read(String key) async => (await _open()).read(key);

  @override
  Future<void> write(String key, Uint8List value) async =>
      (await _open()).write(key, value);

  @override
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
  }) async =>
      (await _open()).compareAndSet(key, expected: expected, next: next);

  @override
  Future<void> delete(String key) async => (await _open()).delete(key);

  @override
  Future<bool> deleteIfEquals(String key, Uint8List expected) async =>
      (await _open()).deleteIfEquals(key, expected);
}
