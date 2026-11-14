import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/capture/presentation/capture_settings_screen.dart';

import 'capture_ui_support.dart';

AppLocalizations l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

Future<void> pump(
  WidgetTester t,
  FakeControls c, {
  Locale locale = const Locale('en'),
  double scale = 1.0,
  TargetPlatform platform = TargetPlatform.android,
  CaptureHealth? healthState,
  Object? error,
  bool loading = false,
  void Function(CaptureChannel)? onFix,
  bool settle = true,
}) async {
  await t.binding.setSurfaceSize(const Size(390, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    host(
      CaptureSettingsScreen(onFix: onFix, onRequestBank: () {}),
      controls: c,
      locale: locale,
      scale: scale,
      platform: platform,
      healthState: healthState,
      controlsError: error,
      loading: loading,
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
}

void main() {
  testWidgets('empty: all cards tracked', (t) async {
    await pump(t, FakeControls());
    expect(find.byKey(const Key('capture-not-tracked-empty')), findsOneWidget);
    expect(find.text(l10n(t).captureSettingsNotTrackedEmpty), findsOneWidget);
    expect(find.byKey(const Key('capture-rescan')), findsOneWidget);
  });

  testWidgets('loading shows a spinner', (t) async {
    await pump(t, FakeControls(), loading: true, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error: banner and Try again re-reads', (t) async {
    await pump(t, FakeControls(), error: StateError('x'));
    expect(find.byKey(const Key('capture-settings-error')), findsOneWidget);
    expect(find.text(l10n(t).commonActionTryAgain), findsOneWidget);
  });

  testWidgets('permission revoked: Off with Fix, calls onFix', (t) async {
    CaptureChannel? fixed;
    await pump(
      t,
      FakeControls(),
      healthState: health(sms: ChannelState.offPermission),
      onFix: (ch) => fixed = ch,
    );
    expect(find.text(l10n(t).captureSettingsOff), findsOneWidget);
    await t.tap(find.text(l10n(t).commonActionFix));
    expect(fixed, CaptureChannel.smsLive);
  });

  testWidgets('Play build without SMS: no SMS row', (t) async {
    await pump(
      t,
      FakeControls(),
      healthState: health(sms: ChannelState.unavailable),
    );
    expect(find.byKey(const Key('capture-sms')), findsNothing);
    expect(find.byKey(const Key('capture-notifications')), findsOneWidget);
  });

  testWidgets('iOS: Shortcuts row, checker unknown, no notifications, '
      'no re-scan', (t) async {
    await pump(t, FakeControls(), platform: TargetPlatform.iOS);
    expect(find.text(l10n(t).captureSettingsSmsIos), findsOneWidget);
    expect(find.text(l10n(t).captureSettingsUnknown), findsOneWidget);
    expect(find.byKey(const Key('capture-notifications')), findsNothing);
    expect(find.byKey(const Key('capture-rescan')), findsNothing);
  });

  testWidgets('unreadable messages banner offers the re-scan', (t) async {
    await pump(
      t,
      FakeControls(),
      healthState: health(issues: {CaptureIssue.unreadable}),
    );
    expect(find.text(l10n(t).captureSettingsUnreadable), findsOneWidget);
    await t.tap(find.text(l10n(t).captureRescanTitle));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('rescan-start')), findsOneWidget);
  });

  testWidgets('share how-to sheet', (t) async {
    await pump(t, FakeControls());
    await t.tap(find.byKey(const Key('capture-share')));
    await t.pumpAndSettle();
    expect(find.text(l10n(t).captureShareHowStep2), findsOneWidget);
  });

  testWidgets('ignored list: card and bank rows with channels', (t) async {
    final c = FakeControls(
      rules: [
        rule('1', 'cib', '9910', 'sms'),
        rule('2', 'cib', '9910', 'notification'),
        rule('3', 'revolut', null, 'notification'),
      ],
    );
    await pump(t, c);
    expect(find.text('CIB •9910'), findsOneWidget);
    expect(find.text('Revolut'), findsOneWidget);
    expect(find.text('SMS, Notifications off'), findsOneWidget);
    expect(find.text('Notifications off'), findsOneWidget);
  });

  testWidgets('AC2: one-tap Undo restores capture (rules removed) and the '
      'row disappears', (t) async {
    final c = FakeControls(
      rules: [
        rule('1', 'cib', '9910', 'notification'),
        rule('2', 'cib', '9910', 'applePay'),
      ],
    );
    await pump(t, c);
    await t.tap(find.text(l10n(t).commonActionUndo));
    await t.pumpAndSettle();
    expect(c.rules, isEmpty);
    expect(find.byKey(const Key('capture-not-tracked-empty')), findsOneWidget);
  });

  testWidgets('Undo of an SMS rule offers a re-scan; yes scans that bank', (
    t,
  ) async {
    final c = FakeControls(rules: [rule('1', 'cib', '9910', 'sms')]);
    await pump(t, c);
    await t.tap(find.text(l10n(t).commonActionUndo));
    await t.pumpAndSettle();
    expect(find.text(l10n(t).captureRescanOfferBody), findsOneWidget);
    await t.tap(find.byKey(const Key('rescan-offer-yes')));
    await t.pumpAndSettle();
    expect(c.lastScanInstitution, 'cib');
  });

  testWidgets('declining the re-scan offer scans nothing', (t) async {
    final c = FakeControls(rules: [rule('1', 'cib', '9910', 'sms')]);
    await pump(t, c);
    await t.tap(find.text(l10n(t).commonActionUndo));
    await t.pumpAndSettle();
    await t.tap(find.text(l10n(t).commonActionCancel));
    await t.pumpAndSettle();
    expect(c.calls.where((e) => e.startsWith('rescan')), isEmpty);
  });

  group('don\'t track sheet', () {
    Future<void> open(WidgetTester t, FakeControls c) async {
      await pump(t, c);
      await t.tap(find.byKey(const Key('capture-add-ignore')));
      await t.pumpAndSettle();
    }

    testWidgets('validation: bank, channel and last-4 errors', (t) async {
      await open(t, FakeControls());
      await t.enterText(find.byKey(const Key('ignore-last4')), '12');
      await t.tap(find.byKey(const Key('ignore-save')));
      await t.pumpAndSettle();
      final l = l10n(t);
      expect(find.text(l.captureIgnoreErrorBank), findsOneWidget);
      expect(find.text(l.captureIgnoreErrorChannel), findsOneWidget);
      expect(find.text(l.captureIgnoreErrorLast4), findsOneWidget);
    });

    testWidgets('saves a card rule per channel, snackbar Undo removes them', (
      t,
    ) async {
      final c = FakeControls();
      await open(t, c);
      await t.tap(find.byKey(const Key('ignore-bank')));
      await t.pumpAndSettle();
      await t.tap(find.text('CIB').last);
      await t.pumpAndSettle();
      // Arabic-Indic digits are normalised.
      await t.enterText(find.byKey(const Key('ignore-last4')), '٩٩١٠');
      await t.tap(find.byKey(const Key('ignore-ch-sms')));
      await t.tap(find.byKey(const Key('ignore-ch-notification')));
      await t.tap(find.byKey(const Key('ignore-save')));
      await t.pumpAndSettle();
      expect(c.calls, ['add:cib:9910:sms', 'add:cib:9910:notification']);
      expect(find.text(l10n(t).captureIgnoreSaved), findsOneWidget);
      await t.tap(find.text(l10n(t).commonActionUndo).last);
      await t.pumpAndSettle();
      expect(c.rules, isEmpty);
    });

    testWidgets('empty last-4 stops the whole bank', (t) async {
      final c = FakeControls();
      await open(t, c);
      await t.tap(find.byKey(const Key('ignore-bank')));
      await t.pumpAndSettle();
      await t.tap(find.text('Revolut').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ignore-ch-notification')));
      await t.tap(find.byKey(const Key('ignore-save')));
      await t.pumpAndSettle();
      expect(c.calls, ['add:revolut:null:notification']);
    });

    testWidgets('a failed save keeps the sheet and shows the error', (t) async {
      final c = FakeControls()..failAdd = true;
      await open(t, c);
      await t.tap(find.byKey(const Key('ignore-bank')));
      await t.pumpAndSettle();
      await t.tap(find.text('CIB').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ignore-ch-sms')));
      await t.tap(find.byKey(const Key('ignore-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('ignore-save-error')), findsOneWidget);
    });
  });

  group('re-scan', () {
    testWidgets('depth picker, running count, done', (t) async {
      final c = FakeControls();
      await pump(t, c);
      await t.tap(find.byKey(const Key('capture-rescan')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rescan-depth-12')));
      await t.pump();
      await t.tap(find.byKey(const Key('rescan-start')));
      await t.pump();
      expect(find.byKey(const Key('rescan-running')), findsOneWidget);
      c.progress.add(const ScanProgress(phase: ScanPhase.running, imported: 3));
      await t.pump();
      expect(find.text('Searching… 3 new found'), findsOneWidget);
      c.scanDone!.complete(
        const ScanProgress(phase: ScanPhase.done, imported: 4),
      );
      await t.pumpAndSettle();
      expect(find.text('Added 4 new transactions ✓'), findsOneWidget);
    });

    testWidgets('failed scan shows the error and can retry', (t) async {
      final c = FakeControls();
      await pump(t, c);
      await t.tap(find.byKey(const Key('capture-rescan')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rescan-start')));
      await t.pump();
      c.scanDone!.complete(
        const ScanProgress(phase: ScanPhase.failed, code: 'IO_ERROR'),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rescan-failed')), findsOneWidget);
      await t.tap(find.text(l10n(t).commonActionTryAgain));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rescan-start')), findsOneWidget);
    });
  });

  testWidgets('supported banks: search and empty result', (t) async {
    await pump(t, FakeControls());
    await t.tap(find.byKey(const Key('capture-banks')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('bank-cib')), findsOneWidget);
    await t.enterText(find.byKey(const Key('banks-search')), 'rev');
    await t.pump();
    expect(find.byKey(const Key('bank-cib')), findsNothing);
    expect(find.byKey(const Key('bank-revolut')), findsOneWidget);
    await t.enterText(find.byKey(const Key('banks-search')), 'zzz');
    await t.pump();
    expect(find.byKey(const Key('banks-empty')), findsOneWidget);
  });

  testWidgets('iOS supported banks show the per-bank iOS note', (t) async {
    await pump(t, FakeControls(), platform: TargetPlatform.iOS);
    await t.tap(find.byKey(const Key('capture-banks')));
    await t.pumpAndSettle();
    expect(find.text(l10n(t).captureBanksIosNote('CIB')), findsOneWidget);
  });

  testWidgets('Arabic RTL at 1.3x with rules: no overflow, mirrored', (
    t,
  ) async {
    final c = FakeControls(
      rules: [
        rule('1', 'cib', '9910', 'sms'),
        rule('2', 'cib', '9910', 'notification'),
      ],
    );
    await pump(
      t,
      c,
      locale: const Locale('ar', 'EG'),
      scale: 1.3,
      healthState: health(
        sms: ChannelState.offPermission,
        issues: {CaptureIssue.unreadable},
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.textContaining('٩٩١٠'), findsOneWidget);
    expect(
      Directionality.of(t.element(find.byKey(const Key('capture-sms')))),
      TextDirection.rtl,
    );
    await t.tap(find.byKey(const Key('capture-add-ignore')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
