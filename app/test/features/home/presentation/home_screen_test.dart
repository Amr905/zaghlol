import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_banner.dart';
import 'package:zaghlol/features/home/presentation/home_screen.dart';

import 'home_harness.dart';

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final locale in [_ar, _en]) {
      for (final scale in [1.0, 1.3]) {
        final tag = '${platform.name} ${locale.languageCode} x$scale';

        testWidgets('data state, no overflow ($tag)', (tester) async {
          await pumpHome(
            tester,
            locale: locale,
            platform: platform,
            value: model(review: 3),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('home-review')), findsOneWidget);
          expect(find.byKey(const ValueKey('home-row-t1')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-title-ios')),
            platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const ValueKey('home-title-android')),
            platform == TargetPlatform.android ? findsOneWidget : findsNothing,
          );
          final dir = Directionality.of(
            tester.element(find.byType(HomeScreen)),
          );
          expect(
            dir,
            locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
        });
      }
    }
  }

  testWidgets('hero shows safe to spend, en digits and EGP', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.text('Safe to spend today'), findsOneWidget);
    expect(find.textContaining('314'), findsOneWidget);
    expect(find.textContaining('EGP'), findsWidgets);
  });

  testWidgets('ar renders Arabic-Indic digits and the ج.م symbol', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _ar,
      platform: TargetPlatform.android,
      value: model(),
    );
    expect(find.textContaining('٣١٤'), findsOneWidget);
    expect(find.textContaining('ج.م'), findsWidgets);
  });

  testWidgets('spending amounts are ink, not red', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    final t = tester.widget<Text>(find.textContaining('-').first);
    final c = t.style!.color!;
    expect(c.r > 0.5 && c.g < 0.3 && c.b < 0.3, isFalse);
  });

  testWidgets('no budget: hero offers Set a budget, no safe-to-spend', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(currencies: [figs(egp, safe: null)]),
    );
    expect(find.text('Set a budget'), findsOneWidget);
    expect(find.text('Safe to spend today'), findsNothing);
    expect(find.text('Spent this cycle'), findsOneWidget);
  });

  testWidgets('two currencies: pager with dots, figures never summed', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(
        currencies: [figs(egp), figs(usd, income: 500, spend: 120, safe: 9)],
      ),
    );
    expect(find.byKey(const ValueKey('home-pager')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('home-pager')),
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('USD'), findsWidgets);
  });

  testWidgets('one currency: no pager', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(),
    );
    expect(find.byKey(const ValueKey('home-pager')), findsNothing);
  });

  testWidgets('review pill hidden at zero', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.byKey(const ValueKey('home-review')), findsNothing);
  });

  testWidgets('scan banner while scanning', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(scanning: true),
    );
    expect(find.byKey(const ValueKey('home-scan-banner')), findsOneWidget);
  });

  testWidgets('internal transfer is labelled, not red, not signed as spend', (
    tester,
  ) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(),
    );
    expect(find.textContaining('To yourself'), findsWidgets);
  });

  testWidgets('empty: add action when SMS is not waiting', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(currencies: [], recent: []),
    );
    expect(find.byKey(const ValueKey('home-empty')), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Add first expense'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-hero-empty')), findsOneWidget);
  });

  testWidgets('empty with SMS on: waiting copy, no add button', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      value: model(currencies: [], recent: []),
      smsWaiting: true,
    );
    expect(find.textContaining('as soon as a bank message'), findsOneWidget);
    expect(find.text('Add first expense'), findsNothing);
  });

  testWidgets('filter empty names the card (EC-61) and clears', (tester) async {
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.iOS,
      value: model(recent: [], filter: {'a1'}),
      filter: {'a1'},
      accounts: [account('a1', 'CIB', '1234')],
    );
    await tester.pump();
    expect(find.textContaining('CIB •1234 this cycle'), findsOneWidget);
    expect(find.text('Clear filter'), findsWidgets);
  });

  testWidgets('loading shows skeleton', (tester) async {
    final c = pending();
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      future: c.future,
      settle: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('home-skeleton')), findsOneWidget);
  });

  testWidgets('error shows inline banner with retry', (tester) async {
    final c = pending();
    await pumpHome(
      tester,
      locale: _en,
      platform: TargetPlatform.android,
      future: c.future,
      settle: false,
    );
    c.completeError(StateError('x'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('home-error')), findsOneWidget);
    expect(find.byType(ZBanner), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
