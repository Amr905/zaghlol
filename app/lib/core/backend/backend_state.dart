// T-141: where BackendClient keeps its tokens: the encrypted `secure_state`
// table (database-schema §2.8, security-model §3). Never preferences, files,
// logs or errors.

import 'dart:typed_data';

import '../db/daos/settings_dao.dart';

/// The `secure_state` keys of the backend client. T-144 (entitlement) and
/// T-147 (account) read and write their tokens under these keys; this client
/// deletes them on re-registration (R5-1).
abstract final class BackendStateKeys {
  /// The registered install ID (UUID v4; also the user's support code).
  static const String installId = 'install_id';

  /// The install token (32 random bytes, base64url).
  static const String installToken = 'install_token';

  /// A registration in flight: `{installId, key, body}`, so a retry after a
  /// lost response resends the same `Idempotency-Key` and body bytes (R3-6).
  static const String registration = 'install_registration';

  /// Set while an R5-1 re-registration has not finished; cleared after
  /// `InstallReregistered` was emitted.
  static const String reregistration = 'install_reregistration';

  /// The signed entitlement JWS (owner: T-144).
  static const String entitlementToken = 'entitlement_token';

  /// The account JWT (owner: T-147).
  static const String accountToken = 'account_token';
}

/// The store port. Values are opaque bytes; implementations never log.
abstract interface class BackendStateStore {
  Future<Uint8List?> read(String key);

  Future<void> write(String key, Uint8List value);

  /// Writes [next] only when the current value equals [expected] (null:
  /// only when unset). True when this call wrote.
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
  });

  Future<void> delete(String key);

  /// Deletes [key] only while its value equals [expected]. True when this
  /// call deleted.
  Future<bool> deleteIfEquals(String key, Uint8List expected);
}

/// The production store over [SecureStateDao].
final class SecureStateBackendStore implements BackendStateStore {
  SecureStateBackendStore(this._dao, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SecureStateDao _dao;
  final DateTime Function() _now;

  int get _at => _now().toUtc().millisecondsSinceEpoch;

  @override
  Future<Uint8List?> read(String key) => _dao.read(key);

  @override
  Future<void> write(String key, Uint8List value) =>
      _dao.write(key, value, at: _at);

  @override
  Future<bool> compareAndSet(
    String key, {
    required Uint8List? expected,
    required Uint8List next,
  }) => _dao.compareAndSet(key, expected: expected, next: next, at: _at);

  @override
  Future<void> delete(String key) => _dao.delete(key);

  @override
  Future<bool> deleteIfEquals(String key, Uint8List expected) =>
      _dao.deleteIfEquals(key, expected);
}
