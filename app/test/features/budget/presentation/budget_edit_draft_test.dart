// T-101: S-23 validation (limits >= 0, thresholds 1-150, first < second).

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/budget/presentation/budget_edit_draft.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'budget_test_support.dart';

BudgetDraft draft({
  String total = '',
  bool useTotal = false,
  Map<String, String> cats = const {},
  int? first = 80,
  int? second = 100,
}) => BudgetDraft(
  currency: egp,
  useTotal: useTotal,
  totalText: total,
  categoryTexts: cats,
  first: first,
  second: second,
  rollover: false,
);

void main() {
  test('valid draft: blank and zero mean no budget; Arabic digits parse', () {
    final d = draft(cats: {'a': '', 'b': '0', 'c': '٤٬٠٠٠٫٥٠'});
    expect(validateDraft(d), isEmpty);
    final v = validated(d);
    expect(v.limits.keys, ['c']);
    expect(v.limits['c']!.minor, 400050);
    expect(v.limits['c']!.currency, egp);
    expect(v.total, isNull);
    expect(v.thresholds, [80, 100]);
  });

  test('negative and garbage limits are rejected', () {
    final e = validateDraft(draft(cats: {'a': '-5', 'b': 'abc', 'c': '1.234'}));
    expect(e['a'], BudgetEditError.limitNegative);
    expect(e['b'], BudgetEditError.limitInvalid);
    // EGP has two decimals: three is refused, never rounded.
    expect(e['c'], BudgetEditError.limitInvalid);
  });

  test('currency exponent: JPY has no decimals', () {
    final jpy = Currency.of('JPY');
    final d = BudgetDraft(
      currency: jpy,
      useTotal: true,
      totalText: '5000',
      categoryTexts: const {},
      first: 80,
      second: 100,
      rollover: false,
    );
    expect(validated(d).total!.minor, 5000);
  });

  test('threshold range and order', () {
    expect(
      validateDraft(draft(first: 0))['first'],
      BudgetEditError.thresholdRange,
    );
    expect(
      validateDraft(draft(second: 151))['second'],
      BudgetEditError.thresholdRange,
    );
    expect(
      validateDraft(draft(first: null))['first'],
      BudgetEditError.thresholdRange,
    );
    expect(
      validateDraft(draft(first: 100, second: 100))['first'],
      BudgetEditError.thresholdOrder,
    );
    expect(validateDraft(draft(first: 1, second: 150)), isEmpty);
  });

  test('total is only checked when "a total I set" is chosen', () {
    expect(validateDraft(draft(total: 'x')), isEmpty);
    expect(
      validateDraft(draft(total: 'x', useTotal: true))['total'],
      BudgetEditError.limitInvalid,
    );
  });
}
