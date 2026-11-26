// T-325 AC1/AC2: the bundled name, business-word and honorific lists.
// The files are read from disk (the pubspec declaration is checked in
// flutter analyze / the asset bundle at build time).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show foldKey;

List<String> load(String name) {
  final bytes = File('assets/data/$name').readAsBytesSync();
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB) {
    throw StateError('BOM in $name');
  }
  final text = utf8.decode(bytes);
  return text.endsWith('\n')
      ? text.substring(0, text.length - 1).split('\n')
      : text.split('\n');
}

void main() {
  final lists = {
    'eg_given_names.txt': load('eg_given_names.txt'),
    'eg_business_words.txt': load('eg_business_words.txt'),
    'eg_honorifics.txt': load('eg_honorifics.txt'),
  };

  for (final e in lists.entries) {
    group(e.key, () {
      final l = e.value;
      test('non-empty lines, no digits, NFC-safe, folded', () {
        expect(l, isNotEmpty);
        for (final line in l) {
          expect(line, isNotEmpty);
          expect(line, line.trim());
          expect(RegExp(r'[0-9٠-٩۰-۹]').hasMatch(line), isFalse, reason: line);
          // NFC: no combining marks and no decomposable Arabic hamza forms
          // (no Dart NFC library; the folded form has neither).
          expect(
            RegExp(r'[\u0300-\u036F\u064B-\u065F\u0670]|[أإآ]').hasMatch(line),
            isFalse,
            reason: line,
          );
          expect(foldKey(line), line, reason: line);
        }
      });
      test('sorted by code unit and deduplicated', () {
        final sorted = [...l]..sort();
        expect(l, sorted);
        expect(l.toSet().length, l.length);
      });
    });
  }

  test('counts', () {
    expect(lists['eg_given_names.txt']!.length, greaterThanOrEqualTo(2000));
    expect(lists['eg_business_words.txt']!.length, greaterThanOrEqualTo(60));
  });

  test('business words are not names', () {
    final names = lists['eg_given_names.txt']!.toSet();
    expect(lists['eg_business_words.txt']!.where(names.contains), isEmpty);
  });
}
