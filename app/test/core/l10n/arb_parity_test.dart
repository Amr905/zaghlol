import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Parity between the template (AR) and EN ARB files (T-029 / T-087 testing
// section). Runs from app/, where `flutter test` sets the working directory.

Map<String, dynamic> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Map<String, dynamic> _messages(Map<String, dynamic> arb) => {
  for (final e in arb.entries)
    if (!e.key.startsWith('@')) e.key: e.value,
};

// ICU argument names in a message: {name}, and the selector of a plural or
// select. Branch words such as {Tomorrow} inside a plural body are not args.
final _icuId = RegExp(r'\s*([A-Za-z][A-Za-z0-9]*)\s*');
final _icuKind = RegExp(r'\s*,\s*(\w+)\s*,');
final _icuBranch = RegExp(r'\s*([^{}\s]+)\s*\{');

Set<String> _icuArgs(String s) {
  final names = <String>{};
  _icuMessage(s, 0, stop: false, names: names);
  return names;
}

int _icuMessage(
  String s,
  int i, {
  required bool stop,
  required Set<String> names,
}) {
  while (i < s.length) {
    final c = s[i];
    if (c == '}' && stop) return i + 1;
    i = c == '{' ? _icuArgument(s, i + 1, names) : i + 1;
  }
  if (stop) throw FormatException('unclosed brace in: $s');
  return i;
}

int _icuArgument(String s, int i, Set<String> names) {
  final m = _icuId.matchAsPrefix(s, i);
  if (m == null) throw FormatException('bad argument in: $s');
  names.add(m.group(1)!);
  final j = m.end;
  if (s[j] == '}') return j + 1;
  final k = _icuKind.matchAsPrefix(s, j);
  if (k == null || (k.group(1) != 'plural' && k.group(1) != 'select')) {
    throw FormatException('unsupported ICU argument in: $s');
  }
  var p = k.end;
  while (true) {
    while (s[p].trim().isEmpty) {
      p++;
    }
    if (s[p] == '}') return p + 1;
    final b = _icuBranch.matchAsPrefix(s, p);
    if (b == null) throw FormatException('bad branch in: $s');
    p = _icuMessage(s, b.end, stop: true, names: names);
  }
}

Set<String> _placeholders(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map) return {};
  final ph = meta['placeholders'];
  if (ph is! Map) return {};
  return ph.keys.cast<String>().toSet();
}

void main() {
  const arPath = 'lib/core/l10n/app_ar.arb';
  const enPath = 'lib/core/l10n/app_en.arb';
  final ar = _readArb(arPath);
  final en = _readArb(enPath);
  final arMsgs = _messages(ar);
  final enMsgs = _messages(en);

  group('ARB parity', () {
    test('AR and EN have the same message keys', () {
      expect(enMsgs.keys.toSet(), arMsgs.keys.toSet());
    });

    test('every key has the same placeholder set in AR and EN', () {
      for (final key in arMsgs.keys) {
        expect(
          _icuArgs(enMsgs[key] as String),
          _icuArgs(arMsgs[key] as String),
          reason: 'placeholders differ for $key',
        );
      }
    });

    test('AR template placeholder metadata matches its ICU text', () {
      for (final key in arMsgs.keys) {
        expect(
          _placeholders(ar, key),
          _icuArgs(arMsgs[key] as String),
          reason: 'metadata differs for $key',
        );
      }
    });
  });

  group('Arabic text', () {
    test('no Western digits in AR messages', () {
      final digit = RegExp('[0-9]');
      for (final e in arMsgs.entries) {
        final text = (e.value as String)
            // ICU exact-match selectors such as =1 and =2 are syntax.
            .replaceAll(RegExp(r'=\d+'), '')
            // Placeholder names such as {last4} carry digits by name only.
            .replaceAll(RegExp(r'\{[A-Za-z][A-Za-z0-9]*'), '{');
        expect(digit.hasMatch(text), isFalse, reason: 'digit in ${e.key}');
      }
    });
  });
}
