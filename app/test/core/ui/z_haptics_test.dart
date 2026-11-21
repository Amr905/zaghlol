// UI-fix30: haptics fire through ZHaptics only, and can be switched off.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart';
import 'package:zaghlol/core/ui/z_button.dart';
import 'package:zaghlol/core/ui/z_haptics.dart';

import '../../features/budget/presentation/budget_test_support.dart';

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    ZHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (c) async {
          if (c.method == 'HapticFeedback.vibrate') {
            calls.add(c.arguments as String);
          }
          return null;
        });
  });
  tearDown(() {
    ZHaptics.enabled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('kinds map to the platform calls; disabled is silent', () {
    ZHaptics.selection();
    ZHaptics.light();
    ZHaptics.medium();
    ZHaptics.fire(ZHaptic.none);
    expect(calls, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
    calls.clear();
    ZHaptics.enabled = false;
    ZHaptics.medium();
    expect(calls, isEmpty);
  });

  testWidgets('ZButton ticks light by default, medium for save', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            ZButton(label: 'a', onPressed: () {}),
            ZButton(label: 'b', haptic: ZHaptic.medium, onPressed: () {}),
            const ZButton(label: 'c', onPressed: null),
          ],
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.text('a'));
    await tester.tap(find.text('b'));
    await tester.tap(find.text('c'));
    expect(calls, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  testWidgets('shell: Add is medium, tab switch is selection', (tester) async {
    var added = 0;
    var picked = -1;
    await tester.pumpWidget(
      harness(
        ShellScaffold(
          body: const SizedBox.shrink(),
          selected: 0,
          onSelect: (i) => picked = i,
          onAdd: () => added++,
          labels: const ['a', 'b', 'c', 'd'],
          addLabel: 'add',
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.byType(ZAddButton));
    await tester.tap(find.text('c'));
    expect(added, 1);
    expect(picked, 2);
    expect(calls, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.selectionClick',
    ]);
  });
}
