// T-015: a fixed synthetic database key for tests (design note §9, AC3).
//
// The bytes come from a formula, never from a literal, so neither the bytes
// nor their hex/base64 forms appear in the test binary: a sandbox or log scan
// for them must find nothing unless the app leaked the key. The CI host
// computes the same needles with .github/scripts/db-key-needles.py.
//
// Never print these values, and never use them in a test name, `reason:` or
// an assertion message.

import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol/core/db/key_bootstrap.dart';

/// byte[i] = (seed + 97·i) mod 256. Seed 61 is the AC3 key.
Uint8List syntheticKeyBytes([int seed = 61]) => Uint8List.fromList([
  for (var i = 0; i < dbKeyLength; i++) (seed + 97 * i) & 0xFF,
]);

/// The search needles for [bytes]: the raw bytes, lowercase hex, uppercase
/// hex and standard base64 (ASCII).
List<List<int>> keyNeedles(Uint8List bytes) {
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return [
    bytes,
    ascii.encode(hex),
    ascii.encode(hex.toUpperCase()),
    ascii.encode(base64.encode(bytes)),
  ];
}

/// Hands out copies of a fixed key (each call is a fresh buffer, as the
/// bootstrap zeroes the candidate).
final class FixedKeyGenerator implements KeyGenerator {
  FixedKeyGenerator([this.seed = 61]);

  final int seed;
  final List<Uint8List> handedOut = [];

  @override
  Uint8List? next() {
    final out = syntheticKeyBytes(seed);
    handedOut.add(out);
    return out;
  }
}

/// A generator that returns fixed keys from a list of seeds, in order.
final class SequenceKeyGenerator implements KeyGenerator {
  SequenceKeyGenerator(this.seeds);

  final List<int> seeds;
  var _i = 0;

  @override
  Uint8List? next() => syntheticKeyBytes(seeds[_i++ % seeds.length]);
}

/// Single-pass multi-needle search: true if any needle occurs in [hay].
bool containsAnyNeedle(Uint8List hay, List<List<int>> needles) {
  if (needles.isEmpty) return false;
  final firsts = <int, List<List<int>>>{};
  for (final n in needles) {
    if (n.isEmpty) return true;
    (firsts[n.first] ??= []).add(n);
  }
  for (var i = 0; i < hay.length; i++) {
    final candidates = firsts[hay[i]];
    if (candidates == null) continue;
    outer:
    for (final n in candidates) {
      if (i + n.length > hay.length) continue;
      for (var j = 1; j < n.length; j++) {
        if (hay[i + j] != n[j]) continue outer;
      }
      return true;
    }
  }
  return false;
}
