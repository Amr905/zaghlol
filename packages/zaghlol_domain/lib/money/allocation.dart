/// Maximum number of weights accepted by [largestRemainderSplit].
const int maxAllocationParts = 10000;

/// Splits the integer [amount] into `weights.length` integer shares in
/// proportion to [weights], using the largest-remainder (Hamilton) method.
///
/// Guarantees:
/// - the shares sum to exactly [amount] (no unit is lost or created);
/// - zero weights get exactly zero;
/// - each share is within one unit of its exact quota;
/// - the leftover units go to the largest remainders, ties broken by the
///   lower index, never to a zero weight;
/// - negative amounts are split symmetrically: `split(-x) == -split(x)`.
///
/// Throws [ArgumentError] when [weights] is empty, longer than
/// [maxAllocationParts], has a negative entry or sums to zero. Intermediate
/// products are computed on [BigInt], so any int weights are safe.
List<int> largestRemainderSplit(int amount, List<int> weights) {
  if (weights.isEmpty) {
    throw ArgumentError('weights must not be empty');
  }
  if (weights.length > maxAllocationParts) {
    throw ArgumentError('too many weights (max $maxAllocationParts)');
  }
  var total = BigInt.zero;
  for (final w in weights) {
    if (w < 0) {
      throw ArgumentError('weights must not be negative');
    }
    total += BigInt.from(w);
  }
  if (total == BigInt.zero) {
    throw ArgumentError('at least one weight must be positive');
  }

  final negative = amount < 0;
  // |amount| fits in int64 for every amount Money can hold (|x| <= 2^53 - 1);
  // BigInt keeps this exact for any int anyway.
  final a = BigInt.from(amount).abs();

  final shares = List<BigInt>.filled(weights.length, BigInt.zero);
  final remainders = List<BigInt>.filled(weights.length, BigInt.zero);
  var assigned = BigInt.zero;
  for (var i = 0; i < weights.length; i++) {
    final product = a * BigInt.from(weights[i]);
    shares[i] = product ~/ total;
    remainders[i] = product.remainder(total);
    assigned += shares[i];
  }

  // 0 <= leftover < number of positive weights.
  final leftover = (a - assigned).toInt();
  if (leftover > 0) {
    final candidates = <int>[];
    for (var i = 0; i < weights.length; i++) {
      if (weights[i] > 0) {
        candidates.add(i);
      }
    }
    candidates.sort((i, j) {
      final byRemainder = remainders[j].compareTo(remainders[i]);
      return byRemainder != 0 ? byRemainder : i.compareTo(j);
    });
    for (var k = 0; k < leftover; k++) {
      shares[candidates[k]] += BigInt.one;
    }
  }

  return [for (final s in shares) negative ? -s.toInt() : s.toInt()];
}
