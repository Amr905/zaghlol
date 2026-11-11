// T-075 test group 1: Jaro-Winkler golden vectors (fixture table), in
// millionths, cross-checked against a floating-point reference written
// here (tests may use double; the package may not).

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const _vectors = <(String, String, int)>[
  ('ezaby', 'ezabi', 920000),
  ('metro', 'metra', 920000),
  ('metro', 'mitro', 880000),
  ('carrefour', 'carrefoure', 980000),
  ('talabat', 'talbat', 927778),
  ('zara', 'zaha', 866667),
  ('ezaby', 'ezaby pharmacy', 871429),
  ('martha', 'marhta', 961111),
  ('dixon', 'dicksonx', 813333),
];

double _reference(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  var w = (a.length > b.length ? a.length : b.length) ~/ 2 - 1;
  if (w < 0) w = 0;
  final am = List.filled(a.length, false);
  final bm = List.filled(b.length, false);
  var m = 0;
  for (var i = 0; i < a.length; i++) {
    for (
      var j = i - w < 0 ? 0 : i - w;
      j < (i + w + 1 > b.length ? b.length : i + w + 1);
      j++
    ) {
      if (!bm[j] && a[i] == b[j]) {
        am[i] = bm[j] = true;
        m++;
        break;
      }
    }
  }
  if (m == 0) return 0;
  var t = 0.0;
  var k = 0;
  for (var i = 0; i < a.length; i++) {
    if (!am[i]) continue;
    while (!bm[k]) {
      k++;
    }
    if (a[i] != b[k]) t += 0.5;
    k++;
  }
  final j = (m / a.length + m / b.length + (m - t) / m) / 3;
  if (j <= 0.7) return j;
  var p = 0;
  while (p < 4 && p < a.length && p < b.length && a[p] == b[p]) {
    p++;
  }
  return j + p * 0.1 * (1 - j);
}

void main() {
  group('jaroWinklerScore golden vectors', () {
    for (final (a, b, expected) in _vectors) {
      test('$a / $b = $expected', () {
        expect(jaroWinklerScore(a, b), expected);
        expect(jaroWinklerScore(b, a), expected, reason: 'symmetric');
        expect(
          (jaroWinklerScore(a, b) - _reference(a, b) * 1000000).abs(),
          lessThan(1),
          reason: 'matches the floating-point reference',
        );
      });
    }
    test('exact on the 0.92 line: no epsilon needed', () {
      expect(jaroWinklerScore('ezaby', 'ezabi'), 920000);
      expect(
        jaroWinklerScore('ezaby', 'ezabi') >=
            const CategorizerConfig().fuzzyThreshold,
        isTrue,
      );
    });
    test('equal is one, disjoint is 0, empty strings', () {
      expect(jaroWinklerScore('uber', 'uber'), scoreOne);
      expect(jaroWinklerScore('abc', 'xyz'), 0);
      expect(jaroWinklerScore('', ''), scoreOne);
      expect(jaroWinklerScore('', 'a'), 0);
      expect(jaroWinklerScore('a', ''), 0);
    });
    test('agrees with the reference on many pairs', () {
      const words = [
        'carrefour',
        'carefour',
        'talabat',
        'talbat',
        'ezaby',
        'ezabi',
        'b tech',
        'btech',
        'seoudi',
        'souidi',
        'a',
        'ab',
        'ba',
        'abcdefgh',
        'abcdfegh',
      ];
      for (final a in words) {
        for (final b in words) {
          expect(
            (jaroWinklerScore(a, b) - _reference(a, b) * 1000000).abs(),
            lessThan(1),
            reason: '$a / $b',
          );
        }
      }
    });
  });
}
