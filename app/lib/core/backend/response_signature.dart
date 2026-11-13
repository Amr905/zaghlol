// T-141: verification of `Zaghlol-Signature` (backend-api §1, T-123 design
// note "What the signature covers").
//
// Exactly the backend's form: `kid=<kid>; alg=ES256; sig=<86 base64url>`, in
// that order with "; " separators, nothing trimmed. ECDSA P-256 / SHA-256 over
// the exact response body bytes after decompression; `sig` is IEEE P1363
// `r || s` (64 bytes); high-S is accepted. Only `s` kids sign response headers
// (`e` kids sign JWS tokens and are refused here). Only keys in the pinned set
// verify. Every failure is the same code-only [ResponseSignatureException];
// nothing about the input is kept or echoed.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

final ECDomainParameters _p256 = ECDomainParameters('prime256v1');

final RegExp _keyKid = RegExp(r'^[se][0-9]{4}[a-z]$');
final RegExp _devKid = RegExp(r'^[se]0000[a-z]$');
final RegExp _header = RegExp(
  r'^kid=([se][0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{85}[AQgw])$',
);
final RegExp _b64url = RegExp(r'^[A-Za-z0-9_-]+$');

/// A response signature did not verify. Code only.
final class ResponseSignatureException extends SafeException {
  ResponseSignatureException() : super('BACKEND_BAD_SIGNATURE');
}

/// A pinned public key (an EC P-256 JWK's `kid`, `x`, `y`).
final class ResponseKey {
  /// Throws [ArgumentError] for a malformed kid or a point not on P-256.
  ResponseKey({required this.kid, required Uint8List x, required Uint8List y})
    : _x = Uint8List.fromList(x),
      _y = Uint8List.fromList(y) {
    if (!_keyKid.hasMatch(kid) || x.length != 32 || y.length != 32) {
      throw ArgumentError('bad key');
    }
    final c = _p256.curve;
    final px = c.fromBigInteger(_toBig(x));
    final py = c.fromBigInteger(_toBig(y));
    if (py * py != px * px * px + c.a! * px + c.b!) {
      throw ArgumentError('bad key');
    }
    _public = ECPublicKey(c.createPoint(_toBig(x), _toBig(y)), _p256);
  }

  /// From base64url JWK members.
  factory ResponseKey.fromJwk({
    required String kid,
    required String x,
    required String y,
  }) => ResponseKey(kid: kid, x: _unb64(x), y: _unb64(y));

  final String kid;
  final Uint8List _x;
  final Uint8List _y;
  late final ECPublicKey _public;

  @override
  String toString() => 'ResponseKey($kid)';

  @override
  bool operator ==(Object other) =>
      other is ResponseKey &&
      other.kid == kid &&
      _eq(other._x, _x) &&
      _eq(other._y, _y);

  @override
  int get hashCode => kid.hashCode;
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

BigInt _toBig(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _unb64(String s) {
  if (!_b64url.hasMatch(s)) throw ArgumentError('bad base64url');
  return Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));
}

/// Verifies response signatures against a pinned key set (current + next).
final class ResponseSignatureVerifier {
  /// [keys] are the pinned public keys. Dev kids (`s0000x`, year 0000, whose
  /// private halves are test material) verify only with [allowDevKeys]; the
  /// app passes `!kReleaseMode`, so a release build refuses them.
  ResponseSignatureVerifier(
    Iterable<ResponseKey> keys, {
    this.allowDevKeys = false,
  }) : _keys = {for (final k in keys) k.kid: k} {
    if (_keys.length != keys.length) throw ArgumentError('duplicate kid');
  }

  final Map<String, ResponseKey> _keys;
  final bool allowDevKeys;

  /// Returns the kid that signed [body]. Throws [ResponseSignatureException]
  /// for a missing, malformed, unknown-key, wrong-purpose or invalid
  /// signature; the caller must then drop the body.
  String verify(Uint8List body, String? header) {
    if (header == null || header.length > 128) {
      throw ResponseSignatureException();
    }
    final m = _header.firstMatch(header);
    if (m == null) throw ResponseSignatureException();
    final kid = m.group(1)!;
    // Response headers are signed only by `s` (sync) keys; an `e`
    // (entitlement) key is refused even when pinned (T-123).
    if (!kid.startsWith('s')) throw ResponseSignatureException();
    if (!allowDevKeys && _devKid.hasMatch(kid)) {
      throw ResponseSignatureException();
    }
    final key = _keys[kid];
    if (key == null) throw ResponseSignatureException();
    final raw = base64Url.decode('${m.group(2)!}==');
    if (!_verifyP1363(key, body, raw)) throw ResponseSignatureException();
    return kid;
  }

  /// Verifies a detached ES256 signature (IEEE P1363 `r || s`, 64 bytes) of
  /// [message] by the pinned key [kid], which must carry [kidPrefix] (`e` for
  /// JWS tokens, T-144). The same primitive as [verify]; false for any
  /// failure (unknown kid, wrong purpose, dev key in release, bad signature).
  bool verifyDetached({
    required String kid,
    required String kidPrefix,
    required Uint8List message,
    required Uint8List signature,
  }) {
    if (!_keyKid.hasMatch(kid) || !kid.startsWith(kidPrefix)) return false;
    if (!allowDevKeys && _devKid.hasMatch(kid)) return false;
    final key = _keys[kid];
    if (key == null) return false;
    return _verifyP1363(key, message, signature);
  }
}

bool _verifyP1363(ResponseKey key, Uint8List message, List<int> raw) {
  if (raw.length != 64) return false;
  final r = _toBig(raw.sublist(0, 32));
  final s = _toBig(raw.sublist(32));
  final n = _p256.n;
  if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;
  try {
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(key._public));
    return verifier.verifySignature(message, ECSignature(r, s));
  } on Object {
    return false;
  }
}
