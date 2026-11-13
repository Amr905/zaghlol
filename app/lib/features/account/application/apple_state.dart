// T-147 (backend-api §4.6, Sign in with Apple on Android, step 4): the
// random `state` of the Custom Tab flow. Single use, at most 10 minutes,
// held in memory only. An unknown, reused or expired value is rejected.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const Duration appleStateLifetime = Duration(minutes: 10);

final class AppleStateGuard {
  AppleStateGuard({Random? random, DateTime Function()? now})
    : _rng = random ?? Random.secure(),
      _now = now ?? DateTime.now;

  final Random _rng;
  final DateTime Function() _now;
  String? _value;
  DateTime? _issuedAt;

  /// A new state (>= 128 bits, base64url); replaces any earlier one.
  String issue() {
    final b = Uint8List(24);
    for (var i = 0; i < b.length; i++) {
      b[i] = _rng.nextInt(256);
    }
    _value = base64Url.encode(b).replaceAll('=', '');
    _issuedAt = _now();
    return _value!;
  }

  /// True once, and only for the issued value within the lifetime. The held
  /// value is dropped whatever the answer, so a wrong guess burns it.
  bool consume(String? returned) {
    final held = _value;
    final at = _issuedAt;
    _value = null;
    _issuedAt = null;
    if (held == null || at == null || returned == null) return false;
    if (_now().difference(at) > appleStateLifetime) return false;
    return _constantTimeEquals(held, returned);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return r == 0;
  }

  @override
  String toString() => 'AppleStateGuard';
}
