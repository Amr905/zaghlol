// T-145: StoreBindingRef(installId) (backend-api §4.3, T-130 design note §5).
// The app sets it as Play `obfuscatedAccountId` and Apple `appAccountToken`
// at purchase; verify compares it with the install the install token
// authenticates. The HMAC key is a public domain separator, not a secret.
// Pure Dart; the shared vectors are in
// backend/tests/Zaghlol.Contract.Tests/vectors/store-binding-v1.json.

import 'dart:convert';

import 'package:crypto/crypto.dart' as c;

const String _storeBindingKey = 'zaghlol-store-binding-v1';

final RegExp _installIdShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// First 16 bytes of HMAC-SHA256([_storeBindingKey], [installId]) with the
/// RFC 9562 version-8 and variant bits set, as a lower-case hyphenated UUID.
/// Throws [ArgumentError] (without echoing the input) for anything but a
/// lower-case 36-character UUID text.
String storeBindingRef(String installId) {
  if (!_installIdShape.hasMatch(installId)) {
    throw ArgumentError('install ID must be a lower-case UUID');
  }
  final mac = c.Hmac(
    c.sha256,
    utf8.encode(_storeBindingKey),
  ).convert(utf8.encode(installId)).bytes;
  final b = List<int>.of(mac.sublist(0, 16));
  b[6] = (b[6] & 0x0f) | 0x80;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
