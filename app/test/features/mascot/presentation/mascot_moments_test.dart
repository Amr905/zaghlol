import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/mascot/presentation/interim_mascot.dart';
import 'package:zaghlol/features/mascot/presentation/mascot_moments.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_mascot.dart';

Widget _wrap(
  Widget child, {
  required Locale locale,
  bool osReduce = false,
  double scale = 1,
}) {
  return ProviderScope(
    // These tests are about the interim animation; the bundled .riv is covered
    // by rive_mascot_test.dart.
    overrides: [zaghlolRivePresentProvider.overrideWith((ref) async => false)],
    child: MaterialApp(
      theme: ZaghlolTheme.light,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: osReduce,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    final l = locale.languageCode;
    for (final m in ZaghlolMoment.values) {
      testWidgets('$m animates the interim mascot ($l)', (tester) async {
        await tester.pumpWidget(
          _wrap(ZaghlolAvatar(moment: m, size: 96), locale: locale),
        );
        expect(find.byType(InterimMascot), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        // Reaches the end of a one-off; loops keep running.
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('reduce motion shows the still only ($l)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ZaghlolAvatar(moment: ZaghlolMoment.saved),
          locale: locale,
          osReduce: true,
        ),
      );
      expect(find.byType(InterimMascot), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsNothing);
    });

    testWidgets('tap bubble rotates copy-deck lines ($l)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ZaghlolTapBubble(message: 'base'),
          locale: locale,
          scale: 1.3,
        ),
      );
      final ctx = tester.element(find.byType(ZaghlolTapBubble));
      final loc = AppLocalizations.of(ctx);
      expect(find.text('base'), findsOneWidget);
      await tester.tap(find.byType(ZaghlolTapBubble));
      await tester.pump();
      expect(find.text(loc.mascotTapLine1), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(ZaghlolTapBubble));
      await tester.pump();
      expect(find.text(loc.mascotTapLine2), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  }

  test('loops only while real work runs; one-offs <= 3 s', () {
    final loops = ZaghlolMoment.values.where((m) => m.loops).toSet();
    expect(loops, {
      ZaghlolMoment.listening,
      ZaghlolMoment.thinking,
      ZaghlolMoment.scanning,
      ZaghlolMoment.counting,
    });
    for (final m in ZaghlolMoment.values.where((m) => !m.loops)) {
      expect(m.duration, lessThanOrEqualTo(const Duration(seconds: 3)));
    }
  });

  testWidgets('one-off stops animating (no pending frames)', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ZaghlolAvatar(moment: ZaghlolMoment.saved),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('loop stops when the widget leaves (work ends)', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const ZaghlolAvatar(moment: ZaghlolMoment.counting),
        locale: const Locale('en'),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      _wrap(const SizedBox(), locale: const Locale('en')),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('saved/tap line helpers use ARB copy', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(), locale: const Locale('ar')),
    );
    final loc = AppLocalizations.of(tester.element(find.byType(SizedBox)));
    expect(mascotSavedLine(loc, 0), loc.mascotSavedLine1);
    expect(mascotTapLine(loc, 10), loc.mascotTapLine1);
  });

  testWidgets('MascotRefresh shows the pull moment while refreshing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MascotRefresh(
          onRefresh: () => Future<void>.delayed(const Duration(seconds: 1)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 800)],
          ),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('mascot-pull')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('mascot-pull')), findsNothing);
  });
}
