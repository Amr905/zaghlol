import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/data/capture_host_port.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/onboarding/presentation/android_setup.dart';

class FakeHost implements CaptureHostPort {
  FakeHost({this.flavor = true, this.granted = false, this.grantOnAsk = true});
  bool flavor;
  bool granted;
  bool notif = false;
  final bool grantOnAsk;
  int asks = 0;
  int notifOpens = 0;

  @override
  Future<CaptureCapabilities> getCapabilities() async => CaptureCapabilities(
    smsGranted: granted,
    smsFlavor: flavor,
    notificationAccess: notif,
    postNotifications: true,
    sdkInt: 34,
  );

  @override
  Future<bool> requestSmsPermission() async {
    asks++;
    if (!flavor) throw StateError('NOT_AVAILABLE');
    granted = grantOnAsk;
    return granted;
  }

  @override
  Future<void> openNotificationAccessSettings() async => notifOpens++;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class FakeScan implements SetupScan {
  final ctl = StreamController<ScanProgress>.broadcast();
  ScanProgress cur = ScanProgress.initial;
  int starts = 0;
  @override
  ScanProgress get current => cur;
  @override
  Stream<ScanProgress> get progress => ctl.stream;
  @override
  Future<void> start() async => starts++;
}

Widget host(
  FakeHost h,
  FakeScan s,
  String lang, {
  double scale = 1,
  VoidCallback? onDone,
  void Function(String)? onSkipped,
}) => ProviderScope(
  overrides: [
    captureHostPortProvider.overrideWithValue(h),
    setupScanProvider.overrideWith((ref) async => s),
    languageProvider.overrideWith(
      (ref) => Stream.value(lang == 'ar' ? LanguagePref.ar : LanguagePref.en),
    ),
    digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
  ],
  child: MaterialApp(
    theme: ZaghlolTheme.light,
    locale: Locale(lang),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AndroidSetupScreen(
      onDone: onDone ?? () {},
      onSkipped: onSkipped,
      onShareHow: () {},
    ),
  ),
);

void main() {
  for (final lang in ['ar', 'en']) {
    group(lang, () {
      testWidgets('grant: one tap, scan starts, step 2 with progress', (
        tester,
      ) async {
        final h = FakeHost();
        final s = FakeScan();
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(host(h, s, lang, scale: 1.3));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('setup-sms')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('setup-sms-allow')),
        );
        await tester.tap(find.byKey(const ValueKey('setup-sms-allow')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(h.asks, 1);
        expect(s.starts, 1);
        expect(find.byKey(const ValueKey('setup-notif')), findsOneWidget);
        s.ctl.add(
          const ScanProgress(
            phase: ScanPhase.running,
            imported: 42,
            institutions: 3,
          ),
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('setup-scan')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('notification access: opens OS, rechecks on resume', (
        tester,
      ) async {
        final h = FakeHost(granted: true);
        await tester.pumpWidget(host(h, FakeScan(), lang));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const ValueKey('setup-notif')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('setup-notif-turn-on')),
        );
        await tester.tap(find.byKey(const ValueKey('setup-notif-turn-on')));
        await tester.pump();
        expect(h.notifOpens, 1);
        h.notif = true;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('setup-notif-granted')),
          findsOneWidget,
        );
      });

      testWidgets('denied -> degraded, ask again can recover', (tester) async {
        final h = FakeHost(grantOnAsk: false);
        await tester.pumpWidget(host(h, FakeScan(), lang));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('setup-sms-allow')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('setup-degraded')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('setup-degraded-retry')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('setup-sms')), findsOneWidget);
      });

      testWidgets('NoSms build: degraded at once, never asks', (tester) async {
        final h = FakeHost(flavor: false);
        await tester.pumpWidget(host(h, FakeScan(), lang));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('setup-degraded')), findsOneWidget);
        expect(find.byKey(const ValueKey('setup-sms-allow')), findsNothing);
        expect(
          find.byKey(const ValueKey('setup-degraded-retry')),
          findsNothing,
        );
        expect(h.asks, 0);
        await tester.tap(find.byKey(const ValueKey('setup-degraded-notif')));
        await tester.pump();
        expect(h.notifOpens, 1);
      });

      testWidgets('skip reports the step slug', (tester) async {
        String? slug;
        await tester.pumpWidget(
          host(FakeHost(), FakeScan(), lang, onSkipped: (s) => slug = s),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('setup-skip')));
        expect(slug, kSetupStepSms);
      });
    });
  }
}
