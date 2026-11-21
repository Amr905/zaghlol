import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
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

  group('shared bar (C-02, D-77/D-78)', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('$platform gets the same bar: no M3 bar, no FAB, no glass', (
        tester,
      ) async {
        await pumpShell(tester, platform: platform);
        expect(find.byType(ZBottomBar), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byType(BackdropFilter), findsNothing);
      });
    }

    for (final (name, locale) in [('en', _en), ('ar', _ar)]) {
      testWidgets(
        '($name) bar is docked, 64 dp, and the body ends at its top',
        (tester) async {
          await pumpShell(tester, locale: locale);
          final size = tester.view.physicalSize / tester.view.devicePixelRatio;
          final bar = tester.getRect(find.byType(ZBottomBar));
          expect(bar.bottom, closeTo(size.height, 0.01));
          expect(bar.width, closeTo(size.width, 0.01));
          expect(bar.height, closeTo(64, 0.5));
          final body = tester.getRect(
            find.byKey(const ValueKey('counter-home')),
          );
          expect(body.bottom, lessThanOrEqualTo(bar.top));
        },
      );

      testWidgets('($name) Add: 62 dp circle, centred, raised 34 dp', (
        tester,
      ) async {
        await pumpShell(tester, locale: locale);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        final bar = tester.getRect(find.byType(ZBottomBar));
        final add = tester.getRect(find.byType(ZAddButton));
        expect(add.width, closeTo(62, 0.01));
        expect(add.height, closeTo(62, 0.01));
        expect(add.center.dx, closeTo(size.width / 2, 0.01));
        // 5 dp ring around the circle; the ring's top is 34 dp above the bar.
        expect(bar.top - (add.top - 5), closeTo(34, 0.01));
        expect(find.text(locale == _ar ? 'سجّل' : 'Add'), findsOneWidget);
      });
    }

    testWidgets('RTL order: Home right of Insights, Add centre (ar)', (
      tester,
    ) async {
      await pumpShell(tester, locale: _ar);
      double x(String t) => tester.getCenter(find.text(t)).dx;
      final add = tester.getCenter(find.byType(ZAddButton)).dx;
      expect(x('الرئيسية'), greaterThan(x('الحسبة')));
      expect(x('الحسبة'), greaterThan(add));
      expect(add, greaterThan(x('فلوسي')));
      expect(x('فلوسي'), greaterThan(x('زغلول')));
    });

    testWidgets('LTR order mirrors (en)', (tester) async {
      await pumpShell(tester);
      double x(String t) => tester.getCenter(find.text(t)).dx;
      final add = tester.getCenter(find.byType(ZAddButton)).dx;
      expect(x('Home'), lessThan(x('Insights')));
      expect(x('Insights'), lessThan(add));
      expect(add, lessThan(x('Money')));
      expect(x('Money'), lessThan(x('Zaghlol')));
    });

    testWidgets('tabs and Add are at least 48 dp targets', (tester) async {
      await pumpShell(tester);
      for (final label in ['Home', 'Insights', 'Money', 'Zaghlol']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
      final add = tester.getSize(find.byType(ZAddButton));
      expect(add.shortestSide, greaterThanOrEqualTo(48));
    });

    testWidgets('active tab: primaryContainer pill, filled icon, bold label', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.byIcon(Icons.home), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
      expect(find.byIcon(Icons.area_chart_outlined), findsOneWidget);
      final label = tester.widget<Text>(find.text('Home'));
      expect(label.style!.fontWeight, FontWeight.w700);
      final pill = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.home),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(pill, const Size(56, 30));
    });

    testWidgets('semantics: every tab and Add labelled, selected announced', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpShell(tester, locale: _ar);
      for (final label in ['الرئيسية', 'الحسبة', 'فلوسي', 'زغلول']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }
      expect(find.bySemanticsLabel('سجّل بسرعة'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('الرئيسية')),
        matchesSemantics(
          label: 'الرئيسية',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('dark (True Black): bar #141414, top edge #242424', (
      tester,
    ) async {
      await pumpShell(tester, dark: true);
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ZBottomBar),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, const Color(0xFF141414));
      expect((deco.border! as Border).top.color, const Color(0xFF242424));
      // No shadow in dark.
      expect(deco.boxShadow!.every((b) => b.color.a == 0), isTrue);
    });

    testWidgets('light: soft upward shadow', (tester) async {
      await pumpShell(tester);
      final deco =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(ZBottomBar),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(deco.color, const Color(0xFFFFFFFF));
      expect(deco.boxShadow!.first.offset.dy, lessThan(0));
      expect(deco.boxShadow!.first.color.a, greaterThan(0));
    });

    testWidgets('bottom safe-area inset is added below the 64 dp bar', (
      tester,
    ) async {
      tester.view.padding = FakeViewPadding(
        bottom: 34 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);
      await pumpShell(tester);
      expect(tester.getSize(find.byType(ZBottomBar)).height, closeTo(98, 0.5));
    });

    testWidgets('the bar hides while the keyboard is open', (tester) async {
      await pumpShell(tester);
      expect(find.byType(ZBottomBar), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byType(ZBottomBar), findsNothing);
      expect(find.byType(ZAddButton), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byType(ZBottomBar), findsOneWidget);
    });

    testWidgets('a list with 40 dp end padding clears the raised Add', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShellScaffold(
            body: ListView.builder(
              padding: const EdgeInsets.only(bottom: ZSpacing.fabClearance),
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(
                height: 56,
                child: Text('row$i', key: ValueKey('row$i')),
              ),
            ),
            selected: 0,
            onSelect: (_) {},
            onAdd: () {},
            labels: const ['a', 'b', 'c', 'd'],
            addLabel: 'add',
          ),
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('row29')));
      final ring = tester.getRect(find.byType(ZAddButton)).top - 5;
      expect(last.bottom, lessThanOrEqualTo(ring + 0.01));
      expect(
        tester.getRect(find.byType(ZBottomBar)).top,
        greaterThanOrEqualTo(last.bottom),
      );
    });

    testWidgets('badge shows the count, capped at 9+', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ZaghlolTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: _en,
          home: ShellScaffold(
            body: const SizedBox.shrink(),
            selected: 0,
            onSelect: (_) {},
            onAdd: () {},
            labels: const ['a', 'b', 'c', 'd'],
            addLabel: 'add',
            badges: const {3: 12, 1: 4},
          ),
        ),
      );
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
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
        final bar = find.byType(ZBottomBar);
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
