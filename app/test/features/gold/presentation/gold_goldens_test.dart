@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/gold/presentation/gold_messages.dart';
import 'package:zaghlol/features/gold/presentation/paywall_screen.dart';

import 'gold_ui_harness.dart';

Future<void> main() async {
  await initDateFormatting();
  final next = DateTime.utc(2026, 12, 5, 9);
  for (final lang in ['ar', 'en']) {
    for (final dark in [false, true]) {
      final tag = '${lang}_${dark ? 'dark' : 'light'}';
      testWidgets('paywall $tag', (tester) async {
        await pumpGold(
          tester,
          goldApp(
            const PaywallScreen(),
            overrides: goldOverrides(FakeGoldActions()),
            lang: lang,
            dark: dark,
          ),
          height: 1000,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/gold_paywall_$tag.png'),
        );
      });
      testWidgets('messages $tag', (tester) async {
        await pumpGold(
          tester,
          goldApp(
            Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final k in GoldMessageKind.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GoldMessageCard(
                        message: GoldMessage(k, nextMoveAt: next),
                        onRestore: () {},
                        onRetry: () {},
                        onDismiss: () {},
                      ),
                    ),
                ],
              ),
            ),
            overrides: goldOverrides(FakeGoldActions(), signIn: () {}),
            lang: lang,
            dark: dark,
          ),
          height: 6000,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/gold_messages_$tag.png'),
        );
      });
    }
  }
}
