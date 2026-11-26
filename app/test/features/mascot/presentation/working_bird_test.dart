// T-297: the working bird loops only while busy, settles when done, plays
// oops on failure, and shows the still pose under reduce motion.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/working_bird.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

Widget _app(
  Locale locale,
  Widget child, {
  bool reduce = false,
  List<ZaghlolMoment>? seen,
}) => ProviderScope(
  overrides: [
    zaghlolArtboardProvider.overrideWithValue((context, moment, talk, size) {
      seen?.add(moment);
      return Text('bird ${moment.name}');
    }),
  ],
  child: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: MaterialApp(
      theme: ZaghlolTheme.light,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  ),
);

void main() {
  for (final l in ['ar', 'en']) {
    testWidgets('loops while busy, stops when done, oops on error ($l)', (
      t,
    ) async {
      final locale = Locale(l);
      await t.pumpWidget(_app(locale, const WorkingBird(busy: true)));
      expect(find.text('bird scanning'), findsOneWidget);
      await t.pumpWidget(
        _app(
          locale,
          const WorkingBird(busy: true, moment: ZaghlolMoment.counting),
        ),
      );
      expect(find.text('bird counting'), findsOneWidget);
      await t.pumpWidget(_app(locale, const WorkingBird(busy: false)));
      expect(find.text('bird tourGuide'), findsOneWidget);
      await t.pumpWidget(
        _app(locale, const WorkingBird(busy: false, failed: true)),
      );
      expect(find.text('bird oops'), findsOneWidget);
    });

    testWidgets('reduce motion shows the still pose ($l)', (t) async {
      await t.pumpWidget(
        _app(Locale(l), const WorkingBird(busy: true), reduce: true),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('bird scanning'), findsNothing);
    });
  }
}
