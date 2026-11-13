// T-183: strict JSON parser for the exact restore body the app is about to
// send (backend-api §4.3 step 1, R2-6). Differences from dart:convert:
//  - duplicate member names are rejected at any depth;
//  - lone UTF-16 surrogates are rejected (raw and \u-escaped);
//  - size and depth are capped; no input is ever echoed in an error.
// Result types: Map<String, Object?>, List<Object?>, String, bool, null,
// int (integer literals within +-2^53) and double (everything else numeric).

import 'binding_exceptions.dart';

const int strictJsonMaxLength = 1 << 20; // 1 Mi UTF-16 code units
const int strictJsonMaxDepth = 64;

Object? parseStrictJson(String source) {
  if (source.length > strictJsonMaxLength) {
    throw const BindingException(BindingFailure.malformedJson);
  }
  final p = _Parser(source);
  p._skipWs();
  final v = p._value(0);
  p._skipWs();
  if (p._i != source.length) p._fail();
  return v;
}

class _Parser {
  _Parser(this._s);
  final String _s;
  int _i = 0;

  Never _fail([BindingFailure f = BindingFailure.malformedJson]) =>
      throw BindingException(f);

  void _skipWs() {
    while (_i < _s.length) {
      final c = _s.codeUnitAt(_i);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        _i++;
      } else {
        break;
      }
    }
  }

  Object? _value(int depth) {
    if (depth > strictJsonMaxDepth) _fail();
    if (_i >= _s.length) _fail();
    final c = _s.codeUnitAt(_i);
    switch (c) {
      case 0x7b:
        return _object(depth);
      case 0x5b:
        return _array(depth);
      case 0x22:
        return _string();
      case 0x74:
        return _literal('true', true);
      case 0x66:
        return _literal('false', false);
      case 0x6e:
        return _literal('null', null);
      default:
        return _number();
    }
  }

  Object? _literal(String word, Object? value) {
    if (!_s.startsWith(word, _i)) _fail();
    _i += word.length;
    return value;
  }

  Map<String, Object?> _object(int depth) {
    _i++;
    final map = <String, Object?>{};
    _skipWs();
    if (_peek() == 0x7d) {
      _i++;
      return map;
    }
    while (true) {
      _skipWs();
      if (_peek() != 0x22) _fail();
      final key = _string();
      if (map.containsKey(key)) _fail(BindingFailure.duplicateMember);
      _skipWs();
      if (_peek() != 0x3a) _fail();
      _i++;
      _skipWs();
      map[key] = _value(depth + 1);
      _skipWs();
      final c = _peek();
      _i++;
      if (c == 0x2c) continue;
      if (c == 0x7d) return map;
      _fail();
    }
  }

  List<Object?> _array(int depth) {
    _i++;
    final list = <Object?>[];
    _skipWs();
    if (_peek() == 0x5d) {
      _i++;
      return list;
    }
    while (true) {
      _skipWs();
      list.add(_value(depth + 1));
      _skipWs();
      final c = _peek();
      _i++;
      if (c == 0x2c) continue;
      if (c == 0x5d) return list;
      _fail();
    }
  }

  int _peek() => _i < _s.length ? _s.codeUnitAt(_i) : -1;

  static bool _isHigh(int c) => c >= 0xd800 && c <= 0xdbff;
  static bool _isLow(int c) => c >= 0xdc00 && c <= 0xdfff;

  String _string() {
    _i++; // opening quote
    final out = StringBuffer();
    int pendingHigh = -1; // a high surrogate awaiting its low partner
    void unit(int u) {
      if (pendingHigh >= 0) {
        if (!_isLow(u)) _fail(BindingFailure.loneSurrogate);
        out
          ..writeCharCode(pendingHigh)
          ..writeCharCode(u);
        pendingHigh = -1;
      } else if (_isHigh(u)) {
        pendingHigh = u;
      } else if (_isLow(u)) {
        _fail(BindingFailure.loneSurrogate);
      } else {
        out.writeCharCode(u);
      }
    }

    while (true) {
      if (_i >= _s.length) _fail();
      final c = _s.codeUnitAt(_i++);
      if (c == 0x22) {
        if (pendingHigh >= 0) _fail(BindingFailure.loneSurrogate);
        return out.toString();
      }
      if (c < 0x20) _fail();
      if (c != 0x5c) {
        unit(c);
        continue;
      }
      if (_i >= _s.length) _fail();
      final e = _s.codeUnitAt(_i++);
      switch (e) {
        case 0x22:
          unit(0x22);
        case 0x5c:
          unit(0x5c);
        case 0x2f:
          unit(0x2f);
        case 0x62:
          unit(0x08);
        case 0x66:
          unit(0x0c);
        case 0x6e:
          unit(0x0a);
        case 0x72:
          unit(0x0d);
        case 0x74:
          unit(0x09);
        case 0x75:
          if (_i + 4 > _s.length) _fail();
          var v = 0;
          for (var k = 0; k < 4; k++) {
            final d = _hex(_s.codeUnitAt(_i++));
            if (d < 0) _fail();
            v = v * 16 + d;
          }
          unit(v);
        default:
          _fail();
      }
    }
  }

  static int _hex(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    return -1;
  }

  static bool _digit(int c) => c >= 0x30 && c <= 0x39;

  Object _number() {
    final start = _i;
    var isInt = true;
    if (_peek() == 0x2d) _i++;
    if (_peek() == 0x30) {
      _i++;
    } else if (_digit(_peek())) {
      while (_digit(_peek())) {
        _i++;
      }
    } else {
      _fail();
    }
    if (_peek() == 0x2e) {
      isInt = false;
      _i++;
      if (!_digit(_peek())) _fail();
      while (_digit(_peek())) {
        _i++;
      }
    }
    if (_peek() == 0x65 || _peek() == 0x45) {
      isInt = false;
      _i++;
      if (_peek() == 0x2b || _peek() == 0x2d) _i++;
      if (!_digit(_peek())) _fail();
      while (_digit(_peek())) {
        _i++;
      }
    }
    final text = _s.substring(start, _i);
    if (isInt && text.length <= 16) {
      final n = int.parse(text);
      if (n.abs() <= 9007199254740991) return n;
    }
    final d = double.parse(text);
    if (d.isNaN || d.isInfinite) _fail(BindingFailure.unsupportedNumber);
    return d;
  }
}
