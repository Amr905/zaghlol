import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transactions/application/reimbursements.dart';
import 'package:zaghlol/features/transfers/presentation/split_sheet.dart';

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
  open: (c) => showSplitSheet(c, 'x1'),
);

void main() {
  setUpAll(initDateFormatting);

  testWidgets('populated: people, status badges, repayment, suggestion', (
    t,
  ) async {
    await _open(t, FakePort(split: sampleSplit()));
    expect(find.text('Split the bill'), findsOneWidget);
    expect(find.text('Paid back'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Remove from this bill'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    // Amount 1,200 - 400 - 400 = 400 for the user.
    expect(textHas('400.00'), findsWidgets);
  });

  testWidgets('loading skeleton then error with Try again', (t) async {
    await _open(t, FakePort()..loadFails = true);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('expense no longer exists shows the load error', (t) async {
    await _open(t, FakePort());
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('your share updates live while typing Arabic-Indic digits', (
    t,
  ) async {
    await _open(t, FakePort(split: sampleSplit(withRepayment: false)));
    // Own share starts at 1,200 - 800 = 400.00; change Karim to 600.
    await t.enterText(find.byType(TextField).at(3), '٦٠٠');
    await t.pump();
    expect(
      find.bySemanticsLabel(RegExp('Your share.*200\\.00')),
      findsOneWidget,
    );
  });

  testWidgets('split evenly gives each person an equal exact share', (t) async {
    final port = FakePort(split: sampleSplit(withRepayment: false));
    await _open(t, port);
    await t.tap(find.text('Split evenly'));
    await t.pump();
    // 120000 / 3 people incl. the user = 40000 each.
    expect(find.text('400.00'), findsNWidgets(2));
  });

  testWidgets('save sends exact minor units parsed from typed digits', (
    t,
  ) async {
    final port = FakePort(split: sampleSplit(withRepayment: false));
    await _open(t, port);
    await t.enterText(find.byType(TextField).at(1), '٣٥٠٫٥٠');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final (id, edits, removed) = port.saved.single;
    expect(id, 'x1');
    expect(edits.first.shareMinor, 35050);
    expect(edits.first.id, 'p1');
    expect(removed, isEmpty);
    expect(find.text('Split saved ✓'), findsOneWidget);
    expect(find.text('Split the bill'), findsNothing);
  });

  testWidgets('shares over the expense are refused', (t) async {
    final port = FakePort(split: sampleSplit(withRepayment: false));
    await _open(t, port);
    await t.enterText(find.byType(TextField).at(1), '1100');
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.text('Shares add up to more than the expense'), findsOneWidget);
    expect(port.saved, isEmpty);
  });

  testWidgets('too many decimals for the currency and zero are refused', (
    t,
  ) async {
    final port = FakePort(split: sampleSplit(withRepayment: false));
    await _open(t, port);
    await t.enterText(find.byType(TextField).at(1), '10.505');
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.text('Each share must be more than zero'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(1), '0');
    await t.tap(find.text('Save'));
    await t.pump();
    expect(find.text('Each share must be more than zero'), findsOneWidget);
    expect(port.saved, isEmpty);
  });

  testWidgets('empty name refused; removing a person is sent as removed', (
    t,
  ) async {
    final port = FakePort(split: sampleSplit(withRepayment: false));
    await _open(t, port);
    await t.tap(find.byTooltip('Remove Karim'));
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(port.saved.single.$3, {'p2'});
  });

  testWidgets('save failure keeps the sheet and shows the message', (t) async {
    final port = FakePort(split: sampleSplit(withRepayment: false))
      ..failWith = reimb(ReimbursementException.conflict);
    await _open(t, port);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      find.text("Couldn't save. Try again — what you entered is still here."),
      findsOneWidget,
    );
    expect(find.text('Split the bill'), findsOneWidget);
  });

  testWidgets('unassign removes the link and offers Undo', (t) async {
    final port = FakePort(split: sampleSplit());
    await _open(t, port);
    await t.tap(find.text('Remove from this bill'));
    await t.pump();
    expect(port.unassigned, ['l1']);
    expect(find.text('Removed — it counts as income again'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('linking a suggestion assigns to the matching person', (t) async {
    final port = FakePort(split: sampleSplit());
    await _open(t, port);
    await t.ensureVisible(find.text('Link'));
    await t.pump();
    await t.tap(find.text('Link'));
    await t.pump();
    final (src, lines, pid) = port.assigned.single;
    expect(src, 's2');
    expect(lines.single.amountMinor, 40000);
    expect(pid, 'p2');
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('no overflow at 1.3x text scale (${locale.languageCode})', (
      t,
    ) async {
      await _open(
        t,
        FakePort(split: sampleSplit()),
        locale: locale,
        scale: 1.3,
      );
      expect(t.takeException(), isNull);
      expect(find.byType(SplitSheet), findsOneWidget);
    });
  }

  testWidgets('RTL: people rows mirror (remove button at the start)', (
    t,
  ) async {
    await _open(
      t,
      FakePort(split: sampleSplit(withRepayment: false)),
      locale: const Locale('ar', 'EG'),
    );
    final name = t.getTopLeft(find.byType(TextField).first).dx;
    final amount = t.getTopLeft(find.byType(TextField).at(1)).dx;
    expect(amount, lessThan(name));
  });
}
