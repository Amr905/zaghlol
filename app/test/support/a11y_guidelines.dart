import 'package:flutter_test/flutter_test.dart';

/// NFR-UX-02 guideline bundle: tap targets (Android 48dp, iOS 44pt), labels on
/// tappable nodes, and text contrast (WCAG AA). Call after the screen settled.
///
/// Also asserts nothing threw (RenderFlex overflow shows up as an exception).
Future<void> expectA11yGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  try {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(tester.takeException(), isNull, reason: 'overflow or build error');
  } finally {
    handle.dispose();
  }
}
