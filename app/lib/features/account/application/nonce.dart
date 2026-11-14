// T-147 (R2-9, ADR-016 amendments 2 and 3): the raw sign-in nonce and what
// the provider gets. The raw value lives in memory for one attempt, goes to
// the backend once and is never logged or stored.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

const int _nonceBytes = 24; // 192 bits (>= 128), 32 base64url characters

/// A fresh raw nonce from [rng] (a CSPRNG in production), base64url without
/// padding; matches `^[A-Za-z0-9_-]{22,128}$`.
String newRawNonce(Random rng) {
  final b = Uint8List(_nonceBytes);
  for (var i = 0; i < b.length; i++) {
    b[i] = rng.nextInt(256);
  }
  return base64Url.encode(b).replaceAll('=', '');
}

/// What the provider receives: `hex(SHA-256(ASCII bytes of raw))`, lower case.
String providerNonce(String raw) =>
    c.sha256.convert(ascii.encode(raw)).toString();
