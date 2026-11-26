import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_empty_state.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import '../../support/golden_matrix.dart';

Widget _host(GoldenVariant v, Widget child) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: v.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ZaghlolTheme.light,
    home: Scaffold(body: child),
  ),
);

void main() {
  for (final v in goldenVariants.where((v) => !v.dark)) {
    testWidgets('shows sleeping bird, text and action ${v.name}', (t) async {
      var taps = 0;
      await t.pumpWidget(
        _host(
          v,
          ZEmptyState(
            title: v.isRtl ? 'مفيش فواتير لسه' : 'No bills yet',
            body: 'body',
            actionLabel: 'add',
            onAction: () => taps++,
          ),
        ),
      );
      final bird = t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar));
      expect(bird.moment, ZaghlolMoment.sleep);
      expect(bird.size, 120);
      expect(find.text('body'), findsOneWidget);
      await t.tap(find.text('add'));
      expect(taps, 1);
    });

    testWidgets('no action when none given ${v.name}', (t) async {
      await t.pumpWidget(_host(v, const ZEmptyState(title: 'x')));
      expect(find.byType(ZaghlolAvatar), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  }
}
