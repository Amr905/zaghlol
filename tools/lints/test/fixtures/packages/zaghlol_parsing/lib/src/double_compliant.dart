// Compliant: integer arithmetic, and a documented allow-list entry.

class DoubleCompliant {
  int half(int minor) => minor ~/ 2;

  int parseMinor(String s) => int.parse(s);

  int? tryMinor(String s) => int.tryParse(s);

  BigInt big(String s) => BigInt.parse(s);

  int timing(Stopwatch sw) {
    // ignore: no_double_money - benchmark timing, not money
    final ms = sw.elapsedMicroseconds / 1000;
    return ms.round();
  }
}
