/// Rounding modes for exact integer division. There is no implicit default:
/// every caller names the mode it needs.
enum MoneyRounding {
  /// Nearest; exact halves go to the even neighbour (banker's rounding).
  /// Used by the approximate (≈) view.
  halfEven,

  /// Nearest; exact halves go away from zero.
  halfAwayFromZero,

  /// Toward negative infinity. Used by safe-to-spend.
  floor,

  /// Toward positive infinity.
  ceil,

  /// Toward zero (truncation).
  towardZero,
}

/// Returns `numerator / denominator` rounded with [mode], computed exactly
/// on [BigInt].
///
/// Throws [ArgumentError] when [denominator] is zero. Shared with the ≈ view
/// (T-115) and the Zakah engine.
BigInt roundDiv(BigInt numerator, BigInt denominator, MoneyRounding mode) {
  if (denominator == BigInt.zero) {
    throw ArgumentError('denominator must not be zero');
  }
  // Normalize so that d > 0.
  final n = denominator.isNegative ? -numerator : numerator;
  final d = denominator.abs();
  // Truncating division: q rounds toward zero, rem has the sign of n.
  final q = n ~/ d;
  final rem = n - q * d;
  if (rem == BigInt.zero) {
    return q;
  }
  // rem != 0, so n != 0 and the exact quotient lies strictly between q and
  // q + step, where step points away from zero.
  final step = n.isNegative ? -BigInt.one : BigInt.one;
  switch (mode) {
    case MoneyRounding.towardZero:
      return q;
    case MoneyRounding.floor:
      return n.isNegative ? q - BigInt.one : q;
    case MoneyRounding.ceil:
      return n.isNegative ? q : q + BigInt.one;
    case MoneyRounding.halfAwayFromZero:
      return rem.abs() * BigInt.two >= d ? q + step : q;
    case MoneyRounding.halfEven:
      final twice = rem.abs() * BigInt.two;
      if (twice > d) {
        return q + step;
      }
      if (twice < d) {
        return q;
      }
      return q.isEven ? q : q + step;
  }
}
