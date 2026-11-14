import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/charts/charts_providers.dart';
import 'package:zaghlol/features/share_cards/application/share_providers.dart';
import 'package:zaghlol/features/share_cards/domain/share_figures.dart';
import 'package:zaghlol/features/share_cards/presentation/share_studio_screen.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../support/golden_matrix.dart';

final _egp = Currency.of('EGP');
Money _m(int minor) => Money(_egp, minor);

final _figs = [
  ShareFigure(
    template: ShareTemplate.savings,
    percentBp: 3800,
    amount: Money(Currency.of('EGP'), 1234500),
  ),
];

class _Sheet implements ShareSheet {
  int calls = 0;
  @override
  Future<void> sharePng(Uint8List png) async => calls++;
}

Future<void> pumpStudio(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double scale = 1.0,
  List<ShareFigure>? figures,
  List<Currency>? currencies,
  ShareSheet? sheet,
  bool failFigures = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chartsCurrenciesProvider.overrideWith(
          (ref) async => currencies ?? [_egp],
        ),
        shareFiguresProvider.overrideWith((ref, code) async {
          if (failFigures) throw StateError('x');
          return figures ?? _figs;
        }),
        if (sheet != null) shareSheetProvider.overrideWithValue(sheet),
      ],
      child: MaterialApp(
        locale: locale,
        theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const ShareStudioScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final loc in [const Locale('en'), const Locale('ar', 'EG')]) {
    final name = loc.languageCode;
    testWidgets('hidden mode shows percent only, no amount ($name)', (t) async {
      await pumpStudio(t, locale: loc, scale: 1.3);
      expect(t.takeException(), isNull);
      final ar = loc.languageCode == 'ar';
      expect(find.textContaining(ar ? '٣٨' : '38%'), findsWidgets);
      expect(find.textContaining(ar ? '١٢٬٣٤٥' : '12,345'), findsNothing);
    });

    testWidgets('toggle on shows the amount ($name)', (t) async {
      await pumpStudio(t, locale: loc);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(
        find.textContaining(loc.languageCode == 'ar' ? '١٢٬٣٤٥' : '12,345'),
        findsOneWidget,
      );
    });
  }

  testWidgets('switch is off by default', (t) async {
    await pumpStudio(t);
    expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('empty state', (t) async {
    await pumpStudio(t, figures: const []);
    expect(find.text('Nothing to share yet'), findsOneWidget);
  });

  testWidgets('no currency activity is the empty state', (t) async {
    await pumpStudio(t, currencies: const []);
    expect(find.text('Nothing to share yet'), findsOneWidget);
  });

  testWidgets('error state offers retry', (t) async {
    await pumpStudio(t, failFigures: true);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('two currencies show the switcher', (t) async {
    await pumpStudio(t, currencies: [_egp, Currency.of('USD')]);
    expect(find.text('USD'), findsOneWidget);
  });

  testWidgets('share renders the card and calls the sheet', (t) async {
    final s = _Sheet();
    await pumpStudio(t, sheet: s);
    await t.runAsync(() async {
      await t.tap(find.text('Share').last);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpAndSettle();
    expect(s.calls, 1);
  });

  test('staging file is deleted after share, and on failure', () async {
    final dir = await Directory.systemTemp.createTemp('share_t');
    addTearDown(() => dir.delete(recursive: true));
    String? seen;
    final ok = StagedShareSheet(
      dir: () async => dir,
      invoke: (p) async {
        seen = p;
        expect(File(p).existsSync(), isTrue);
      },
    );
    await ok.sharePng(Uint8List.fromList([1, 2, 3]));
    expect(File(seen!).existsSync(), isFalse);

    final bad = StagedShareSheet(
      dir: () async => dir,
      invoke: (p) async {
        seen = p;
        throw StateError('x');
      },
    );
    await expectLater(bad.sharePng(Uint8List(1)), throwsStateError);
    expect(File(seen!).existsSync(), isFalse);
    expect(dir.listSync(), isEmpty);
  });

  test('buildShareFigures: only templates with data', () {
    final rule = ChartReady(
      FiftyThirtyTwenty(
        income: _m(1000000),
        needs: _m(0),
        wants: _m(0),
        savings: _m(380000),
        other: _m(0),
      ),
    );
    final f = buildShareFigures(rule: rule);
    expect(f.single.template, ShareTemplate.savings);
    expect(f.single.percent, 38);
    expect(buildShareFigures(), isEmpty);
  });

  group('golden', () {
    for (final v in goldenVariants) {
      testWidgets('share studio ${v.name}', (t) async {
        await pumpStudio(t, locale: v.locale, dark: v.dark);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../goldens/share_studio_${v.name}.png'),
        );
      }, tags: 'golden');
    }
  });
}
