// T-030: ES256 signature of the seed, in the backend's header form
// (`Zaghlol-Signature: kid=<kid>; alg=ES256; sig=<base64url>`, backend-api
// §1): ECDSA P-256 over SHA-256 of the exact (decompressed) JSON bytes, the
// signature as raw r || s (64 bytes, 86 base64url characters, no padding).
// The same bytes and header form the backend writes as `full.json` and
// `full.json.sig`.
//
// Verification fails closed: any parse problem, unknown kid, wrong length or
// failed check is one `SEED_BAD_SIGNATURE`, and nothing about the input is
// echoed. Signing is deterministic (RFC 6979), so a rebuild of an unchanged
// seed is byte-identical.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'catalog_seed.dart';

final ECDomainParameters _p256 = ECDomainParameters('prime256v1');

final RegExp _kid = RegExp(r'^[a-z0-9]{1,16}$');
final RegExp _b64url = RegExp(r'^[A-Za-z0-9_-]+$');

/// A public key the app trusts for seed signatures (an EC JWK's `x` and `y`).
final class SeedTrustedKey {
  /// [x] and [y] are the 32-byte big-endian affine coordinates. Throws
  /// [ArgumentError] when the point is not on P-256.
  SeedTrustedKey({required this.kid, required this.x, required this.y}) {
    if (!_kid.hasMatch(kid) || x.length != 32 || y.length != 32) {
      throw ArgumentError('bad key');
    }
    final c = _p256.curve;
    final px = c.fromBigInteger(_toBig(x));
    final py = c.fromBigInteger(_toBig(y));
    // y^2 = x^3 + ax + b on P-256: a key off the curve is refused.
    if (py * py != px * px * px + c.a! * px + c.b!) {
      throw ArgumentError('bad key');
    }
  }

  /// From base64url JWK members.
  factory SeedTrustedKey.fromJwk({
    required String kid,
    required String x,
    required String y,
  }) => SeedTrustedKey(kid: kid, x: _unb64(x), y: _unb64(y));

  final String kid;
  final Uint8List x;
  final Uint8List y;

  ECPublicKey get _public =>
      ECPublicKey(_p256.curve.createPoint(_toBig(x), _toBig(y)), _p256);
}

BigInt _toBig(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _fromBig(BigInt v, int length) {
  final out = Uint8List(length);
  var rest = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  return out;
}

Uint8List _unb64(String s) {
  if (!_b64url.hasMatch(s)) throw ArgumentError('bad base64url');
  return Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));
}

String _b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Signs seed bytes. Build-time only (tools/catalog_build): the app never
/// holds a private key.
final class SeedSigner {
  /// [d] is the 32-byte big-endian private scalar.
  SeedSigner({required this.kid, required Uint8List d}) : _d = _toBig(d) {
    if (!_kid.hasMatch(kid) || d.length != 32) throw ArgumentError('bad key');
  }

  final String kid;
  final BigInt _d;

  /// The `Zaghlol-Signature` header value for [message].
  String sign(Uint8List message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter(ECPrivateKey(_d, _p256)));
    final sig = signer.generateSignature(message) as ECSignature;
    final raw = Uint8List(64)
      ..setRange(0, 32, _fromBig(sig.r, 32))
      ..setRange(32, 64, _fromBig(sig.s, 32));
    return 'kid=$kid; alg=ES256; sig=${_b64(raw)}';
  }
}

/// True for a dev kid (`s0000x` / `e0000x`, backend-api §1: year 0000).
bool isDevKid(String kid) => RegExp(r'^[se]0000[a-z]$').hasMatch(kid);

/// Verifies [header] over [message] against [trusted]. Returns the kid that
/// signed. Throws [CatalogSeedException] (`SEED_BAD_SIGNATURE`) on anything
/// else: the caller must then discard the bytes.
///
/// Dev kids (`s0000x`, whose private half is public) are refused unless
/// [allowDevKeys] is true; release builds must leave it false.
String verifySeedSignature(
  Uint8List message,
  String header,
  Iterable<SeedTrustedKey> trusted, {
  bool allowDevKeys = false,
}) {
  CatalogSeedException bad() =>
      CatalogSeedException(CatalogSeedException.badSignature);
  if (header.length > 256) throw bad();
  final match = RegExp(
    r'^kid=([a-z0-9]{1,16}); alg=ES256; sig=([A-Za-z0-9_-]{86})$',
  ).firstMatch(header.trim());
  if (match == null) throw bad();
  final kid = match.group(1)!;
  // Only Sync keys (`s...`) sign catalogs; an entitlement key (`e...`) never
  // does, even when it is in the trusted set (backend-api §1).
  if (!kid.startsWith('s')) throw bad();
  if (!allowDevKeys && isDevKid(kid)) throw bad();
  final raw = _unb64(match.group(2)!);
  if (raw.length != 64) throw bad();
  SeedTrustedKey? key;
  for (final k in trusted) {
    if (k.kid == kid) key = k;
  }
  if (key == null) throw bad();
  final bool ok;
  try {
    final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(false, PublicKeyParameter(key._public));
    ok = verifier.verifySignature(
      message,
      ECSignature(_toBig(raw.sublist(0, 32)), _toBig(raw.sublist(32))),
    );
  } on Object {
    throw bad();
  }
  if (!ok) throw bad();
  return kid;
}
