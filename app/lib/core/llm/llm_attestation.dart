// T-340: body binding and device proof for the LLM gateway (ask-llm §5,
// FR-LLM-14; vectors ask-binding-v1.json / cat-binding-v1.json, T-322).
//
//   bodyHash       = SHA-256(prefix 00 installId 00 JCS(body without
//                    "attestation"))
//   Android        = Play Integrity standard request over bodyHash (the
//                    native side sends requestHash = b64u(bodyHash))
//   iOS            = App Attest assertion over
//                    clientDataHash = SHA-256(clientDataPrefix 00 bodyHash)
//   debug builds   = {"type":"dev","proof": b64u(HMAC-SHA256(key, bodyHash))}
//                    with the key from --dart-define; never in release.
//
// The platform proof goes through the existing attestation channel
// (platform-channels §4a, T-178/T-341); this file never builds a token. No
// hash, proof or key is logged or put in an error.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

import '../../features/gold/domain/binding/binding_exceptions.dart';
import '../../features/gold/domain/binding/jcs.dart';
import '../../features/gold/domain/binding/strict_json.dart';
import '../backend/backend_client.dart'
    show
        ClientPlatform,
        LlmAppAttestProof,
        LlmAttestation,
        LlmDevProof,
        LlmPlayIntegrityProof;
import '../platform/pigeon_attestation.dart';
import 'llm_feature.dart';

export '../../features/gold/domain/binding/binding_exceptions.dart'
    show BindingException, BindingFailure;

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

const List<int> _nul = [0];

Uint8List _sha256(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return Uint8List.fromList(c.sha256.convert(b.toBytes()).bytes);
}

/// JCS text of [body] without its top-level `attestation` member.
String llmCanonicalBody(Map<String, Object?> body) =>
    jcsCanonicalize(Map<String, Object?>.of(body)..remove('attestation'));

/// `bodyHash` of the JSON text [rawBody] (with or without `attestation`).
/// Strict-parses it first (duplicates and lone surrogates refused). Throws
/// [BindingException] for a bad install ID or body.
Uint8List llmBodyHash(LlmFeature feature, String installId, String rawBody) {
  if (!_uuid.hasMatch(installId)) {
    throw const BindingException(BindingFailure.invalidInstallId);
  }
  final v = parseStrictJson(rawBody);
  if (v is! Map<String, Object?>) {
    throw const BindingException(BindingFailure.malformedJson);
  }
  return _sha256([
    utf8.encode(feature.bindingPrefix),
    _nul,
    utf8.encode(installId),
    _nul,
    utf8.encode(llmCanonicalBody(v)),
  ]);
}

/// App Attest `clientDataHash` over [bodyHash].
Uint8List llmClientDataHash(LlmFeature feature, Uint8List bodyHash) {
  if (bodyHash.length != 32) {
    throw const BindingException(BindingFailure.invalidInput);
  }
  return _sha256([utf8.encode(feature.clientDataPrefix), _nul, bodyHash]);
}

/// Unpadded base64url (Play Integrity `requestHash`, the dev proof).
String b64uNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A device proof for one body hash.
abstract interface class LlmProver {
  /// The proof for [bodyHash] (32 bytes). [forceNewKey] asks iOS for a new
  /// App Attest key (the server didn't accept the stored one). Throws
  /// [AttestationException] when no proof can be made.
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  });
}

/// Play Integrity / App Attest through the platform channel.
final class PlatformLlmProver implements LlmProver {
  PlatformLlmProver(this._attestation, this._platform);

  final PigeonAttestation _attestation;
  final ClientPlatform _platform;
  bool _prepared = false;

  @override
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  }) async {
    if (bodyHash.length != 32) {
      throw const BindingException(BindingFailure.invalidInput);
    }
    switch (_platform) {
      case ClientPlatform.android:
        // Warm the cached standard-request provider once (as restore does);
        // a failed prepare is retried on the next call.
        if (!_prepared) {
          await _attestation.prepare();
          _prepared = true;
        }
        final p = await _attestation.attest(bodyHash);
        final token = p.token;
        if (p.type != DeviceAttestationProof.playIntegrity || token == null) {
          throw const AttestationException(AttestationFailure.unavailable);
        }
        return LlmPlayIntegrityProof(token: token);
      case ClientPlatform.ios:
        final p = await _attestation.attest(
          llmClientDataHash(feature, bodyHash),
          forceNewKey: forceNewKey,
        );
        final keyId = p.keyId;
        final assertion = p.assertion;
        if (p.type != DeviceAttestationProof.appAttest ||
            keyId == null ||
            assertion == null) {
          throw const AttestationException(AttestationFailure.unavailable);
        }
        return LlmAppAttestProof(
          keyId: keyId,
          assertion: assertion,
          attestationObject: p.attestationObject,
        );
    }
  }

  @override
  String toString() => 'PlatformLlmProver(${_platform.name})';
}

/// The build a piece of code runs in. A seam so tests can show the release
/// behaviour of the dev proof.
enum BuildMode {
  debug,
  profile,
  release;

  static const BuildMode current = kReleaseMode
      ? release
      : (kDebugMode ? debug : profile);
}

/// The dev HMAC key from `--dart-define=ZAGHLOL_LLM_DEV_KEY=…`. A constant:
/// in a release build it is the empty string whatever was defined, so no key
/// is compiled into a release app.
const String llmDevKeyDefine = kReleaseMode
    ? ''
    : String.fromEnvironment('ZAGHLOL_LLM_DEV_KEY');

/// The dev proof for the backend's `Fake` attestation mode (Development and
/// Testing only). Exists only in debug builds.
final class DevLlmProver implements LlmProver {
  /// Throws [StateError] outside a debug build or without a key.
  DevLlmProver(String key, {BuildMode mode = BuildMode.current})
    : _mode = mode,
      _key = Uint8List.fromList(utf8.encode(key)) {
    _guard(mode);
    if (key.isEmpty) throw StateError('dev proof needs a key');
  }

  final BuildMode _mode;
  final Uint8List _key;

  static void _guard(BuildMode mode) {
    if (kReleaseMode || mode != BuildMode.debug) {
      throw StateError('dev proof is debug-only');
    }
  }

  @override
  Future<LlmAttestation> prove(
    LlmFeature feature,
    Uint8List bodyHash, {
    bool forceNewKey = false,
  }) async {
    _guard(_mode);
    if (bodyHash.length != 32) {
      throw const BindingException(BindingFailure.invalidInput);
    }
    return LlmDevProof(
      proof: b64uNoPad(c.Hmac(c.sha256, _key).convert(bodyHash).bytes),
    );
  }

  @override
  String toString() => 'DevLlmProver';
}

/// The prover for this build: the dev prover only in a debug build with a
/// dev key defined; the platform prover otherwise.
LlmProver selectLlmProver({
  required PigeonAttestation attestation,
  required ClientPlatform platform,
  BuildMode mode = BuildMode.current,
  String devKey = llmDevKeyDefine,
}) {
  if (mode == BuildMode.debug && !kReleaseMode && devKey.isNotEmpty) {
    return DevLlmProver(devKey, mode: mode);
  }
  return PlatformLlmProver(attestation, platform);
}
