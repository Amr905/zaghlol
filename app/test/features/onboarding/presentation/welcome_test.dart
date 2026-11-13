import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/onboarding/presentation/welcome.dart';

/// Mimics main.dart: the locale comes from [appLocaleProvider].
class _Host extends ConsumerWidget {
  const _Host({this.scale = 1.0, this.onStart, this.onRestore});
  final double scale;
  final VoidCallback? onStart;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: ZaghlolTheme.light,
    locale: ref.watch(appLocaleProvider),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: WelcomeScreen(
      onStart: onStart ?? () {},
      onRestore: onRestore ?? () {},
      onPrivacy: () {},
    ),
  );
}

/// In-memory language setting standing in for the settings repository.
class _Lang extends Notifier<LanguagePref> {
  @override
  LanguagePref build() => LanguagePref.ar;
}

void main() {
  for (final lang in ['ar', 'en']) {
    testWidgets('renders, actions fire, no overflow at 1.3x ($lang)', (
      tester,
    ) async {
      var started = 0, restored = 0;
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            languageProvider.overrideWith(
              (ref) => Stream.value(
                lang == 'ar' ? LanguagePref.ar : LanguagePref.en,
              ),
            ),
          ],
          child: _Host(
            scale: 1.3,
            onStart: () => started++,
            onRestore: () => restored++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dir = Directionality.of(tester.element(find.byType(WelcomeScreen)));
      expect(dir, lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      // One primary action only.
      expect(find.byKey(const ValueKey('welcome-start')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('welcome-start')));
      await tester.tap(find.byKey(const ValueKey('welcome-start')));
      await tester.ensureVisible(find.byKey(const ValueKey('welcome-restore')));
      await tester.tap(find.byKey(const ValueKey('welcome-restore')));
      expect([started, restored], [1, 1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('language toggle flips direction instantly', (tester) async {
    final lang = NotifierProvider<_Lang, LanguagePref>(_Lang.new);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          languageProvider.overrideWith((ref) => Stream.value(ref.watch(lang))),
        ],
        child: const _Host(),
      ),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(WelcomeScreen));
    expect(Directionality.of(ctx), TextDirection.rtl);
    final container = ProviderScope.containerOf(ctx);
    container.read(lang.notifier).state = LanguagePref.en;
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(WelcomeScreen))),
      TextDirection.ltr,
    );
  });
}
