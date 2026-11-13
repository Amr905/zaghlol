// T-141: identifiers the app sends to the backend (backend-api §1, §4.1).
//
// - Install ID: UUID v4 from a CSPRNG (shown to the user as the support code,
//   so not a secret, but never guessable).
// - Idempotency-Key: a ULID whose 80 random bits come from `Random.secure()`
//   (R3-6). Never logged: [IdempotencyKey.toString] prints nothing of it.
// - Time nonce: only *wrapped* here. The value comes from T-144's time-anchor
//   service; this library has no way to make one (R4-2).

import 'dart:math';

final RegExp _ulidShape = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');
final RegExp _nonceShape = RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]$');
final RegExp _uuidV4Shape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// A new install ID: UUID v4 (RFC 9562) from [rng], lower-case hex.
String newInstallId(Random rng) {
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// True for a lower-case UUID v4 string.
bool isInstallId(String s) => _uuidV4Shape.hasMatch(s);

/// An `Idempotency-Key` (backend-api §1, R3-6). Its value is sent in one
/// header and stored only inside the encrypted `secure_state`; it is never
/// printed, logged or put in an error.
final class IdempotencyKey {
  IdempotencyKey._(this.value);

  /// A fresh ULID at [now]: 48 bits of milliseconds, then 80 bits from [rng]
  /// (the client passes `Random.secure()`).
  factory IdempotencyKey.generate(Random rng, DateTime now) {
    final ms = now.toUtc().millisecondsSinceEpoch;
    if (ms < 0 || ms >= (1 << 48)) {
      throw ArgumentError('time out of range');
    }
    var v = BigInt.from(ms);
    for (var i = 0; i < 10; i++) {
      v = (v << 8) | BigInt.from(rng.nextInt(256));
    }
    final out = List<String>.filled(26, '0');
    for (var i = 25; i >= 0; i--) {
      out[i] = _crockford[(v & BigInt.from(31)).toInt()];
      v = v >> 5;
    }
    return IdempotencyKey._(out.join());
  }

  /// Re-reads a stored key. Throws [FormatException] (no value echoed) when
  /// it is not a ULID.
  factory IdempotencyKey.restore(String value) {
    if (!_ulidShape.hasMatch(value) || value.codeUnitAt(0) > 0x37) {
      throw const FormatException('bad idempotency key');
    }
    return IdempotencyKey._(value);
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is IdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IdempotencyKey(…)';
}

/// The `Zaghlol-Time-Nonce` of one anchoring request (R4-2): 128 bits from
/// T-144's time-anchor service, base64url without padding. This class only
/// checks the shape; it never creates a value.
final class TimeNonce {
  /// Throws [FormatException] (no value echoed) for anything but 22
  /// canonical base64url characters.
  TimeNonce(this.value) {
    if (!_nonceShape.hasMatch(value)) {
      throw const FormatException('bad time nonce');
    }
  }

  final String value;

  @override
  String toString() => 'TimeNonce(…)';
}
