import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/ios_shortcut_checker.dart';

import '../../../support/ios_setup_host.dart';

Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(360, 640));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(w);
  await t.pumpAndSettle();
}

/// A message automation silent for 10 days.
ShortcutSetupReport silentMessage() => report(
  message: kNow - 10 * kDayMs,
  wallet: kNow - 3600000,
  baseline: kNow - 30 * kDayMs,
);

void main() {
  for (final lang in ['ar', 'en']) {
    group(lang, () {
      testWidgets('step 1: add shortcut calls the installer, no overflow', (
        t,
      ) async {
        var installs = 0;
        await pump(
          t,
          iosSetupHost(lang, scale: 1.3, install: () async => installs++),
        );
        expect(find.byKey(const ValueKey('ios-setup-add')), findsOneWidget);
        await tapKey(t, 'ios-setup-install');
        expect(installs, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets(
        'step 1: install failure shows the Shortcuts-missing banner',
        (t) async {
          await pump(
            t,
            iosSetupHost(lang, install: () async => throw Exception()),
          );
          await tapKey(t, 'ios-setup-install');
          expect(
            find.byKey(const ValueKey('ios-setup-install-failed')),
            findsOneWidget,
          );
        },
      );

      testWidgets('step 1: how it works expands to a placeholder, no image', (
        t,
      ) async {
        await pump(t, iosSetupHost(lang));
        await tapKey(t, 'ios-setup-how');
        expect(
          find.byKey(const ValueKey('ios-setup-how-placeholder')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('ios-setup-how-placeholder')),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
      });

      testWidgets('returning from Shortcuts runs the checker (step 2)', (
        t,
      ) async {
        await pump(t, iosSetupHost(lang));
        await tapKey(t, 'ios-setup-install');
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('ios-setup-check')), findsOneWidget);
      });

      testWidgets('step 2: all fine shows the all-good line, no Fix', (
        t,
      ) async {
        await pump(t, iosSetupHost(lang));
        await tapKey(t, 'ios-setup-to-check');
        expect(find.byKey(const ValueKey('ios-setup-count')), findsOneWidget);
        expect(find.byKey(const ValueKey('ios-setup-fix-smsAr')), findsNothing);
      });

      testWidgets('step 2: a silent automation gets Fix with steps', (t) async {
        await pump(t, iosSetupHost(lang, reportFn: silentMessage, scale: 1.3));
        await tapKey(t, 'ios-setup-to-check');
        expect(
          find.byKey(const ValueKey('ios-setup-fix-smsAr')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('ios-setup-fix-applePay')),
          findsNothing,
        );
        await tapKey(t, 'ios-setup-fix-smsAr');
        expect(t.takeException(), isNull);
      });

      testWidgets('step 2: Wallet never ran is not flagged (PO decision)', (
        t,
      ) async {
        await pump(
          t,
          iosSetupHost(
            lang,
            reportFn: () => report(
              message: kNow - 3600000,
              wallet: null,
              baseline: kNow - 30 * kDayMs,
            ),
          ),
        );
        await tapKey(t, 'ios-setup-to-check');
        expect(
          find.byKey(const ValueKey('ios-setup-fix-applePay')),
          findsNothing,
        );
      });

      testWidgets('step 2: Wallet silent after a capture is flagged', (
        t,
      ) async {
        await pump(
          t,
          iosSetupHost(
            lang,
            reportFn: () => report(
              message: kNow - 3600000,
              wallet: kNow - 10 * kDayMs,
              baseline: kNow - 30 * kDayMs,
            ),
          ),
        );
        await tapKey(t, 'ios-setup-to-check');
        expect(
          find.byKey(const ValueKey('ios-setup-fix-applePay')),
          findsOneWidget,
        );
      });

      testWidgets('step 2: cannot tell is a note, not a failure', (t) async {
        await pump(t, iosSetupHost(lang, reportFn: () => null));
        await tapKey(t, 'ios-setup-to-check');
        expect(find.byKey(const ValueKey('ios-setup-unknown')), findsOneWidget);
        expect(find.byKey(const ValueKey('ios-setup-row-smsAr')), findsNothing);
      });

      testWidgets('step 2: loading spinner, then Check again re-runs', (
        t,
      ) async {
        final c = Completer<ShortcutSetupReport?>();
        var calls = 0;
        await pump(
          t,
          iosSetupHost(
            lang,
            reportFn: () {
              calls++;
              return calls == 1 ? c.future : healthy();
            },
          ),
        );
        final go = find.byKey(const ValueKey('ios-setup-to-check'));
        await t.ensureVisible(go);
        await t.tap(go);
        await t.pump();
        await t.pump();
        expect(
          find.byKey(const ValueKey('ios-setup-checking')),
          findsOneWidget,
        );
        c.complete(silentMessage());
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('ios-setup-fix-smsAr')),
          findsOneWidget,
        );
        await tapKey(t, 'ios-setup-recheck');
        expect(calls, 2);
        expect(find.byKey(const ValueKey('ios-setup-fix-smsAr')), findsNothing);
      });

      testWidgets('step 3: say, type, online banks and done', (t) async {
        final hits = <String>[];
        var done = 0;
        await pump(
          t,
          iosSetupHost(
            lang,
            scale: 1.3,
            onSay: () => hits.add('say'),
            onType: () => hits.add('type'),
            onOnlineBanks: () => hits.add('banks'),
            onDone: () => done++,
          ),
        );
        await tapKey(t, 'ios-setup-to-check');
        await tapKey(t, 'ios-setup-to-first');
        await tapKey(t, 'ios-setup-say');
        await tapKey(t, 'ios-setup-type');
        await tapKey(t, 'ios-setup-online-banks');
        expect(hits, ['say', 'type', 'banks']);
        await tapKey(t, 'ios-setup-done');
        expect(done, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('skip at each step reports the shortcuts slug', (t) async {
        final slugs = <String>[];
        for (var step = 0; step < 3; step++) {
          await t.pumpWidget(const SizedBox());
          await pump(t, iosSetupHost(lang, onSkipped: slugs.add));
          if (step >= 1) await tapKey(t, 'ios-setup-to-check');
          if (step >= 2) await tapKey(t, 'ios-setup-to-first');
          await tapKey(t, 'ios-setup-skip');
        }
        expect(slugs, ['ios_shortcuts', 'ios_shortcuts', 'ios_shortcuts']);
      });
    });
  }

  testWidgets('RTL: the skip button sits at the end (left in ar)', (t) async {
    await pump(t, iosSetupHost('ar'));
    final skip = t.getTopLeft(find.byKey(const ValueKey('ios-setup-skip')));
    expect(skip.dx, lessThan(180));
  });
}
