import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/theme/app_theme.dart';

/// A tab root with local state, to prove tabs keep their state.
class CounterRoot extends StatefulWidget {
  const CounterRoot({super.key, required this.tag});
  final String tag;

  @override
  State<CounterRoot> createState() => _CounterRootState();
}

class _CounterRootState extends State<CounterRoot> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      key: ValueKey('counter-${widget.tag}'),
      onPressed: () => setState(() => count++),
      child: Text('${widget.tag}:$count'),
    ),
  );
}

TabRoots counterRoots() => TabRoots(
  home: (_) => const CounterRoot(tag: 'home'),
  insights: (_) => const CounterRoot(tag: 'insights'),
  money: (_) => const CounterRoot(tag: 'money'),
  zaghlol: (_) => const CounterRoot(tag: 'zaghlol'),
);

class ShellApp extends StatelessWidget {
  const ShellApp({
    super.key,
    required this.router,
    required this.locale,
    required this.platform,
    this.dark = false,
    this.textScale = 1.0,
  });

  final GoRouter router;
  final Locale locale;
  final TargetPlatform platform;
  final bool dark;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    // The Add sheet reads the entitlement (T-082).
    return ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light.copyWith(platform: platform),
        darkTheme: ZaghlolTheme.dark.copyWith(platform: platform),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    );
  }
}

Future<GoRouter> pumpShell(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  TargetPlatform platform = TargetPlatform.android,
  TabRoots? roots,
  bool dark = false,
  double textScale = 1.0,
}) async {
  final router = buildAppRouter(roots ?? counterRoots());
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ShellApp(
      router: router,
      locale: locale,
      platform: platform,
      dark: dark,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
