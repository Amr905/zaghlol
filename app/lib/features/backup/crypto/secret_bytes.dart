// T-148: key material holder (design note §3 "Zeroization"), like
// DbKeyMaterial: owns its buffer, redacted toString, identity equality only,
// zeroize() overwrites the bytes. Dart can't pin memory or wipe copies made by
// the VM or a platform channel; that limit is accepted (T-015 §5).

import 'dart:typed_data';

final class SecretBytes {
  SecretBytes._(this._bytes);

  /// Copies [bytes] into a new holder. The caller still owns [bytes].
  factory SecretBytes.copyOf(List<int> bytes) =>
      SecretBytes._(Uint8List.fromList(bytes));

  /// Takes ownership of [bytes] (no copy). The caller must not use or keep
  /// [bytes] afterwards.
  factory SecretBytes.adopt(Uint8List bytes) => SecretBytes._(bytes);

  final Uint8List _bytes;
  bool _zeroized = false;

  bool get isZeroized => _zeroized;

  int get length => _bytes.length;

  /// The live buffer. Use it at once and keep no reference: it is zeroed by
  /// [zeroize].
  Uint8List get bytes {
    if (_zeroized) throw StateError('BACKUP_KEY_ZEROIZED');
    return _bytes;
  }

  /// A new holder with a copy of the bytes.
  SecretBytes clone() => SecretBytes.copyOf(bytes);

  /// Constant-time comparison (length is not secret).
  bool sameAs(SecretBytes other) =>
      !_zeroized &&
      !other._zeroized &&
      constantTimeEquals(_bytes, other._bytes);

  void zeroize() {
    _bytes.fillRange(0, _bytes.length, 0);
    _zeroized = true;
  }

  @override
  String toString() => 'SecretBytes(<redacted>)';
}

/// Constant time in the content for equal lengths.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Overwrites [bytes] with zeros; unmodifiable views are skipped.
void wipe(Uint8List bytes) {
  try {
    bytes.fillRange(0, bytes.length, 0);
  } on UnsupportedError {
    // Unmodifiable view (platform channel codec): nothing to do.
  }
}
