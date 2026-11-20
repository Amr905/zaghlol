// T-196: every category the detection skips is a real seeded category code
// (a dead code would silently exclude nothing).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  test('every excluded id is a seeded category code; rent-like ones are not '
      'excluded', () {
    final seeded = {
      for (final line in File(
        '../tools/catalog_build/data/catalog_seed.csv',
      ).readAsLinesSync())
        if (line.startsWith('category,')) line.split(',')[1],
    };
    expect(seeded, containsAll(['groceries', 'dining', 'transport', 'bills']));
    for (final id in nonRecurringCategoryIds) {
      expect(seeded, contains(id), reason: id);
    }
    expect(nonRecurringCategoryIds, {
      'groceries',
      'dining',
      'transport',
      'cash',
      'income',
    });
    for (final bill in ['bills', 'housing', 'subscriptions', 'instapay']) {
      expect(nonRecurringCategoryIds, isNot(contains(bill)));
    }
  });
}
