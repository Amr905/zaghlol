// T-183: RFC 8785 (JCS) canonicalizer over a value produced by
// parseStrictJson. Keys sort by UTF-16 code units (String.compareTo does
// exactly that); numbers use ECMAScript Number::toString; strings use the
// RFC 8785 §3.2.2.2 escape set. Output is the canonical text; utf8 of it is
// what gets hashed.

import 'binding_exceptions.dart';

String jcsCanonicalize(Object? value) {
  final b = StringBuffer();
  _write(b, value);
  return b.toString();
}

void _write(StringBuffer b, Object? v) {
  switch (v) {
    case null:
      b.write('null');
    case bool():
      b.write(v ? 'true' : 'false');
    case int():
      b.write(_intText(v));
    case double():
      b.write(esNumberToString(v));
    case String():
      _writeString(b, v);
    case List<Object?>():
      b.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) b.write(',');
        _write(b, v[i]);
      }
      b.write(']');
    case Map<String, Object?>():
      final keys = v.keys.toList()..sort();
      b.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) b.write(',');
        _writeString(b, keys[i]);
        b.write(':');
        _write(b, v[keys[i]]);
      }
      b.write('}');
    default:
      throw const BindingException(BindingFailure.invalidInput);
  }
}

String _intText(int n) {
  if (n.abs() > 9007199254740991) {
    return esNumberToString(n.toDouble());
  }
  return n.toString();
}

void _writeString(StringBuffer b, String s) {
  b.write('"');
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5c:
        b.write(r'\\');
      case 0x08:
        b.write(r'\b');
      case 0x09:
        b.write(r'\t');
      case 0x0a:
        b.write(r'\n');
      case 0x0c:
        b.write(r'\f');
      case 0x0d:
        b.write(r'\r');
      default:
        if (c < 0x20) {
          b.write('\\u00${c.toRadixString(16).padLeft(2, '0')}');
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
}

/// ECMAScript Number::toString (RFC 8785 §3.2.2.3) for a finite double.
String esNumberToString(double d) {
  if (d.isNaN || d.isInfinite) {
    throw const BindingException(BindingFailure.unsupportedNumber);
  }
  if (d == 0) return '0'; // also -0
  final neg = d < 0;
  // Dart's toStringAsExponential() with no argument yields the shortest
  // round-trip digits: "d.ddde+x".
  final exp = d.abs().toStringAsExponential();
  final eIdx = exp.indexOf('e');
  final digits = exp.substring(0, eIdx).replaceAll('.', '');
  final n = int.parse(exp.substring(eIdx + 1)) + 1; // decimal point position
  final k = digits.length;
  final String body;
  if (k <= n && n <= 21) {
    body = digits + '0' * (n - k);
  } else if (0 < n && n <= 21) {
    body = '${digits.substring(0, n)}.${digits.substring(n)}';
  } else if (-6 < n && n <= 0) {
    body = '0.${'0' * -n}$digits';
  } else {
    final e = n - 1;
    final sign = e < 0 ? '-' : '+';
    final mant = k == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
    body = '${mant}e$sign${e.abs()}';
  }
  return neg ? '-$body' : body;
}
