// T-174: guideline + 1.3x sweep over Transaction detail/edit, Home, Review
// queue, Scan results and Capture settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/features/capture/presentation/capture_settings_screen.dart';

import '../features/capture/presentation/capture_ui_support.dart' as cap;
import '../features/home/presentation/home_harness.dart' as home;
import '../features/ingestion/presentation/review/review_harness.dart' as rev;
import '../features/onboarding/presentation/scan_results_test.dart' as scan;
import '../features/transactions/presentation/detail_edit_harness.dart';
import '../features/transactions/presentation/list/list_harness.dart';
import '../support/a11y_guidelines.dart';
import '../support/golden_matrix.dart';

void main() {
  setUpAll(initDateFormatting);
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;

    testWidgets('transaction detail a11y ${v.name}', (t) async {
      await pumpDetail(
        t,
        Harness(FakeRepo([txnRec('a')])),
        detail: AsyncData(
          detailOf(txnRec('a'), raw: 'SYNTHETIC BANK: purchase 450.00 EGP'),
        ),
        locale: v.locale,
        dark: v.dark,
        textScale: v.textScale,
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('transaction edit a11y ${v.name}', (t) async {
      await pumpEditor(
        t,
        FakeEditor(),
        existing: txnRec('a'),
        locale: v.locale,
        dark: v.dark,
        textScale: v.textScale,
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('home a11y ${v.name}', (t) async {
      await home.pumpHome(
        t,
        platform: TargetPlatform.android,
        locale: v.locale,
        dark: v.dark,
        textScale: v.textScale,
        value: home.model(review: 3),
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('home empty a11y ${v.name}', (t) async {
      await home.pumpHome(
        t,
        platform: TargetPlatform.android,
        locale: v.locale,
        dark: v.dark,
        textScale: v.textScale,
        value: home.model(currencies: [], recent: []),
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('review queue a11y ${v.name}', (t) async {
      await rev.pumpReview(
        t,
        rev.reviewApp(
          actions: rev.FakeActions(),
          queue: rev.sampleCards,
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
        ),
        size: const Size(390, 1500),
      );
      await expectA11yGuidelines(t);
    });

    testWidgets('scan results a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        scan.host(
          const AsyncData(scan.sample),
          lang,
          dark: v.dark,
          scale: v.textScale,
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });

    testWidgets('capture settings a11y ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        cap.host(
          const CaptureSettingsScreen(),
          controls: cap.FakeControls(
            rules: [
              cap.rule('1', 'cib', '9910', 'sms'),
              cap.rule('3', 'revolut', null, 'notification'),
            ],
          ),
          locale: v.locale,
          dark: v.dark,
          scale: v.textScale,
        ),
      );
      await t.pumpAndSettle();
      await expectA11yGuidelines(t);
    });
  }
}
