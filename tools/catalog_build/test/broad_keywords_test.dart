import 'dart:io';

import 'package:test/test.dart';

// FU-251: keep the seed from regressing to over-broad matches.
void main() {
  final rows = File('data/catalog_curated.csv').readAsLinesSync();
  test('no bare CLAUDE alias, bare محطة or bare food keyword', () {
    expect(rows.where((r) => r.contains(',CLAUDE,prefix')), isEmpty);
    expect(rows.where((r) => r.endsWith(',محطة,ar,60')), isEmpty);
    expect(rows.where((r) => r.endsWith(',food,en,60')), isEmpty);
  });
}
