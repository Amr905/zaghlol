import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/transfers/presentation/link_transfer_sheet.dart';
import 'package:zaghlol/features/transfers/presentation/transfers_format.dart';
import 'package:zaghlol/features/transfers/presentation/transfers_port.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

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
  open: (c) => showLinkTransferSheet(c, 'out1'),
);

void main() {
  setUpAll(initDateFormatting);

  testWidgets('candidates: gap labels, cross-currency implied rate', (t) async {
    await _open(t, FakePort(linkData: sampleLink()));
    expect(find.text('Link my own transfer'), findsOneWidget);
    expect(find.text('Pick the matching transaction'), findsOneWidget);
    expect(find.text('2 min later'), findsOneWidget);
    expect(find.text('1 day later'), findsOneWidget);
    // 1,000.00 EGP / 20.05 USD = 49.87 EGP per USD.
    expect(textHas('Implied rate ≈ EGP 49.88 per USD'), findsOneWidget);
  });

  testWidgets('link pairs out leg first, then in leg; Undo unlinks', (t) async {
    final port = FakePort(linkData: sampleLink());
    await _open(t, port);
    await t.tap(find.text('Link').last);
    await t.pumpAndSettle();
    expect(port.linked, [('out1', 'in1')]);
    expect(find.text('Linked ✓ Not counted as spending'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pump();
    expect(port.unlinked, ['out1']);
  });

  testWidgets('picking the cross-currency candidate links that one', (t) async {
    final port = FakePort(linkData: sampleLink());
    await _open(t, port);
    await t.tap(textHas('Wise'));
    await t.pump();
    await t.tap(find.text('Link').last);
    await t.pumpAndSettle();
    expect(port.linked, [('out1', 'in2')]);
  });

  testWidgets('same currency with different amounts is blocked', (t) async {
    final d = sampleLink();
    final port = FakePort(
      linkData: LinkData(
        id: d.id,
        amount: e(99000),
        accountLabel: d.accountLabel,
        when: d.when,
        isOut: true,
        candidates: [d.candidates.first],
      ),
    );
    await _open(t, port);
    expect(find.text('Amounts must match'), findsOneWidget);
    await t.tap(find.text('Link').last);
    await t.pump();
    expect(port.linked, isEmpty);
  });

  testWidgets('failure shows a message and keeps the sheet', (t) async {
    final port = FakePort(linkData: sampleLink())..failWith = StateError('x');
    await _open(t, port);
    await t.tap(find.text('Link').last);
    await t.pumpAndSettle();
    expect(
      find.text("Couldn't save. Try again — what you entered is still here."),
      findsOneWidget,
    );
  });

  testWidgets('empty: explanation; mark-anyway only when supported', (t) async {
    await _open(t, FakePort(linkData: sampleLink(empty: true)));
    expect(find.text('No matching transaction found'), findsOneWidget);
    expect(find.text('Mark as my transfer'), findsNothing);
  });

  testWidgets('empty with mark-anyway supported shows the action', (t) async {
    await _open(t, FakePort(linkData: sampleLink(empty: true), markable: true));
    expect(find.text('Mark as my transfer'), findsOneWidget);
  });

  testWidgets('error state', (t) async {
    await _open(t, FakePort()..loadFails = true);
    expect(find.text('Try again'), findsOneWidget);
  });

  for (final locale in [const Locale('ar', 'EG'), const Locale('en')]) {
    testWidgets('no overflow at 1.3x (${locale.languageCode})', (t) async {
      await _open(
        t,
        FakePort(linkData: sampleLink()),
        locale: locale,
        scale: 1.3,
      );
      expect(t.takeException(), isNull);
    });
  }

  group('impliedRate', () {
    test('larger currency per one of the smaller, exact integers', () {
      final r = impliedRate(e(100000), u(2005))!;
      expect(r.per, usd);
      expect(r.rate, e(4988));
      // Same answer whichever side is the source.
      final r2 = impliedRate(u(2005), e(100000))!;
      expect(r2.rate, e(4988));
    });
    test('three-decimal currency', () {
      final kwd = Currency.of('KWD');
      final r = impliedRate(e(15000), Money(kwd, 1000))!;
      expect(r.per, kwd);
      expect(r.rate, e(15000));
    });
    test('same currency or zero gives null', () {
      expect(impliedRate(e(1), e(2)), isNull);
      expect(impliedRate(e(0), u(2)), isNull);
    });
  });
}
