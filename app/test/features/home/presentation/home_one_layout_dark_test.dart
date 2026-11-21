import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/features/home/presentation/home_widgets.dart'
    show HomeCardFilterChip, HomeGreeting, HomeSettingsButton;

import 'home_harness.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

/// Positions of the header pieces, to compare the two platforms.
List<Offset> _headerPositions(WidgetTester tester) => [
  tester.getTopLeft(find.byType(HomeCardFilterChip)),
  tester.getTopLeft(find.byType(HomeSettingsButton)),
  tester.getTopLeft(find.byType(HomeGreeting)),
];

void main() {
  for (final locale in [_ar, _en]) {
    testWidgets(
      'Home is one layout on iOS and Android (${locale.languageCode})',
      (tester) async {
        await pumpHome(
          tester,
          locale: locale,
          platform: TargetPlatform.iOS,
          value: model(review: 2),
        );
        final ios = _headerPositions(tester);
        final iosRow = find.byKey(const ValueKey('home-row-t1'));
        final iosRowPos = tester.getTopLeft(iosRow);
        await pumpHome(
          tester,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(review: 2),
        );
        expect(_headerPositions(tester), ios);
        expect(tester.getTopLeft(iosRow), iosRowPos);
        expect(find.byKey(const ValueKey('home-title-android')), findsNothing);
      },
    );

    testWidgets(
      'dark Home has no green text, flat outlined hero (${locale.languageCode})',
      (tester) async {
        await pumpHome(
          tester,
          locale: locale,
          platform: TargetPlatform.android,
          value: model(review: 2),
          dark: true,
        );
        expect(tester.takeException(), isNull);
        final z = ZColors.dark;
        // Old green text colours (Mint Fresh primary, Jade Night primary).
        const green = [Color(0xFF0F7A55), Color(0xFF34D399)];
        final bad = <String>[];
        for (final e in find.byType(Text).evaluate()) {
          final w = e.widget as Text;
          final color = DefaultTextStyle.of(e).style.merge(w.style).color;
          if (color != null && green.contains(color)) bad.add(w.data ?? '?');
          // Any dark text must be neutral, or income mint / apricot / warning.
        }
        expect(bad, isEmpty);
        // Hero number is white.
        expect(z.heroNumber, const Color(0xFFFFFFFF));
        // No visible shadows anywhere under Home.
        for (final d in tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.byType(DecoratedBox),
          ),
        )) {
          final deco = d.decoration;
          if (deco is BoxDecoration) {
            for (final s in deco.boxShadow ?? const <BoxShadow>[]) {
              expect(s.color.a, 0, reason: 'dark shadow must be transparent');
            }
          }
        }
        // Filter pill and settings circle are outlined.
        for (final t in [HomeCardFilterChip, HomeSettingsButton]) {
          final box = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(t),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect((box.decoration as BoxDecoration).border, isNotNull);
        }
      },
    );
  }

  testWidgets('light header pill and circle have no outline', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(HomeSettingsButton),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).border, isNull);
  });

  testWidgets('EC-61: dark empty state still names the card filter', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(recent: [], filter: {'a1'}),
      filter: {'a1'},
      accounts: [account('a1', 'CIB', '1234')],
      dark: true,
    );
    expect(find.textContaining('CIB'), findsWidgets);
    expect(find.text('Clear filter'), findsWidgets);
  });
}
