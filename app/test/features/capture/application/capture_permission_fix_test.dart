// SMS-device: the Fix button of capture settings asks for the OS permission.
// Fails without the fix: CaptureSettingsScreen had no default onFix, so the
// button was not even shown.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/capture/application/capture_providers.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';
import 'package:zaghlol/features/capture/presentation/capture_settings_screen.dart';

import '../presentation/capture_ui_support.dart';
import '../support/capture_fakes.dart';

void main() {
  Future<FakeHost> pumpScreen(
    WidgetTester t, {
    ChannelState sms = ChannelState.offPermission,
    ChannelState notif = ChannelState.active,
  }) async {
    final h = FakeHost();
    await t.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // `host` builds the ProviderScope; wrap it so the capture host is fake.
    await t.pumpWidget(
      host(
        const CaptureSettingsScreen(),
        controls: FakeControls(),
        healthState: health(sms: sms, notif: notif),
        extraOverrides: [
          captureHostPortProvider.overrideWithValue(h),
          captureCoordinatorProvider.overrideWith((ref) async => null),
          inboxScanServiceProvider.overrideWith((ref) async => null),
        ],
      ),
    );
    await t.pumpAndSettle();
    return h;
  }

  AppLocalizations l10n(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold).first));

  testWidgets('SMS off: Fix is shown and asks for the SMS permission', (
    t,
  ) async {
    final h = await pumpScreen(t);
    expect(find.text(l10n(t).commonActionFix), findsOneWidget);
    await t.tap(find.text(l10n(t).commonActionFix));
    await t.pumpAndSettle();
    expect(h.log, contains('requestSms'));
  });

  testWidgets('notifications off: Fix opens the notification access list', (
    t,
  ) async {
    final h = await pumpScreen(
      t,
      sms: ChannelState.active,
      notif: ChannelState.offPermission,
    );
    await t.tap(find.text(l10n(t).commonActionFix));
    await t.pumpAndSettle();
    expect(h.notificationSettingsOpened, 1);
    expect(h.log, isNot(contains('requestSms')));
  });
}
