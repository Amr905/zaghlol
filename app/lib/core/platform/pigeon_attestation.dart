// T-178: device attestation over the Pigeon channel (platform-channels §4a).
// The caller (T-145 restore) passes the 32-byte hash computed by the binding
// library (lib/features/gold/domain/binding/request_binding.dart): Android
// gets bodyHash, iOS the restore clientDataHash. This wrapper never builds or
// alters the hash. Every failure becomes a code-only exception: no token, key
// ID, assertion or native message reaches Dart errors or logs. Nothing here
// logs.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attestation_api.g.dart';

/// Contract error codes (platform-channels §6).
enum AttestationFailure {
  /// `ATTEST_TRANSIENT`: network, rate limit or Google/Apple server; retry later.
  transient,

  /// `ATTEST_PLAY_SERVICES_OUTDATED`: Play services / Play Store too old.
  playServicesOutdated,

  /// `ATTEST_UNAVAILABLE` and anything else, including a malformed proof.
  unavailable,
}

/// A failed attestation. Code only.
final class AttestationException implements Exception {
  const AttestationException(this.failure);
  final AttestationFailure failure;

  @override
  String toString() => 'AttestationException(${failure.name})';
}

/// The proof for the restore body's `attestation` object. [toString] never
/// shows the token, key ID or assertion.
final class DeviceAttestationProof {
  const DeviceAttestationProof._({
    required this.type,
    this.token,
    this.keyId,
    this.assertion,
    this.attestationObject,
  });

  static const String playIntegrity = 'play_integrity';
  static const String appAttest = 'app_attest';

  /// [playIntegrity] or [appAttest].
  final String type;
  final String? token;
  final String? keyId;
  final String? assertion;

  /// Only for a newly generated App Attest key.
  final String? attestationObject;

  @override
  String toString() => 'DeviceAttestationProof($type)';
}

final class PigeonAttestation {
  PigeonAttestation({AttestationHostApi? api})
    : _api = api ?? AttestationHostApi();

  static const int hashLength = 32;

  final AttestationHostApi _api;

  /// Android: warms up the Play Integrity provider. iOS: no-op.
  Future<void> prepare() async {
    try {
      await _api.prepare();
    } on Object catch (e) {
      throw AttestationException(_failureOf(e));
    }
  }

  /// Attests exactly [hash32] (32 bytes). [forceNewKey] makes iOS replace its
  /// App Attest key (the server reported it unknown); Android ignores it.
  Future<DeviceAttestationProof> attest(
    Uint8List hash32, {
    bool forceNewKey = false,
  }) async {
    if (hash32.length != hashLength) {
      // Fixed text: never echoes the input.
      throw ArgumentError('attestation hash must be $hashLength bytes');
    }
    final AttestationProof raw;
    try {
      raw = await _api.attest(Uint8List.fromList(hash32), forceNewKey);
    } on Object catch (e) {
      throw AttestationException(_failureOf(e));
    }
    return _checked(raw);
  }

  static DeviceAttestationProof _checked(AttestationProof p) {
    bool present(String? s) => s != null && s.isNotEmpty;
    switch (p.type) {
      case DeviceAttestationProof.playIntegrity when present(p.token):
        return DeviceAttestationProof._(type: p.type, token: p.token);
      case DeviceAttestationProof.appAttest
          when present(p.keyId) && present(p.assertion):
        return DeviceAttestationProof._(
          type: p.type,
          keyId: p.keyId,
          assertion: p.assertion,
          attestationObject: present(p.attestationObject)
              ? p.attestationObject
              : null,
        );
      default:
        // Unknown type or missing fields: fail closed.
        throw const AttestationException(AttestationFailure.unavailable);
    }
  }

  static AttestationFailure _failureOf(Object e) {
    if (e is PlatformException) {
      switch (e.code) {
        case 'ATTEST_TRANSIENT':
          return AttestationFailure.transient;
        case 'ATTEST_PLAY_SERVICES_OUTDATED':
          return AttestationFailure.playServicesOutdated;
      }
    }
    return AttestationFailure.unavailable;
  }
}

/// Device attestation through the platform. Overridden with a fake in tests.
final attestationProvider = Provider<PigeonAttestation>(
  (ref) => PigeonAttestation(),
  name: 'attestationProvider',
);
