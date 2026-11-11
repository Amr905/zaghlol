// T-008: ULIDs for raw_messages ids (database-schema.md: ULID TEXT primary
// keys). Crockford base32, 48-bit millisecond time + 80 random bits.

import 'dart:math';

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// The shape of a ULID (also what native spool ids look like).
final RegExp ulidPattern = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

final class UlidGenerator {
  UlidGenerator({Random? random, int Function()? nowMs})
    : _random = random ?? Random.secure(),
      _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Random _random;
  final int Function() _nowMs;

  String next() {
    final out = StringBuffer();
    var t = _nowMs();
    final time = List<String>.filled(10, '0');
    for (var i = 9; i >= 0; i--) {
      time[i] = _alphabet[t & 31];
      t >>= 5;
    }
    out.writeAll(time);
    for (var i = 0; i < 16; i++) {
      out.write(_alphabet[_random.nextInt(32)]);
    }
    return out.toString();
  }
}
