// T-238 / E2E-10: language (ar <-> en) and digits (Arabic-Indic <-> Western)
// on every tab and the main sub-screens, in the real app on the emulator.
// The first switch (English -> Arabic, then Arabic-Indic digits) goes through
// the Preferences screen; the other combinations through the settings
// repository (the app's own provider) to keep the run short. Per screen: the
// text direction (RTL for Arabic, LTR for English), and any FlutterError
// (overflows included) fails the test. On the transactions list a known
// amount (EGP 1,234.50) must show in the chosen digits and no digit of the
// other kind may show. Digit leaks on other screens are listed (screen name
// and count only), not failed. Synthetic data; amounts never printed.
//
// Run: flutter test integration_test/e2e_locale_device_test.dart
//      --flavor devSms -d <device> --no-uninstall

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol/app/app_navigation.dart' show openSettings;
import 'package:zaghlol/core/routing/app_router.dart' show rootNavigatorKey;
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/main.dart' as app;

import 'support/e2e_common.dart';

final _western = RegExp('[0-9]');
final _indic = RegExp('[٠-٩]');
// 1,234.50 with any grouping separator, in each digit set.
final _amountWestern = RegExp('1[,٬، ]?234');
final _amountIndic = RegExp('١[,٬، ]?٢٣٤');

void main() {
  final e = E2e('E2E10');

  testWidgets('language and digits on every tab and sub-screen', (t) async {
    final semantics = t.ensureSemantics();
    addTearDown(semantics.dispose);
    await e.seedReturningUser();
    e.captureFlutterErrors();

    await app.main();
    e.say('MAIN_RETURNED');
    await e.waitFor(t, find.text('Home'), what: 'Home');
    await e.settle(t, 2000);
    await e.addTransactions([123450]);
    await e.settle(t, 800);

    List<String> texts() => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        w.data ?? w.textSpan?.toPlainText() ?? '',
    ];

    Future<void> go(String route) async {
      rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      await e.settle(t, 300);
      GoRouter.of(rootNavigatorKey.currentContext!).go(route);
      await e.settle(t, 1800);
    }

    // The screen on show: direction, and digit leaks (names and counts only).
    void inspect(String screen, {required bool rtl, required bool indic}) {
      final dir = Directionality.of(rootNavigatorKey.currentContext!);
      e.check(
        dir == (rtl ? TextDirection.rtl : TextDirection.ltr),
        '$screen: direction is $dir, wanted ${rtl ? 'rtl' : 'ltr'}',
      );
      final all = texts();
      final leaks = all.where((s) => (indic ? _western : _indic).hasMatch(s));
      if (leaks.isNotEmpty) {
        e.say(
          'DIGIT_LEAK $screen ${indic ? 'western-in-indic' : 'indic-in-western'} count=${leaks.length}',
        );
      }
    }

    Future<void> visitAll(
      String combo, {
      required bool rtl,
      required bool indic,
    }) async {
      for (final r in [
        ('home', AppRoutes.home),
        ('money', AppRoutes.money),
        ('insights', AppRoutes.insights),
        ('zaghlol', AppRoutes.zaghlol),
      ]) {
        await go(r.$2);
        inspect('$combo/${r.$1}', rtl: rtl, indic: indic);
        await e.shot(t, '$combo-${r.$1}');
      }
      // The transactions list holds the known amount.
      await go(AppRoutes.transactions);
      inspect('$combo/transactions', rtl: rtl, indic: indic);
      final all = texts();
      e.check(
        all.any((s) => (indic ? _amountIndic : _amountWestern).hasMatch(s)),
        '$combo/transactions: the known amount shows in ${indic ? 'Arabic-Indic' : 'Western'} digits',
      );
      e.check(
        !all.any((s) => (indic ? _western : _indic).hasMatch(s)),
        '$combo/transactions: no ${indic ? 'Western' : 'Arabic-Indic'} digit on the list',
      );
      await e.shot(t, '$combo-transactions');
      await go(AppRoutes.review);
      inspect('$combo/review', rtl: rtl, indic: indic);
      await e.shot(t, '$combo-review');
      // Settings and Preferences.
      await go(AppRoutes.home);
      unawaited(openSettings(rootNavigatorKey.currentContext!));
      await e.settle(t, 1800);
      inspect('$combo/settings', rtl: rtl, indic: indic);
      await e.shot(t, '$combo-settings');
      final prefs = find.text(rtl ? 'التفضيلات' : 'Preferences');
      await e.waitFor(t, prefs, what: '$combo Preferences row');
      await t.tap(prefs.first);
      await e.settle(t, 1500);
      inspect('$combo/preferences', rtl: rtl, indic: indic);
      await e.shot(t, '$combo-preferences');
      await go(AppRoutes.home);
    }

    // ---- UI: English/Western -> Arabic -> Arabic-Indic digits.
    await go(AppRoutes.home);
    unawaited(openSettings(rootNavigatorKey.currentContext!));
    await e.waitFor(t, find.text('Preferences'), what: 'Settings rows');
    await t.tap(find.text('Preferences').first);
    await e.waitFor(t, find.text('Language'), what: 'the Preferences screen');
    await e.settle(t, 800);
    await t.tap(find.text('\u0627\u0644\u0639\u0631\u0628\u064a\u0629').first);
    await e.settle(t, 2000);
    e.check(
      Directionality.of(rootNavigatorKey.currentContext!) == TextDirection.rtl,
      'tapping the Arabic segment turns the app RTL',
    );
    await e.shot(t, 'switch-ar');
    // Arabic UI: the digits segment "Arabic-Indic" is labelled in Arabic.
    final indicSeg = find.text('\u0639\u0631\u0628\u064a');
    await e.waitFor(t, indicSeg, what: 'the Arabic-Indic digits segment');
    await t.tap(indicSeg.first);
    await e.settle(t, 1500);
    await e.shot(t, 'switch-digits');
    await go(AppRoutes.home);

    await visitAll('ar-indic', rtl: true, indic: true);

    // ---- the other combinations through the app's own settings provider.
    Future<void> setPrefs(LanguagePref l, DigitsPref d) async {
      final repo = await e.container().read(settingsRepositoryProvider.future);
      await repo.set(Settings.language, l);
      await repo.set(Settings.digits, d);
      await e.settle(t, 2000);
    }

    await setPrefs(LanguagePref.ar, DigitsPref.western);
    await visitAll('ar-western', rtl: true, indic: false);
    await setPrefs(LanguagePref.en, DigitsPref.western);
    await visitAll('en-western', rtl: false, indic: false);
    await setPrefs(LanguagePref.en, DigitsPref.arabicIndic);
    await visitAll('en-indic', rtl: false, indic: true);

    e.finish();
  });
}
