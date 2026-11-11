// T-015: an in-memory SecretStore with the native semantics (one process-wide
// lease with a timeout, createIfAbsent winner semantics, writes need the
// current lease). Records every call so tests can prove "nothing written".

import 'dart:async';
import 'dart:typed_data';

import 'package:zaghlol/core/crypto/secret_store.dart';

final class FakeSecretStore implements SecretStore {
  /// The stored secret (null: nothing stored).
  Uint8List? stored;

  /// When set, reads report this status (the stored value is kept), like a
  /// Keystore alias that disappeared (unusable) or a locked phone
  /// (unavailable). Cleared by [delete].
  SecretStatus? forcedStatus;

  /// Attempts reported by reads.
  int readAttempts = 1;

  /// Failures to inject.
  SecretStoreErrorCode? failAcquire;
  SecretStoreErrorCode? failCreate;
  SecretStoreErrorCode? failDelete;

  /// Called right before createIfAbsent decides (to simulate a racing writer).
  void Function()? beforeCreate;

  /// T-016: how many more renewals succeed before the held lease lapses
  /// (null: never lapses). At 0 the next renewal expires the lease (it is no
  /// longer held) and returns false, like the native 30 s expiry.
  int? renewalsBeforeLapse;

  /// When true, renewals throw (a broken channel).
  bool failRenew = false;

  final List<String> calls = [];

  /// T-148: every slot a call touched (this fake models dbKey only).
  final List<SecretSlot> slotsTouched = [];

  /// Every buffer handed out by [read] (to check the caller zeroes them).
  final List<Uint8List> handedOut = [];

  int? _held;
  int _nextLease = 1;
  final List<Completer<void>> _waiters = [];

  int get createCalls => calls.where((c) => c == 'create').length;
  int get renewCalls => calls.where((c) => c == 'renew').length;
  int get deleteCalls => calls.where((c) => c == 'delete').length;
  int get writeCalls => createCalls + deleteCalls;
  bool get leaseHeld => _held != null;

  /// Takes the lease outside any bootstrap (to simulate another engine).
  SecretStoreLease holdLease() {
    if (_held != null) throw StateError('lease already held');
    _held = _nextLease++;
    return SecretStoreLease(_held!);
  }

  @override
  Future<SecretStoreLease> acquireBootstrapLease(Duration timeout) async {
    calls.add('acquire');
    final fail = failAcquire;
    if (fail != null) throw SecretStoreException(fail);
    final deadline = DateTime.now().add(timeout);
    while (_held != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
      }
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await waiter.future.timeout(remaining);
      } on TimeoutException {
        _waiters.remove(waiter);
        throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
      }
    }
    _held = _nextLease++;
    return SecretStoreLease(_held!);
  }

  @override
  Future<void> releaseBootstrapLease(SecretStoreLease lease) async {
    calls.add('release');
    if (_held != lease.id) return;
    _held = null;
    if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
  }

  @override
  Future<bool> renewBootstrapLease(SecretStoreLease lease) async {
    calls.add('renew');
    if (failRenew) {
      throw const SecretStoreException(SecretStoreErrorCode.unavailable);
    }
    if (_held != lease.id) return false;
    final left = renewalsBeforeLapse;
    if (left != null) {
      if (left <= 0) {
        _held = null;
        if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
        return false;
      }
      renewalsBeforeLapse = left - 1;
    }
    return true;
  }

  @override
  Future<SecretRead> read(SecretSlot slot) async {
    calls.add('read');
    slotsTouched.add(slot);
    final forced = forcedStatus;
    final value = stored;
    if (forced != null && forced != SecretStatus.found) {
      return SecretRead(forced, attempts: readAttempts);
    }
    if (value == null) {
      return SecretRead(SecretStatus.notFound, attempts: readAttempts);
    }
    final copy = Uint8List.fromList(value);
    handedOut.add(copy);
    return SecretRead(SecretStatus.found, value: copy, attempts: readAttempts);
  }

  @override
  Future<Uint8List> createIfAbsent(
    SecretStoreLease lease,
    SecretSlot slot,
    Uint8List candidate,
  ) async {
    calls.add('create');
    slotsTouched.add(slot);
    _requireLease(lease);
    beforeCreate?.call();
    final fail = failCreate;
    if (fail != null) throw SecretStoreException(fail);
    final existing = stored;
    if (existing != null) {
      if (forcedStatus != null) {
        // Native refuses to overwrite an unusable or unknown secret.
        throw const SecretStoreException(SecretStoreErrorCode.storeFailed);
      }
      return Uint8List.fromList(existing);
    }
    stored = Uint8List.fromList(candidate);
    return Uint8List.fromList(candidate);
  }

  @override
  Future<void> delete(SecretStoreLease lease, SecretSlot slot) async {
    calls.add('delete');
    slotsTouched.add(slot);
    _requireLease(lease);
    final fail = failDelete;
    if (fail != null) throw SecretStoreException(fail);
    stored = null;
    forcedStatus = null;
  }

  void _requireLease(SecretStoreLease lease) {
    if (_held != lease.id) {
      throw const SecretStoreException(SecretStoreErrorCode.leaseTimeout);
    }
  }
}
