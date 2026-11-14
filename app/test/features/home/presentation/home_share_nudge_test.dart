// T-117 share entry and T-066 nudge on Home.

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/capture/application/ios_nudge_providers.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';

import 'home_harness.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    final locale = Locale(lang);
    group('Home ($lang)', () {
      testWidgets('share icon opens S-73 and is a 48dp target', (t) async {
        var opened = 0;
        await pumpHome(
          t,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(),
          textScale: 1.3,
          actions: HomeActions(openShare: () => opened++),
        );
        final icon = find.byKey(const ValueKey('home-share'));
        expect(icon, findsOneWidget);
        expect(find.byIcon(Icons.ios_share), findsOneWidget);
        final l = AppLocalizations.of(t.element(icon));
        expect(find.byTooltip(l.shareStudioShare), findsOneWidget);
        expect(t.getSize(icon).height, greaterThanOrEqualTo(48));
        await t.tap(icon);
        expect(opened, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('iOS uses the Cupertino share glyph', (t) async {
        await pumpHome(
          t,
          locale: locale,
          platform: TargetPlatform.iOS,
          value: model(),
          actions: HomeActions(openShare: () {}),
        );
        expect(find.byIcon(CupertinoIcons.share), findsOneWidget);
      });

      testWidgets('no share callback: no share icon', (t) async {
        await pumpHome(
          t,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(),
        );
        expect(find.byKey(const ValueKey('home-share')), findsNothing);
      });

      testWidgets('nudge shows when silent and opens Capture', (t) async {
        var capture = 0;
        await pumpHome(
          t,
          locale: locale,
          platform: TargetPlatform.iOS,
          value: model(),
          textScale: 1.3,
          actions: HomeActions(openCaptureSettings: () => capture++),
          extraOverrides: [iosNudgeDaysProvider.overrideWithValue(9)],
        );
        final nudge = find.byKey(const ValueKey('ios-setup-nudge'));
        expect(nudge, findsOneWidget);
        final l = AppLocalizations.of(t.element(nudge));
        await t.ensureVisible(find.text(l.iosSetupNudgeCheck));
        await t.tap(find.text(l.iosSetupNudgeCheck));
        expect(capture, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('no nudge when the checker is quiet', (t) async {
        await pumpHome(
          t,
          locale: locale,
          platform: TargetPlatform.iOS,
          value: model(),
        );
        expect(find.byKey(const ValueKey('ios-setup-nudge')), findsNothing);
      });
    });
  }
}
