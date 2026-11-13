import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/capture/presentation/card_capture_sheet.dart';

import 'capture_ui_support.dart';

Widget sheet() => const Scaffold(
  body: SingleChildScrollView(
    child: CardCaptureControls(
      institutionCode: 'cib',
      last4: '1234',
      cardName: 'CIB 1234',
    ),
  ),
);

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

Future<void> pump(
  WidgetTester t,
  FakeControls c, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    host(
      sheet(),
      controls: c,
      locale: locale,
      scale: scale,
      platform: platform,
    ),
  );
  await t.pumpAndSettle();
}

bool isOn(WidgetTester t, String ch) =>
    t.widget<SwitchListTile>(find.byKey(Key('capture-card-$ch'))).value;

void main() {
  testWidgets('both switches on when no rule exists; Android channels', (
    t,
  ) async {
    await pump(t, FakeControls());
    expect(isOn(t, 'sms'), isTrue);
    expect(isOn(t, 'notification'), isTrue);
    expect(find.byKey(const Key('capture-card-apple_pay')), findsNothing);
    expect(find.text(l10n(t).captureCardControlsInfo), findsOneWidget);
  });

  testWidgets('iOS shows SMS and Apple Pay only', (t) async {
    await pump(t, FakeControls(), platform: TargetPlatform.iOS);
    expect(find.byKey(const Key('capture-card-apple_pay')), findsOneWidget);
    expect(find.byKey(const Key('capture-card-notification')), findsNothing);
    expect(find.text(l10n(t).captureCardControlsSmsIos), findsOneWidget);
  });

  testWidgets('AC1: turning one channel off adds the rule at once, on '
      'removes it (Undo restores capture)', (t) async {
    final c = FakeControls();
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-sms')));
    await t.pumpAndSettle();
    expect(c.calls, ['add:cib:1234:sms']);
    expect(isOn(t, 'sms'), isFalse);
    expect(find.byType(AlertDialog), findsNothing);
    await t.tap(find.byKey(const Key('capture-card-sms')));
    await t.pumpAndSettle();
    expect(c.calls.last, startsWith('remove:'));
    expect(c.rules, isEmpty);
    expect(isOn(t, 'sms'), isTrue);
  });

  testWidgets('last channel off asks; Keep is the default; snackbar Undo '
      'restores the switches', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')])
      ..previewCounts = {'sms': 100, 'notification': 114};
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    expect(find.text(l10n(t).captureStopTrackingTitle('CIB 1234')), findsOne);
    expect(find.textContaining('214'), findsOneWidget);
    await t.tap(find.byKey(const Key('stop-confirm')));
    await t.pumpAndSettle();
    expect(c.rules.map((r) => r.channel).toSet(), {'sms', 'notification'});
    expect(c.lastDeleteIds, isNull);
    expect(find.text(l10n(t).captureStopTrackingDone('CIB 1234')), findsOne);
    await t.tap(find.text(l10n(t).commonActionUndo));
    await t.pumpAndSettle();
    // Only the rule this action created is undone.
    expect(c.rules.map((r) => r.channel), ['sms']);
    expect(isOn(t, 'notification'), isTrue);
  });

  testWidgets('cancel leaves everything on', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')]);
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n(t).commonActionCancel));
    await t.pumpAndSettle();
    expect(c.calls, isEmpty);
    expect(isOn(t, 'notification'), isTrue);
  });

  testWidgets('delete asks twice and deletes exactly the previewed ids', (
    t,
  ) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')])
      ..previewCounts = {'sms': 2, 'notification': 1};
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stop-delete')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stop-confirm')));
    await t.pumpAndSettle();
    expect(c.calls, isEmpty, reason: 'second confirmation pending');
    expect(find.text(l10n(t).captureStopTrackingDeleteBody), findsOneWidget);
    await t.tap(find.byKey(const Key('stop-delete-confirm')));
    await t.pumpAndSettle();
    expect(c.lastDeleteIds, {'sms-0', 'sms-1', 'notification-0'});
  });

  testWidgets('declining the second confirmation changes nothing', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')])
      ..previewCounts = {'notification': 3};
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('stop-delete')));
    await t.tap(find.byKey(const Key('stop-confirm')));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n(t).commonActionCancel));
    await t.pumpAndSettle();
    expect(c.calls, isEmpty);
  });

  testWidgets('no transactions: the delete option is hidden', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')]);
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('stop-delete')), findsNothing);
  });

  testWidgets('institution-level rule: switch shown off and locked', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', null, 'sms')]);
    await pump(t, c);
    final sw = t.widget<SwitchListTile>(
      find.byKey(const Key('capture-card-sms')),
    );
    expect(sw.value, isFalse);
    expect(sw.onChanged, isNull);
  });

  testWidgets('a failed write shows the save error and keeps the switch', (
    t,
  ) async {
    final c = FakeControls()..failAdd = true;
    await pump(t, c);
    await t.tap(find.byKey(const Key('capture-card-sms')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('capture-card-error')), findsOneWidget);
    expect(isOn(t, 'sms'), isTrue);
  });

  testWidgets('Arabic RTL at 1.3x: no overflow, Arabic copy', (t) async {
    final c = FakeControls(rules: [rule('r1', 'cib', '1234', 'sms')])
      ..previewCounts = {'notification': 3};
    await pump(t, c, locale: const Locale('ar', 'EG'), scale: 1.3);
    expect(t.takeException(), isNull);
    expect(
      Directionality.of(t.element(find.byType(SwitchListTile).first)),
      TextDirection.rtl,
    );
    await t.tap(find.byKey(const Key('capture-card-notification')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.textContaining('٣'), findsWidgets);
  });
}
