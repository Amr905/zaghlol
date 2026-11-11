// T-015: SecretStore over the Pigeon channel (platform-channels §5/§6). Maps
// native results to the pure-Dart types and drops every native message: only
// the error code crosses into Dart code.

import 'package:flutter/services.dart';

import '../crypto/secret_store.dart';
import 'secret_store_api.g.dart';

/// Native error codes (platform-channels §6).
const String keyStoreFailedCode = 'KEY_STORE_FAILED';
const String leaseTimeoutCode = 'LEASE_TIMEOUT';

final class PigeonSecretStore implements SecretStore {
  PigeonSecretStore({SecretStoreHostApi? api})
    : _api = api ?? SecretStoreHostApi();

  final SecretStoreHostApi _api;

  @override
  Future<SecretStoreLease> acquireBootstrapLease(Duration timeout) async {
    final id = await _guard(
      () => _api.acquireBootstrapLease(timeout.inMilliseconds),
    );
    return SecretStoreLease(id);
  }

  @override
  Future<void> releaseBootstrapLease(SecretStoreLease lease) async {
    try {
      await _api.releaseBootstrapLease(lease.id);
    } on Object {
      // Releasing is best effort: the native lease expires after 30 s anyway.
    }
  }

  @override
  Future<bool> renewBootstrapLease(SecretStoreLease lease) async {
    try {
      return await _api.renewBootstrapLease(lease.id);
    } on Object {
      // Can't confirm the lease: treat it as lapsed (the caller stops).
      return false;
    }
  }

  @override
  Future<SecretRead> read(SecretSlot slot) async {
    final SecretReadMsg msg;
    try {
      msg = await _api.read(_slot(slot));
    } on Object {
      return SecretRead(SecretStatus.unavailable, attempts: 0);
    }
    final value = msg.value;
    switch (msg.status) {
      case SecretStatusMsg.found:
        if (value == null) {
          return SecretRead(SecretStatus.unavailable, attempts: msg.attempts);
        }
        // The codec may hand out an unmodifiable view; copy it so the caller
        // can zero its buffer.
        return SecretRead(
          SecretStatus.found,
          value: Uint8List.fromList(value),
          attempts: msg.attempts,
        );
      case SecretStatusMsg.notFound:
        return SecretRead(SecretStatus.notFound, attempts: msg.attempts);
      case SecretStatusMsg.unusable:
        return SecretRead(SecretStatus.unusable, attempts: msg.attempts);
      case SecretStatusMsg.unavailable:
        return SecretRead(SecretStatus.unavailable, attempts: msg.attempts);
    }
  }

  @override
  Future<Uint8List> createIfAbsent(
    SecretStoreLease lease,
    SecretSlot slot,
    Uint8List candidate,
  ) async {
    final stored = await _guard(
      () => _api.createIfAbsent(lease.id, _slot(slot), candidate),
    );
    return Uint8List.fromList(stored);
  }

  @override
  Future<void> delete(SecretStoreLease lease, SecretSlot slot) =>
      _guard(() => _api.delete(lease.id, _slot(slot)));

  static SecretSlotMsg _slot(SecretSlot slot) => switch (slot) {
    SecretSlot.dbKey => SecretSlotMsg.dbKey,
    SecretSlot.backupKey => SecretSlotMsg.backupKey,
  };

  /// Runs [call] and replaces any failure with a code-only
  /// [SecretStoreException]. The PlatformException (message, details) is
  /// dropped here.
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw SecretStoreException(errorCodeFor(e.code));
    } on Object {
      throw const SecretStoreException(SecretStoreErrorCode.unavailable);
    }
  }

  /// Maps a native error code to [SecretStoreErrorCode].
  static SecretStoreErrorCode errorCodeFor(String code) => switch (code) {
    leaseTimeoutCode => SecretStoreErrorCode.leaseTimeout,
    keyStoreFailedCode => SecretStoreErrorCode.storeFailed,
    _ => SecretStoreErrorCode.unavailable,
  };
}
