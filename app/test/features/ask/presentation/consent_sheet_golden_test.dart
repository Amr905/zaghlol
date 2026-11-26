// T-345: goldens for the consent sheet and the disclosure (ar/en x
// light/dark x 100/130 %). Tagged; PNGs come from CI (app-regen).
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ask/presentation/consent_sheet.dart';
import 'package:zaghlol/features/ask/presentation/sent_disclosure.dart';

import '../../settings/settings_harness.dart';

const _terms = AskConsentTerms(
  providerId: 'prov-a',
  version: 1,
  providerName: 'Prov A',
  quotaPerMonth: 5,
);

void main() {
  for (final lang in ['ar', 'en']) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        final name =
            '${lang}_${dark ? 'dark' : 'light'}_${(scale * 100).round()}';
        testWidgets('consent sheet $name', (tester) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          final segs = lang == 'ar'
              ? const <SentSegment>[
                  SentPlain('صرفت كام على '),
                  SentPlaceholder(SentChipKind.card, 1),
                  SentPlain('؟'),
                ]
              : const <SentSegment>[
                  SentPlain('How much did I spend on '),
                  SentPlaceholder(SentChipKind.card, 1),
                  SentPlain('?'),
                ];
          await tester.pumpWidget(
            h.app(
              Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      ConsentSheet(terms: _terms, preview: segs),
                      SentDisclosure(
                        segments: segs,
                        providerName: 'Prov A',
                        initiallyExpanded: true,
                      ),
                    ],
                  ),
                ),
              ),
              locale: Locale(lang),
              dark: dark,
              scale: scale,
            ),
          );
          await settle(tester, height: 3000);
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile('goldens/consent_sheet_$name.png'),
          );
        });
      }
    }
  }
}
