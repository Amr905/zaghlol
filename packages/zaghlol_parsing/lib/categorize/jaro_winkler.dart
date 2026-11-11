/// Jaro and Jaro-Winkler similarity (T-075, parsing-engine §5). Pure.
///
/// Scores are integers in millionths (0 to 1000000), computed with exact
/// integer arithmetic and rounded to the nearest millionth. That keeps
/// floating point out of the package (no `double`, per the lint scope) and
/// makes the threshold test exact: `ezaby`/`ezabi` is exactly 920000, so
/// "at least 0.92" needs no epsilon.
library;

/// A similarity of 1.0.
const int scoreOne = 1000000;

/// Winkler prefix scale 0.1 is applied as `p / 10` per shared prefix
/// character, up to [winklerMaxPrefix].
const int winklerMaxPrefix = 4;

/// The boost applies only when the Jaro score is above 0.7 (7 / 10).
const int _boostNumerator = 7;
const int _boostDenominator = 10;

/// Jaro similarity of [a] and [b] as an exact fraction `(num, den)`.
/// Two empty strings are equal (1); one empty string scores 0. Match window
/// is `floor(max(len) / 2) - 1` (at least 0), on UTF-16 code units.
(int, int) jaroFraction(String a, String b) {
  if (a == b) return (1, 1);
  final la = a.length;
  final lb = b.length;
  if (la == 0 || lb == 0) return (0, 1);
  var window = (la > lb ? la : lb) ~/ 2 - 1;
  if (window < 0) window = 0;
  final aMatched = List<bool>.filled(la, false);
  final bMatched = List<bool>.filled(lb, false);
  var m = 0;
  for (var i = 0; i < la; i++) {
    final lo = i - window < 0 ? 0 : i - window;
    final hi = i + window + 1 > lb ? lb : i + window + 1;
    for (var j = lo; j < hi; j++) {
      if (bMatched[j] || a.codeUnitAt(i) != b.codeUnitAt(j)) continue;
      aMatched[i] = true;
      bMatched[j] = true;
      m++;
      break;
    }
  }
  if (m == 0) return (0, 1);
  var half = 0; // half-transpositions: t = half / 2
  var k = 0;
  for (var i = 0; i < la; i++) {
    if (!aMatched[i]) continue;
    while (!bMatched[k]) {
      k++;
    }
    if (a.codeUnitAt(i) != b.codeUnitAt(k)) half++;
    k++;
  }
  // j = (m/la + m/lb + (m - t)/m) / 3, over the denominator 6 * la * lb * m.
  final top = 2 * m * lb * m + 2 * m * la * m + (2 * m - half) * la * lb;
  final den = 6 * la * lb * m;
  return (top, den);
}

int _toScore(int top, int den) => (top * scoreOne + den ~/ 2) ~/ den;

/// Jaro similarity in millionths.
int jaroScore(String a, String b) {
  final (n, d) = jaroFraction(a, b);
  return _toScore(n, d);
}

/// Jaro-Winkler similarity in millionths (prefix cap 4, scale 0.1, boost
/// only when Jaro > 0.7). Symmetric.
int jaroWinklerScore(String a, String b) {
  final (n, d) = jaroFraction(a, b);
  if (n * _boostDenominator <= _boostNumerator * d) return _toScore(n, d);
  var p = 0;
  final cap = [
    a.length,
    b.length,
    winklerMaxPrefix,
  ].reduce((x, y) => x < y ? x : y);
  while (p < cap && a.codeUnitAt(p) == b.codeUnitAt(p)) {
    p++;
  }
  // jw = j + p/10 * (1 - j) = (j * (10 - p) + p) / 10
  return _toScore(n * (10 - p) + p * d, 10 * d);
}
