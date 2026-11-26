// T-362: goldens of the card, the consent sheet, the Settings row and the
// queue header (ar/en x light/dark x 100/130 %). PNGs come from CI.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/features/categorization/data/llm_cat_providers.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_consent_sheet.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_discovery_card.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_queue_header.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_ui_providers.dart';
import 'package:zaghlol/features/settings/presentation/privacy_llm_cat_section.dart';

import '../../settings/settings_harness.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        final name =
            '${lang}_${dark ? 'dark' : 'light'}_${(scale * 100).round()}';
        testWidgets('auto category $name', (tester) async {
          final h = SettingsHarness();
          addTearDown(h.db.close);
          final consent = LlmConsentStore(h.repo);
          await consent.grant(LlmFeature.categorise, 'prov-a', 1);
          await tester.pumpWidget(
            h.app(
              const Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      LlmCatDiscoveryCard(),
                      LlmCatConsentSheet(
                        providerName: 'prov-a',
                        quotaPerMonth: 15,
                      ),
                      PrivacyLlmCatSection(),
                      LlmCatQueueHeader(),
                    ],
                  ),
                ),
              ),
              locale: Locale(lang),
              dark: dark,
              scale: scale,
              overrides: [
                llmCatTermsProvider.overrideWithValue(
                  const LlmTerms(provider: 'prov-a', v: 1),
                ),
                llmConsentStoreProvider.overrideWith((ref) async => consent),
                featureFlagProvider(FeatureFlag.llmCategorise)
                    .overrideWithValue(true),
                catEligibleCountProvider.overrideWith((ref) async => 3),
                // The card shows only before consent; golden shows the
                // consented rows, so pin the card visible separately.
                catCardVisibleProvider.overrideWith((ref) async => true),
              ],
            ),
          );
          await settle(tester, height: 4000);
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile('goldens/llm_cat_$name.png'),
          );
        });
      }
    }
  }
}
