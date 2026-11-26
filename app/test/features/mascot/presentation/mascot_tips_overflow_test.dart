// T-277: every tip fits the Home bubble at 1.0x and 1.3x, RTL and LTR.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/application/mascot_tips.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moments.dart';

Widget _host(Locale locale, double scale, String message) => ProviderScope(
  child: MaterialApp(
    theme: ZaghlolTheme.light,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: ZaghlolTapBubble(message: message)),
    ),
  ),
);

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('all tips fit (${locale.languageCode}, ${scale}x)', (
        t,
      ) async {
        t.view.physicalSize = const Size(360, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final l = await AppLocalizations.delegate.load(locale);
        for (final tip in mascotTips) {
          final text = tip.text(l);
          await t.pumpWidget(_host(locale, scale, text));
          await t.pump();
          expect(t.takeException(), isNull, reason: text);
          expect(
            t.getSize(find.byType(ZaghlolTapBubble)).height,
            lessThan(300),
            reason: text,
          );
          expect(text.length, lessThanOrEqualTo(110), reason: 'keep it short');
        }
      });
    }
  }
}
