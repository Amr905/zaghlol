import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/onboarding/presentation/onboarding_parts.dart';

void main() {
  for (final scale in [1.3, 2.0]) {
    testWidgets('pinned actions do not overflow at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ZaghlolTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: OnbPage(
              content: const [Text('content')],
              actions: [
                for (var i = 0; i < 6; i++)
                  FilledButton(
                    key: ValueKey('a$i'),
                    onPressed: () {},
                    child: const Text('زرار طويل بعض الشيء للاختبار هنا كمان'),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // The last action is reachable by scrolling.
      await tester.ensureVisible(find.byKey(const ValueKey('a5')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
