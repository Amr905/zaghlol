import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/presentation/notifications_settings_screen.dart';

import '../../settings/settings_harness.dart';

class PermStub implements NotificationPermissionPort {
  PermStub({this.allowed = true, this.grant = true});
  bool allowed;
  bool grant;
  int requests = 0;

  @override
  Future<bool> isAllowed() async => allowed;

  @override
  Future<bool> request() async {
    requests++;
    allowed = grant;
    return grant;
  }
}

Future<(SettingsHarness, PermStub, List<int>)> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
  PermStub? perm,
  bool allOff = false,
}) async {
  final h = SettingsHarness();
  addTearDown(h.db.close);
  if (allOff) {
    await tester.runAsync(() async {
      for (final ty in NotificationType.values) {
        await h.repo.set(ty.toggle, false);
      }
    });
  }
  final p = perm ?? PermStub();
  final opened = <int>[];
  await tester.pumpWidget(
    h.app(
      const NotificationsSettingsScreen(),
      locale: locale,
      dark: dark,
      scale: scale,
      overrides: [
        notificationPermissionProvider.overrideWithValue(p),
        openNotificationSettingsProvider.overrideWithValue(
          () async => opened.add(1),
        ),
      ],
    ),
  );
  await settle(tester);
  return (h, p, opened);
}

void main() {
  for (final loc in const [Locale('en'), Locale('ar', 'EG')]) {
    final lang = loc.languageCode;
    for (final scale in const [1.0, 1.3]) {
      testWidgets('lists every toggle, no overflow ($lang x$scale)', (
        tester,
      ) async {
        await _pump(tester, locale: loc, scale: scale);
        final t = AppLocalizations.of(
          tester.element(find.byType(NotificationsSettingsScreen)),
        );
        for (final s in [
          t.notificationsSettingsBudget,
          t.notificationsSettingsSpikes,
          t.notificationsSettingsDues,
          t.notificationsSettingsDuplicates,
          t.notificationsSettingsRenewals,
          t.notificationsSettingsBackup,
          t.notificationsSettingsWeekly,
          t.notificationsSettingsQuiet,
          t.notificationsSettingsHideAmounts,
        ]) {
          expect(find.text(s), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        expect(
          Directionality.of(tester.element(find.byType(Scaffold))),
          lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }
  }

  testWidgets('a toggle writes the type setting', (tester) async {
    final (h, _, _) = await _pump(tester);
    final t = AppLocalizations.of(
      tester.element(find.byType(NotificationsSettingsScreen)),
    );
    await tester.tap(find.text(t.notificationsSettingsSpikes));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(
      await tester.runAsync(
        () => h.repo.get(NotificationType.spendingSpike.toggle),
      ),
      isFalse,
    );
  });

  testWidgets('first toggle on asks for the permission', (tester) async {
    final (_, perm, _) = await _pump(tester, allOff: true);
    final t = AppLocalizations.of(
      tester.element(find.byType(NotificationsSettingsScreen)),
    );
    expect(perm.requests, 0);
    await tester.tap(find.text(t.notificationsSettingsBudget));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(perm.requests, 1);
    await tester.tap(find.text(t.notificationsSettingsSpikes));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(perm.requests, 1);
  });

  testWidgets('permission denied shows the OS-off state and opens settings', (
    tester,
  ) async {
    final (_, perm, opened) = await _pump(
      tester,
      perm: PermStub(allowed: false, grant: false),
    );
    final t = AppLocalizations.of(
      tester.element(find.byType(NotificationsSettingsScreen)),
    );
    expect(find.text(t.notificationsSettingsOsOffTitle), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notif-open-settings')));
    await tester.pump();
    expect(opened, [1]);
    expect(perm.requests, 0);
  });

  testWidgets('turning a type on while the OS is off asks and keeps banner', (
    tester,
  ) async {
    final (_, perm, _) = await _pump(
      tester,
      perm: PermStub(allowed: false, grant: false),
    );
    final t = AppLocalizations.of(
      tester.element(find.byType(NotificationsSettingsScreen)),
    );
    // Off then on again.
    await tester.tap(find.text(t.notificationsSettingsBudget));
    await tester.pump();
    await tester.tap(find.text(t.notificationsSettingsBudget));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(perm.requests, greaterThan(0));
    expect(find.text(t.notificationsSettingsOsOffTitle), findsOneWidget);
  });

  testWidgets('quiet hours reveal the range; hide amounts writes', (
    tester,
  ) async {
    final (h, _, _) = await _pump(tester);
    expect(find.byKey(const ValueKey('notif-quiet-start')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notif-quiet')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notif-quiet-start')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('notif-quiet')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notif-quiet-start')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notif-hide-amounts')));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(
      await tester.runAsync(() => h.repo.get(Settings.quietHoursEnabled)),
      isTrue,
    );
    expect(
      await tester.runAsync(
        () => h.repo.get(Settings.hideAmountsNotifications),
      ),
      isTrue,
    );
  });

  testWidgets('tap targets and labels meet the guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, perm: PermStub(allowed: false));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
