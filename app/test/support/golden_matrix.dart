import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';

/// One cell of the golden matrix.
class GoldenVariant {
  const GoldenVariant({
    required this.locale,
    required this.dark,
    this.textScale = 1.0,
  });

  final Locale locale;
  final bool dark;
  final double textScale;

  bool get isRtl => locale.languageCode == 'ar';

  /// Suffix used in golden file names, e.g. `ar_dark` or `en_light_x1.3`.
  String get name =>
      '${locale.languageCode}_${dark ? 'dark' : 'light'}'
      '${textScale == 1.0 ? '' : '_x$textScale'}';
}

const _ar = Locale('ar', 'EG');
const _en = Locale('en');

/// ar RTL and en LTR, light (Mint Fresh) and dark (Jade Night), scale 1.0.
const goldenVariants = <GoldenVariant>[
  GoldenVariant(locale: _ar, dark: false),
  GoldenVariant(locale: _ar, dark: true),
  GoldenVariant(locale: _en, dark: false),
  GoldenVariant(locale: _en, dark: true),
];

/// The same four cells at text scale 1.3 (NFR-UX-02).
const goldenVariantsScaled = <GoldenVariant>[
  GoldenVariant(locale: _ar, dark: false, textScale: 1.3),
  GoldenVariant(locale: _ar, dark: true, textScale: 1.3),
  GoldenVariant(locale: _en, dark: false, textScale: 1.3),
  GoldenVariant(locale: _en, dark: true, textScale: 1.3),
];

/// Wraps [child] in the themed, directional, scaled harness for a variant.
Widget goldenHarness(GoldenVariant v, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    // Direction is forced below: Material's built-in delegate only knows `en`.
    theme: ZaghlolTheme.light,
    darkTheme: ZaghlolTheme.dark,
    themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(v.textScale)),
      child: Directionality(
        textDirection: v.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: app!,
      ),
    ),
    home: Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('golden-root'),
        child: Builder(
          builder: (context) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  );
}

/// Registers one golden test per variant for [build]'s widget.
///
/// Files land in `goldens/<name>_<variant>.png` next to the test.
void goldenMatrix(
  String name,
  Widget Function() build, {
  List<GoldenVariant> variants = goldenVariants,
  Size size = const Size(390, 480),
}) {
  for (final v in variants) {
    testWidgets('$name golden ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(goldenHarness(v, build()));
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('${name}_${v.name}.png'),
      );
    });
  }
}
