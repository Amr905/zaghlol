import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/core/ui/z_components.dart';

Widget _app(
  Widget child, {
  bool rtl = false,
  bool dark = false,
  double scale = 1.0,
}) {
  return MaterialApp(
    locale: rtl ? const Locale('ar', 'EG') : const Locale('en'),
    supportedLocales: [rtl ? const Locale('ar', 'EG') : const Locale('en')],
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: app!,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

Color? _textColor(WidgetTester tester, Finder f) =>
    tester.widget<Text>(f).style?.color;

void main() {
  group('theme', () {
    testWidgets('light and dark expose the right tokens', (tester) async {
      late ZColors seen;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) =>
                Text('x', style: TextStyle(color: (seen = ZColors.of(c)).text)),
          ),
        ),
      );
      expect(seen.bg, const Color(0xFFF3FBF7));
      expect(seen.primary, const Color(0xFF0F7A55));
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) =>
                Text('x', style: TextStyle(color: (seen = ZColors.of(c)).text)),
          ),
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(seen.bg, const Color(0xFF08130F));
      expect(seen.primary, const Color(0xFF34D399));
    });

    test('scaffold background follows the token', () {
      expect(ZaghlolTheme.light.scaffoldBackgroundColor, ZColors.light.bg);
      expect(ZaghlolTheme.dark.scaffoldBackgroundColor, ZColors.dark.bg);
    });
  });

  group('ZButton', () {
    testWidgets('default: tap fires', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(ZButton(label: 'Go', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Go'));
      expect(taps, 1);
    });

    testWidgets('disabled: no tap, 38% opacity, label kept', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(const ZButton(label: 'Go', onPressed: null)),
      );
      await tester.tap(find.text('Go'), warnIfMissed: false);
      expect(
        tester
            .widgetList<Opacity>(find.byType(Opacity))
            .any((o) => o.opacity == 0.38),
        isTrue,
      );
      expect(tester.getSemantics(find.byType(ZButton)).label, 'Go');
      handle.dispose();
    });

    testWidgets('loading: spinner shown, taps ignored, width kept', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(ZButton(label: 'Save', onPressed: () => taps++)),
      );
      final idle = tester.getSize(find.byType(ZButton));
      await tester.pumpWidget(
        _app(ZButton(label: 'Save', onPressed: () => taps++, loading: true)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(find.byType(ZButton)).width, idle.width);
      await tester.tap(find.byType(ZButton), warnIfMissed: false);
      expect(taps, 0);
    });

    for (final v in ZButtonVariant.values) {
      testWidgets('variant ${v.name} renders with >= 48dp target', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(ZButton(label: 'Go', onPressed: () {}, variant: v)),
        );
        expect(
          tester.getSize(find.byType(ZButton)).height,
          greaterThanOrEqualTo(48),
        );
      });
    }

    testWidgets('small size keeps a 48dp target', (tester) async {
      await tester.pumpWidget(
        _app(ZButton(label: 'Go', onPressed: () {}, size: ZButtonSize.small)),
      );
      expect(
        tester.getSize(find.byType(ZButton)).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('icon sits at the start edge in RTL and LTR', (tester) async {
      Future<void> check(bool rtl) async {
        await tester.pumpWidget(
          _app(
            ZButton(label: 'Go', icon: Icons.add, onPressed: () {}),
            rtl: rtl,
          ),
        );
        final icon = tester.getCenter(find.byIcon(Icons.add)).dx;
        final label = tester.getCenter(find.text('Go')).dx;
        expect(rtl ? icon > label : icon < label, isTrue);
      }

      await check(false);
      await check(true);
    });

    testWidgets('no overflow at 1.3x text scale with a long label', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 200,
            child: ZButton(
              label: 'A fairly long button label here',
              onPressed: () {},
              expand: true,
            ),
          ),
          scale: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ZChip and ZPill', () {
    testWidgets('selected chip keeps its label and taps', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(ZChip(label: 'Food', selected: true, onTap: () => taps++)),
      );
      await tester.tap(find.text('Food'));
      expect(taps, 1);
      expect(tester.getSemantics(find.byType(ZChip)).label, 'Food');
      handle.dispose();
    });

    testWidgets('clear affordance fires onClear', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        _app(ZChip(label: 'CIB', selected: true, onClear: () => cleared++)),
      );
      await tester.tap(find.byIcon(Icons.close));
      expect(cleared, 1);
    });

    testWidgets('every pill tone renders its label', (tester) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (final t in ZPillTone.values) ZPill(label: t.name, tone: t),
            ],
          ),
        ),
      );
      for (final t in ZPillTone.values) {
        expect(find.text(t.name), findsOneWidget);
      }
    });
  });

  group('ZMoneyText', () {
    testWidgets('spending is ink, income is green, neutral is muted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              ZMoneyText(text: '-450'),
              ZMoneyText(text: '+3500', kind: ZMoneyKind.income),
              ZMoneyText(text: '450', kind: ZMoneyKind.neutral),
            ],
          ),
        ),
      );
      expect(
        _textColor(tester, find.textContaining('-450')),
        ZColors.light.text,
      );
      expect(
        _textColor(tester, find.textContaining('+3500')),
        ZColors.light.incomeText,
      );
      expect(
        _textColor(tester, find.text('\u2068450\u2069')),
        ZColors.light.textMuted,
      );
    });

    testWidgets('masked mode shows the mask, never the amount', (tester) async {
      await tester.pumpWidget(
        _app(const ZMoneyText(text: '-450', masked: true, maskedText: '•••')),
      );
      expect(find.textContaining('450'), findsNothing);
      expect(find.textContaining('•••'), findsOneWidget);
    });

    testWidgets('display size shrinks to fit instead of overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SizedBox(
            width: 120,
            child: ZMoneyText(
              text: '-123,456,789.00 EGP',
              size: ZMoneySize.display,
            ),
          ),
          scale: 1.3,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ZBanner', () {
    for (final t in ZBannerTone.values) {
      testWidgets('tone ${t.name} renders message', (tester) async {
        await tester.pumpWidget(
          _app(ZBanner(message: 'msg ${t.name}', tone: t)),
        );
        expect(find.text('msg ${t.name}'), findsOneWidget);
      });
    }

    testWidgets('action and dismiss callbacks fire', (tester) async {
      var acted = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        _app(
          ZBanner(
            message: 'm',
            actionLabel: 'Fix',
            onAction: () => acted++,
            onDismiss: () => dismissed++,
          ),
        ),
      );
      await tester.tap(find.text('Fix'));
      await tester.tap(find.byIcon(Icons.close));
      expect(acted, 1);
      expect(dismissed, 1);
    });
  });

  group('ZListRow / ZCard / ZCategoryTile', () {
    testWidgets('min heights 56 and 72', (tester) async {
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              ZListRow(key: ValueKey('plain'), title: 'A'),
              ZListRow(key: ValueKey('sub'), title: 'B', subtitle: 'sub'),
            ],
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('plain'))).height,
        greaterThanOrEqualTo(56),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('sub'))).height,
        greaterThanOrEqualTo(72),
      );
    });

    testWidgets('disclosure chevron mirrors in RTL', (tester) async {
      await tester.pumpWidget(
        _app(ZListRow(title: 'A', showChevron: true, onTap: () {})),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.pumpWidget(
        _app(ZListRow(title: 'A', showChevron: true, onTap: () {}), rtl: true),
      );
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('disabled row ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(ZListRow(title: 'A', enabled: false, onTap: () => taps++)),
      );
      await tester.tap(find.text('A'));
      expect(taps, 0);
    });

    testWidgets('card tap and category tile', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          ZCard(
            onTap: () => taps++,
            child: const ZCategoryTile(color: Colors.teal, child: Text('x')),
          ),
        ),
      );
      await tester.tap(find.byType(ZCategoryTile));
      expect(taps, 1);
    });
  });

  group('ZSegmentedControl', () {
    testWidgets('selecting a segment reports its value', (tester) async {
      int? picked;
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: ZSegmentedControl<int>(
              segments: const [
                ZSegment(value: 1, label: 'One'),
                ZSegment(value: 2, label: 'Two'),
              ],
              selected: 1,
              onChanged: (v) => picked = v,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Two'));
      expect(picked, 2);
    });

    testWidgets('first segment is at the start edge in RTL', (tester) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 360,
            child: ZSegmentedControl<int>(
              segments: const [
                ZSegment(value: 1, label: 'One'),
                ZSegment(value: 2, label: 'Two'),
              ],
              selected: 1,
              onChanged: (_) {},
            ),
          ),
          rtl: true,
        ),
      );
      expect(
        tester.getCenter(find.text('One')).dx,
        greaterThan(tester.getCenter(find.text('Two')).dx),
      );
    });
  });

  group('sheet', () {
    testWidgets('showZSheet shows title, content and actions', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ZButton(
              label: 'Open',
              onPressed: () => showZSheet<void>(
                context: context,
                title: 'Sheet title',
                builder: (_) => const Text('body'),
                actions: const Text('actions'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sheet title'), findsOneWidget);
      expect(find.text('body'), findsOneWidget);
      expect(find.text('actions'), findsOneWidget);
    });
  });
}
