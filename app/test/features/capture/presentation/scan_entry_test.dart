// T-161: the add sheet's Scan tile opens S-32 (WIRE-NAV).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_navigation.dart' show wiredAddSelected;
import 'package:zaghlol/core/ocr/unavailable_ocr_engine.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';

import '../../transactions/presentation/detail_edit_harness.dart';
import 'scan_confirm_screen_test.dart' show FakeOcr, scanOverrides;

void main() {
  for (final (name, engine, expected) in [
    ('ready phone', FakeOcr(''), 'Choose an image'),
    (
      'phone without OCR',
      const UnavailableOcrEngine(),
      "I can't read this kind of file",
    ),
  ]) {
    testWidgets('Scan tile opens S-32 on a $name', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harnessApp(
          scanOverrides(FakeEditor(), engine),
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) =>
                      AddSheet(onSelected: (a) => wiredAddSelected(ctx, a)),
                ),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Scan a screenshot'), findsOneWidget);
      expect(find.text(expected), findsWidgets);
    });
  }
}
