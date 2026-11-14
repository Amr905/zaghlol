// T-066 (EC-14): the iOS "Shortcuts went quiet" nudge on Home and Settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/features/capture/application/ios_nudge_providers.dart';
import 'package:zaghlol/features/capture/application/ios_setup_providers.dart';
import 'package:zaghlol/features/capture/domain/ios_setup_checker.dart';
import 'package:zaghlol/features/capture/presentation/ios_setup_nudge.dart';
import 'package:zaghlol/features/settings/presentation/settings_main_screen.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart'
    show clockProvider;

import '../../settings/settings_harness.dart';

const _silent = IosSetupStatus(IosSetupState.silent, silentDays: 9);
const _ok = IosSetupStatus(IosSetupState.ok);
final _now = DateTime.utc(2026, 11, 14, 10);

void main() {
  for (final lang in ['ar', 'en']) {
    group('nudge ($lang)', () {
      late SettingsHarness h;
      setUp(() => h = SettingsHarness());
      tearDown(() => h.db.close());

      Future<void> pump(
        WidgetTester t, {
        IosSetupStatus status = _silent,
        int? snoozedUntil,
        VoidCallback? onCheck,
        bool dark = false,
        Widget? home,
      }) async {
        await t.pumpWidget(
          h.app(
            home ??
                Scaffold(
                  body: Padding(
                    padding: const EdgeInsetsDirectional.all(16),
                    child: IosSetupNudge(onCheck: onCheck),
                  ),
                ),
            locale: Locale(lang),
            dark: dark,
            scale: 1.3,
            overrides: [
              iosSetupStatusProvider.overrideWithValue(status),
              clockProvider.overrideWithValue(() => _now),
              iosNudgeSnoozedUntilProvider.overrideWith(
                (ref) => Stream.value(snoozedUntil),
              ),
            ],
          ),
        );
        await settle(t, height: 800);
      }

      AppLocalizations l(WidgetTester t) =>
          AppLocalizations.of(t.element(find.byType(Scaffold).first));

      testWidgets('silent: shows the days, the action and a 48dp dismiss', (
        t,
      ) async {
        var checked = 0;
        await pump(t, onCheck: () => checked++);
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsOneWidget);
        expect(find.textContaining(lang == 'ar' ? '٩' : '9'), findsWidgets);
        await t.tap(find.text(l(t).iosSetupNudgeCheck));
        expect(checked, 1);
        final dismiss = find.bySemanticsLabel(l(t).iosSetupNudgeSnoozeA11y);
        expect(dismiss, findsOneWidget);
        expect(t.getSize(dismiss).height, greaterThanOrEqualTo(48));
        expect(t.takeException(), isNull);
      });

      testWidgets('RTL: the dismiss button sits at the end', (t) async {
        await pump(t, onCheck: () {});
        final banner = t.getRect(find.byKey(const ValueKey('ios-setup-nudge')));
        final close = t.getCenter(find.byIcon(Icons.close));
        if (lang == 'ar') {
          expect(close.dx, lessThan(banner.center.dx));
        } else {
          expect(close.dx, greaterThan(banner.center.dx));
        }
      });

      testWidgets('dark theme builds without overflow', (t) async {
        await pump(t, dark: true, onCheck: () {});
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('not silent: nothing', (t) async {
        await pump(t, status: _ok);
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsNothing);
      });

      testWidgets('snoozed until later: nothing; after the snooze: back', (
        t,
      ) async {
        await pump(
          t,
          snoozedUntil: _now
              .add(const Duration(days: 3))
              .millisecondsSinceEpoch,
        );
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsNothing);
        await t.pumpWidget(const SizedBox());
        await pump(
          t,
          snoozedUntil: _now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsOneWidget);
      });

      testWidgets('dismiss writes a 7-day snooze', (t) async {
        await pump(t);
        await t.tap(find.byIcon(Icons.close));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        final stored = await t.runAsync(
          () => h.repo.get(Settings.iosNudgeSnoozedUntil),
        );
        expect(
          stored,
          _now.add(const Duration(days: 7)).millisecondsSinceEpoch,
        );
      });

      testWidgets('Settings shows the nudge above the rows and its action '
          'opens Capture', (t) async {
        var capture = 0;
        await pump(
          t,
          home: SettingsMainScreen(
            destinations: SettingsDestinations(onCapture: () => capture++),
          ),
        );
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsOneWidget);
        await t.tap(find.text(l(t).iosSetupNudgeCheck));
        expect(capture, 1);
      });

      testWidgets('Settings without a nudge has none', (t) async {
        await pump(t, status: _ok, home: const SettingsMainScreen());
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsNothing);
      });
    });
  }

  test('off iOS the checker is unknown, so there is no nudge', () {
    final c = ProviderContainer(
      overrides: [captureIosProvider.overrideWithValue(false)],
    );
    addTearDown(c.dispose);
    expect(c.read(iosNudgeDaysProvider), isNull);
  });
}
