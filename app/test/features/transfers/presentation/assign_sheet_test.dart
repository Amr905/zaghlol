import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transfers/presentation/assign_sheet.dart';

import 'transfers_harness.dart';

Future<void> _open(
  WidgetTester t,
  FakePort p, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
}) => pumpSheet(
  t,
  port: p,
  locale: locale,
  textScale: scale,
  open: (c) => showAssignSheet(c, 'in1'),
);

void main() {
  setUpAll(initDateFormatting);

  testWidgets('populated: header, candidates, nothing assigned yet', (t) async {
    await _open(t, FakePort(assignData: sampleAssign()));
    expect(find.text('Assign to expenses'), findsOneWidget);
    expect(textHas('from AHMED'), findsOneWidget);
    expect(find.text('Cilantro'), findsOneWidget);
    expect(find.text('Uber'), findsOneWidget);
    expect(textHas('Not assigned: EGP 800.00'), findsOneWidget);
  });

  testWidgets('picking expenses fills amounts and updates "not assigned"', (
    t,
  ) async {
    await _open(t, FakePort(assignData: sampleAssign()));
    await t.tap(find.text('Uber'));
    await t.pump();
    // Uber has room 180.00.
    expect(textHas('Not assigned: EGP 620.00'), findsOneWidget);
    await t.tap(find.text('Cilantro'));
    await t.pump();
    // The rest of the transfer (620) goes to Cilantro: nothing left.
    expect(textHas('Not assigned: EGP 0.00'), findsOneWidget);
  });

  testWidgets('save sends exact amounts', (t) async {
    final port = FakePort(assignData: sampleAssign());
    await _open(t, port);
    await t.tap(find.text('Uber'));
    await t.pump();
    await t.enterText(find.byType(TextField).last, '١٥٠٫٢٥');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final (src, lines, _) = port.assigned.single;
    expect(src, 'in1');
    expect(lines.single.expenseId, 'x2');
    expect(lines.single.amountMinor, 15025);
    expect(find.text('Assigned ✓'), findsOneWidget);
  });

  testWidgets('more than the expense is refused', (t) async {
    final port = FakePort(assignData: sampleAssign());
    await _open(t, port);
    await t.tap(find.text('Uber'));
    await t.pump();
    await t.enterText(find.byType(TextField).last, '200');
    await t.tap(find.text('Save'));
    await t.pump();
    expect(
      find.text("Money back can't be more than the expense"),
      findsOneWidget,
    );
    expect(port.assigned, isEmpty);
  });

  testWidgets('more than the transfer is refused', (t) async {
    final port = FakePort(assignData: sampleAssign());
    await _open(t, port);
    await t.tap(find.text('Cilantro'));
    await t.pump();
    await t.tap(find.text('Uber'));
    await t.pump();
    await t.enterText(find.byType(TextField).last, '180');
    await t.enterText(find.byType(TextField).at(1), '800');
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.text("You've assigned more than you received"), findsOneWidget);
    expect(port.assigned, isEmpty);
  });

  testWidgets('empty: message and search-all reloads without the window', (
    t,
  ) async {
    final port = FakePort(assignData: sampleAssign(candidates: const []));
    await _open(t, port);
    expect(find.text('No expenses in the last 60 days'), findsOneWidget);
    await t.tap(find.text('Search all expenses').last);
    await t.pumpAndSettle();
    expect(port.searchAllCalls, [false, true]);
  });

  testWidgets('error state offers Try again', (t) async {
    await _open(t, FakePort()..loadFails = true);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('no overflow at 1.3x (${locale.languageCode})', (t) async {
      await _open(
        t,
        FakePort(assignData: sampleAssign()),
        locale: locale,
        scale: 1.3,
      );
      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
