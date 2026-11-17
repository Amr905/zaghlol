import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/ui/shell/add_sheet.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart';

import 'shell_harness.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

String _location(dynamic router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('FU-125: an unknown location falls back to the Home root', (
    tester,
  ) async {
    final router = await pumpShell(tester);
    router.go('/no/such/place?secret=1');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('counter-home')), findsOneWidget);
  });

  group('platform variant', () {
    testWidgets('Android: M3 NavigationBar and FAB at bottom-end (en)', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(ZAddButton), findsOneWidget);
      final fab = tester.getCenter(find.byType(ZAddButton));
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(fab.dx, greaterThan(size.width / 2));
    });

    for (final (name, locale, leftSide) in [
      ('en', _en, false),
      ('ar', _ar, true),
    ]) {
      testWidgets('Android ($name): FAB floats above the bar at bottom-end', (
        tester,
      ) async {
        await pumpShell(tester, locale: locale);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        final fab = tester.getRect(find.byType(ZAddButton));
        final bar = tester.getRect(find.byType(NavigationBar));
        expect(fab.width, closeTo(56, 0.01));
        expect(fab.height, closeTo(56, 0.01));
        expect(fab.bottom, lessThanOrEqualTo(bar.top));
        expect(bar.top - fab.bottom, lessThan(32));
        expect(fab.center.dx < size.width / 2, leftSide);
        expect(leftSide ? fab.left : size.width - fab.right, closeTo(16, 0.01));
      });
    }

    testWidgets('Android RTL: FAB bottom-left, first tab on the right', (
      tester,
    ) async {
      await pumpShell(tester, locale: _ar);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getCenter(find.byType(ZAddButton)).dx,
        lessThan(size.width / 2),
      );
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(
        tester.getCenter(find.text('الرئيسية')).dx,
        greaterThan(tester.getCenter(find.text('زغلول')).dx),
      );
    });

    for (final (name, locale) in [('en', _en), ('ar', _ar)]) {
      testWidgets('iOS ($name): glass bar and detached Add, no NavigationBar', (
        tester,
      ) async {
        await pumpShell(tester, locale: locale, platform: TargetPlatform.iOS);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        final add = tester.getCenter(find.byIcon(Icons.add));
        final home = tester.getCenter(find.byIcon(Icons.home_outlined));
        final rtl = locale == _ar;
        // Add sits at the trailing end: left in Arabic, right in English.
        expect(add.dx > home.dx, !rtl);
      });
    }
  });

  group('tabs', () {
    testWidgets('keep their state when switching (ar)', (tester) async {
      await pumpShell(tester, locale: _ar);
      await tester.tap(find.byKey(const ValueKey('counter-home')));
      await tester.tap(find.byKey(const ValueKey('counter-home')));
      await tester.pump();
      expect(find.text('home:2'), findsOneWidget);

      await tester.tap(find.text('فلوسي'));
      await tester.pumpAndSettle();
      expect(find.text('money:0'), findsOneWidget);

      await tester.tap(find.text('الرئيسية'));
      await tester.pumpAndSettle();
      expect(find.text('home:2'), findsOneWidget);
    });

    testWidgets('keep their state on iOS glass bar too', (tester) async {
      await pumpShell(tester, platform: TargetPlatform.iOS);
      await tester.tap(find.byKey(const ValueKey('counter-home')));
      await tester.pump();
      await tester.tap(find.text('Insights'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('home:1'), findsOneWidget);
    });

    testWidgets('re-tapping the active tab pops it to its root', (
      tester,
    ) async {
      final router = await pumpShell(tester);
      router.go(AppRoutes.review);
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.review);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.home);
    });

    testWidgets('system back on another tab goes Home, then may exit', (
      tester,
    ) async {
      final router = await pumpShell(tester);
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.money);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.home);
    });

    testWidgets('tab labels follow the locale', (tester) async {
      await pumpShell(tester, locale: _ar);
      for (final label in ['الرئيسية', 'الحسبة', 'فلوسي', 'زغلول']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('Add button and sheet', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('opens the Add sheet over the current tab ($platform, ar)', (
        tester,
      ) async {
        await pumpShell(tester, locale: _ar, platform: platform);
        await tester.tap(find.text('الحسبة'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('سجّل بسرعة'));
        await tester.pumpAndSettle();
        expect(find.byType(AddSheet), findsOneWidget);
        expect(find.text('تحب تسجل إيه؟'), findsOneWidget);

        // Back closes the sheet and returns to the same tab.
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(AddSheet), findsNothing);
        expect(find.text('insights:0'), findsOneWidget);
      });
    }

    testWidgets('sheet entries are 48dp targets with labels (en)', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.tap(find.byType(ZAddButton));
      await tester.pumpAndSettle();
      for (final label in ['Say', 'Type', 'Scan', 'Asset']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        );
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel('Tell Zaghlol'), findsOneWidget);
    });
  });

  group('deep links', () {
    testWidgets('zaghlol://add opens the Add sheet over Home', (tester) async {
      final router = await pumpShell(tester);
      await tester.binding.handlePushRoute('zaghlol://add');
      await tester.pumpAndSettle();
      expect(find.byType(AddSheet), findsOneWidget);
      expect(_location(router), AppRoutes.addOverHome);
      // Home is underneath, so closing the sheet lands on Home.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('home:0'), findsOneWidget);
    });

    testWidgets('zaghlol://review opens the review queue (ar)', (tester) async {
      final router = await pumpShell(tester, locale: _ar);
      await tester.tap(find.text('فلوسي'));
      await tester.pumpAndSettle();
      await tester.binding.handlePushRoute('zaghlol://review');
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.review);
      expect(find.text('مستني رأيك 👀'), findsOneWidget);
    });

    testWidgets('widget tap zaghlol://home selects Home', (tester) async {
      final router = await pumpShell(tester);
      await tester.tap(find.text('Zaghlol'));
      await tester.pumpAndSettle();
      await tester.binding.handlePushRoute('zaghlol://home');
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.home);
    });

    testWidgets('unknown link falls back to Home', (tester) async {
      final router = await pumpShell(tester);
      await tester.binding.handlePushRoute('zaghlol://whatever');
      await tester.pumpAndSettle();
      expect(_location(router), AppRoutes.home);
    });
  });

  testWidgets('text scale 1.3 does not overflow (ar, both platforms)', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpShell(tester, locale: _ar, platform: platform, textScale: 1.3);
      expect(tester.takeException(), isNull);
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final lang in ['ar', 'en']) {
      testWidgets('tab labels are not truncated at 320 dp, x1.3 '
          '($lang, $platform)', (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pumpShell(
          tester,
          locale: Locale(lang),
          platform: platform,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        final bar = find.byType(NavigationBar).evaluate().isNotEmpty
            ? find.byType(NavigationBar)
            : find.byType(Scaffold).first;
        final paragraphs = tester
            .renderObjectList<RenderParagraph>(
              find.descendant(of: bar, matching: find.byType(RichText)),
            )
            .where((p) => p.text.toPlainText().trim().isNotEmpty);
        for (final p in paragraphs) {
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: 'truncated: ${p.text.toPlainText()}',
          );
        }
      });
    }
  }
}
