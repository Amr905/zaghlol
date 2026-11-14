// WIRE-2 (T-118): the default widget copy comes from the ARB strings.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/widgets_bridge/application/widget_bridge.dart';

void main() {
  test('en: the four lines come from l10n', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final copy = c.read(widgetCopyProvider('en'));
    expect(copy.openApp, 'Open Zaghlol');
    expect(copy.setBudget, 'Set a budget');
    expect(copy.perDay('X'), 'X/day');
    expect(copy.daysToPayday(3, '3'), '3 days to payday');
  });

  test('ar: Egyptian copy, same keys', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final copy = c.read(widgetCopyProvider('ar'));
    expect(copy.openApp, 'افتح زغلول');
    expect(copy.setBudget, isNotEmpty);
    expect(copy.perDay('X'), contains('X'));
    expect(copy.daysToPayday(1, '١'), isNotEmpty);
  });
}
