// SMS-device: the historical inbox scan asks the system SMS provider for
// concrete sender addresses (`address IN (...)`; SQL cannot run a regex), so
// a registry sender written as a regex (HSBC: `^hsbc(?:[ ._-]?(?:eg|egy|
// egypt|bank))?$`) was never scanned and its old messages were never read.
// This turns such a regex into the finite list of addresses it matches.
//
// Supported grammar (anything else returns null, and the sender is then only
// captured live): optional `^` and `$` at the ends, literal characters
// (letters, digits, space, `-`, `_`, escaped `\.`), classes `[ ._-]`, groups
// `(?:a|b)` and the `?` quantifier on a literal, class or group. Pure; no
// logging; output is lower case (native binds the lower, upper and original
// case of every address; a Title Case variant is added here for senders such
// as `Hsbc`).

/// Most addresses one pattern may expand to.
const int kMaxExpandedSenders = 64;

/// The addresses [pattern] matches (lower case, plus Title Case variants),
/// or null when it is outside the supported grammar or expands past
/// [kMaxExpandedSenders].
List<String>? expandSenderRegex(String pattern) {
  try {
    final p = _Parser(pattern);
    final out = p.parse();
    if (out == null || out.isEmpty || out.length > kMaxExpandedSenders) {
      return null;
    }
    final all = <String>{};
    for (final s in out) {
      if (s.trim().isEmpty) continue;
      all.add(s);
      all.add(_title(s));
    }
    if (all.isEmpty) return null;
    return all.toList()..sort();
  } on Object {
    return null;
  }
}

String _title(String s) {
  final b = StringBuffer();
  var start = true;
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    b.write(start ? c.toUpperCase() : c);
    start = c == ' ' || c == '.' || c == '-' || c == '_';
  }
  return b.toString();
}

final class _Parser {
  _Parser(this._s);

  final String _s;
  int _i = 0;

  List<String>? parse() {
    if (_peek == '^') _i++;
    final r = _sequence(topLevel: true);
    if (r == null) return null;
    if (_peek == r'$') _i++;
    if (_i != _s.length) return null;
    return r;
  }

  String? get _peek => _i < _s.length ? _s[_i] : null;

  /// Concatenation of items until `|`, `)` or the end.
  List<String>? _sequence({required bool topLevel}) {
    var acc = <String>[''];
    while (true) {
      final c = _peek;
      if (c == null || c == '|' || c == ')') break;
      if (topLevel && c == r'$' && _i == _s.length - 1) break;
      final atom = _atom();
      if (atom == null) return null;
      var options = atom;
      if (_peek == '?') {
        _i++;
        options = {'', ...atom}.toList();
      } else if (_peek == '*' || _peek == '+' || _peek == '{') {
        return null;
      }
      final next = <String>{};
      for (final a in acc) {
        for (final o in options) {
          next.add(a + o);
        }
      }
      if (next.length > kMaxExpandedSenders * 4) return null;
      acc = next.toList();
    }
    return acc;
  }

  List<String>? _atom() {
    final c = _peek!;
    if (c == '(') {
      if (!_s.startsWith('(?:', _i)) return null;
      _i += 3;
      final alts = <String>{};
      while (true) {
        final seq = _sequence(topLevel: false);
        if (seq == null) return null;
        alts.addAll(seq);
        if (_peek == '|') {
          _i++;
          continue;
        }
        break;
      }
      if (_peek != ')') return null;
      _i++;
      return alts.toList();
    }
    if (c == '[') {
      final end = _s.indexOf(']', _i + 1);
      if (end < 0) return null;
      final body = _s.substring(_i + 1, end);
      _i = end + 1;
      if (body.isEmpty || body.startsWith('^')) return null;
      final chars = <String>[];
      for (var k = 0; k < body.length; k++) {
        final ch = body[k];
        if (ch == r'\') {
          if (k + 1 >= body.length) return null;
          chars.add(body[++k]);
        } else if (k + 1 < body.length - 1 && body[k + 1] == '-') {
          return null; // a range: not supported
        } else {
          chars.add(ch);
        }
      }
      return chars;
    }
    if (c == r'\') {
      if (_i + 1 >= _s.length) return null;
      final n = _s[_i + 1];
      if (!'.-_ /'.contains(n)) return null;
      _i += 2;
      return [n];
    }
    if ('.*+{}|^\$'.contains(c)) return null;
    _i++;
    return [c.toLowerCase()];
  }
}
