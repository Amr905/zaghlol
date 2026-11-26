// T-362: discovery card, consent sheet, Settings row and queue header.
//   AC1 card frequency          -> 'frequency' + 'card' groups
//   AC2 Not now sends nothing, switch off empties the queue -> 'consent'
//   AC4 flag off hides all      -> 'flag off', 'terms unknown'

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/features/categorization/data/llm_cat_providers.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_consent_sheet.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_discovery_card.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_queue_header.dart';
import 'package:zaghlol/features/categorization/presentation/llm_cat_ui_providers.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';

import '../../settings/settings_harness.dart';

const _terms = LlmTerms(provider: 'prov-a', v: 1);

void main() {
  group('frequency', () {
    final now = DateTime.utc(2026, 11, 26);
    bool due({
      int eligible = 3,
      int shown = 0,
      DateTime? last,
      bool never = false,
    }) => catCardDue(
      eligible: eligible,
      shown: shown,
      lastShownMs: last?.millisecondsSinceEpoch,
      never: never,
      now: now,
    );

    test('2 merchants no card, 3 merchants card', () {
      expect(due(eligible: 2), isFalse);
      expect(due(eligible: 3), isTrue);
    });
    test('dismissed: not again for 30 days', () {
      expect(
        due(shown: 1, last: now.subtract(const Duration(days: 29))),
        isFalse,
      );
      expect(
        due(shown: 1, last: now.subtract(const Duration(days: 30))),
        isTrue,
      );
    });
    test('never after 3 showings or "never"', () {
      expect(
        due(shown: 3, last: now.subtract(const Duration(days: 90))),
        isFalse,
      );
      expect(due(never: true), isFalse);
    });
  });

  late SettingsHarness h;
  late LlmConsentStore consent;
  late LlmQuotaStore quota;
  late int kicks;
  setUp(() {
    h = SettingsHarness();
    consent = LlmConsentStore(
      h.repo,
      nowMs: () => 99,
      onCleared: (f) async {
        if (f == LlmFeature.categorise) await LlmCatQueueDao(h.db).clear();
      },
    );
    quota = LlmQuotaStore(h.repo);
    kicks = 0;
  });
  tearDown(() => h.db.close());

  List<Override> ov({
    bool flag = true,
    LlmTerms? terms = _terms,
    int eligible = 3,
  }) => [
    llmCatTermsProvider.overrideWithValue(terms),
    llmConsentStoreProvider.overrideWith((ref) async => consent),
    llmQuotaStoreProvider.overrideWith((ref) async => quota),
    featureFlagProvider(FeatureFlag.llmCategorise).overrideWithValue(flag),
    catEligibleCountProvider.overrideWith((ref) async => eligible),
    catSenderKickProvider.overrideWithValue((lang) async => kicks++),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    String lang = 'en',
    List<Override>? overrides,
    double scale = 1.0,
  }) async {
    await tester.pumpWidget(
      h.app(
        const Scaffold(body: LlmCatDiscoveryCard()),
        locale: Locale(lang),
        overrides: overrides ?? ov(),
        scale: scale,
      ),
    );
    await settle(tester);
  }

  for (final lang in ['ar', 'en']) {
    group('card [$lang]', () {
      testWidgets('shows with 3 merchants and a 48 dp Allow', (tester) async {
        await pumpCard(tester, lang: lang);
        expect(
          find.byKey(const ValueKey('cat-discovery-card')),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('cat-card-allow'))).height,
          greaterThanOrEqualTo(48),
        );
      });

      testWidgets('Not now hides it, stores the count, sends nothing', (
        tester,
      ) async {
        await pumpCard(tester, lang: lang);
        await tester.tap(find.byKey(const ValueKey('cat-card-not-now')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
        expect(
          await tester.runAsync(() => h.repo.get(CatCardSettings.shown)),
          1,
        );
        expect(
          await tester.runAsync(() => h.repo.get(CatCardSettings.lastShown)),
          isNotNull,
        );
        expect(
          await tester.runAsync(() => consent.read(LlmFeature.categorise)),
          isNull,
        );
        expect(kicks, 0);
      });

      testWidgets("Don't ask again hides it for good", (tester) async {
        await pumpCard(tester, lang: lang);
        await tester.tap(find.byKey(const ValueKey('cat-card-never')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
        expect(
          await tester.runAsync(() => h.repo.get(CatCardSettings.never)),
          isTrue,
        );
      });
    });
  }

  group('consent', () {
    testWidgets('Allow on the sheet stores consent and starts the sender', (
      tester,
    ) async {
      await pumpCard(tester);
      await tester.tap(find.byKey(const ValueKey('cat-card-allow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cat-consent-sheet')), findsOneWidget);
      expect(kicks, 0);
      await tester.tap(find.byKey(const ValueKey('cat-consent-allow')));
      await tester.pumpAndSettle();
      final g = await tester.runAsync(
        () => consent.read(LlmFeature.categorise),
      );
      expect(g, const LlmConsentGrant(provider: 'prov-a', v: 1, atMs: 99));
      expect(kicks, 1);
      expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
    });

    testWidgets('Not now on the sheet stores nothing and sends nothing', (
      tester,
    ) async {
      await pumpCard(tester);
      await tester.tap(find.byKey(const ValueKey('cat-card-allow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cat-consent-not-now')));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => consent.read(LlmFeature.categorise)),
        isNull,
      );
      expect(kicks, 0);
    });

    testWidgets('buttons stack at 130 percent and keep 48 dp', (tester) async {
      await pumpCard(tester, scale: 1.3);
      await tester.tap(find.byKey(const ValueKey('cat-card-allow')));
      await tester.pumpAndSettle();
      final a = tester.getRect(find.byKey(const ValueKey('cat-consent-allow')));
      final n = tester.getRect(
        find.byKey(const ValueKey('cat-consent-not-now')),
      );
      expect(n.top, greaterThanOrEqualTo(a.bottom));
      expect(a.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });

  group('flag off / terms unknown', () {
    testWidgets('flag off: no card', (tester) async {
      await pumpCard(tester, overrides: ov(flag: false));
      expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
    });
    testWidgets('terms unknown: no card (FU-425)', (tester) async {
      await pumpCard(tester, overrides: ov(terms: null));
      expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
    });
    testWidgets('2 merchants: no card', (tester) async {
      await pumpCard(tester, overrides: ov(eligible: 2));
      expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
    });
    testWidgets('already consented: no card', (tester) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await pumpCard(tester);
      expect(find.byKey(const ValueKey('cat-discovery-card')), findsNothing);
    });
    testWidgets('flag off: no row, no counter, no server item', (tester) async {
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          overrides: ov(flag: false),
        ),
      );
      await settle(tester, height: 4000);
      expect(find.byKey(const ValueKey('cat-llm-switch')), findsNothing);
      expect(find.textContaining('shop name for a category'), findsNothing);
    });
    testWidgets('flag off: no queue header', (tester) async {
      await tester.pumpWidget(
        h.app(
          const Scaffold(body: LlmCatQueueHeader()),
          overrides: ov(flag: false),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('cat-queue-passive')), findsNothing);
    });
  });

  group('S-71 row', () {
    Future<void> pump(WidgetTester tester, {String lang = 'en'}) async {
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          locale: Locale(lang),
          overrides: ov(),
        ),
      );
      await settle(tester, height: 4000);
    }

    testWidgets(
      'allow, unknown counter, then off clears and empties the queue',
      (tester) async {
        await tester.runAsync(
          () =>
              LlmCatQueueDao(h.db)
                  .put('shop a', txnCount: 1, lastSeenAt: 1, at: 1),
        );
        await pump(tester);
        expect(find.byKey(const ValueKey('cat-llm-quota')), findsNothing);
        final sw = find.byKey(const ValueKey('cat-llm-switch'));
        await tester.ensureVisible(sw);
        await tester.tap(sw);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cat-consent-allow')));
        await tester.pumpAndSettle();
        expect(
          find.text("The count shows after Zaghlol's first guess."),
          findsOneWidget,
        );
        await tester.tap(sw);
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(() => consent.read(LlmFeature.categorise)),
          isNull,
        );
        expect(await tester.runAsync(() => LlmCatQueueDao(h.db).count()), 0);
        expect(find.byKey(const ValueKey('cat-llm-quota')), findsNothing);
      },
    );

    testWidgets('counter shows remaining; hidden while paused', (tester) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await h.repo.set(
        LlmQuotaSettings.catQuota,
        LlmQuotaSnapshot(
          limit: 15,
          remaining: 4,
          resetsAt: DateTime.now().toUtc().add(const Duration(days: 5)),
        ),
      );
      await pump(tester);
      expect(find.textContaining('4 guesses left'), findsOneWidget);
    });

    testWidgets('paused hides the counter', (tester) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await quota.pause(LlmFeature.categorise);
      await pump(tester);
      expect(find.byKey(const ValueKey('cat-llm-quota')), findsNothing);
    });

    testWidgets("What's sent opens a read-only sheet", (tester) async {
      await pump(tester, lang: 'ar');
      final d = find.byKey(const ValueKey('cat-llm-details'));
      await tester.ensureVisible(d);
      await tester.tap(d);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cat-consent-allow')), findsNothing);
      expect(find.byKey(const ValueKey('cat-consent-not-now')), findsOneWidget);
    });
  });

  group('queue header', () {
    Future<void> pump(WidgetTester tester, {String lang = 'en'}) async {
      await tester.pumpWidget(
        h.app(
          const Scaffold(body: LlmCatQueueHeader()),
          locale: Locale(lang),
          overrides: ov(),
        ),
      );
      await settle(tester);
    }

    testWidgets('off: passive row opens the sheet', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('cat-queue-passive')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cat-consent-sheet')), findsOneWidget);
    });

    testWidgets('on: unknown counter is a dash; known shows counts', (
      tester,
    ) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await pump(tester);
      expect(find.text('—'), findsOneWidget);
      expect(find.byKey(const ValueKey('cat-queue-passive')), findsNothing);
    });

    testWidgets('on: remaining of limit', (tester) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await h.repo.set(
        LlmQuotaSettings.catQuota,
        LlmQuotaSnapshot(
          limit: 15,
          remaining: 9,
          resetsAt: DateTime.now().toUtc().add(const Duration(days: 5)),
        ),
      );
      await pump(tester);
      expect(find.text('9 of 15 guesses left'), findsOneWidget);
    });

    testWidgets('paused: no counter', (tester) async {
      await consent.grant(LlmFeature.categorise, 'prov-a', 1);
      await quota.pause(LlmFeature.categorise);
      await pump(tester);
      expect(find.byKey(const ValueKey('cat-queue-counter')), findsNothing);
    });
  });
}
