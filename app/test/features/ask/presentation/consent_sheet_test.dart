// T-345: consent sheet, "What I sent" disclosure and the S-71 row.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_providers.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/features/ask/presentation/consent_sheet.dart';
import 'package:zaghlol/features/ask/presentation/sent_disclosure.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';

import '../../settings/settings_harness.dart';

const _terms = AskConsentTerms(
  providerId: 'prov-a',
  version: 1,
  providerName: 'Prov A',
  quotaPerMonth: 5,
);

const _segments = <SentSegment>[
  SentPlain('كام صرفت على '),
  SentPlaceholder(SentChipKind.card, 1),
  SentPlain(' و '),
  SentHidden(SentHiddenKind.phone),
];

class _Opener extends ConsumerWidget {
  const _Opener({this.preview, this.readOnly = false});
  final List<SentSegment>? preview;
  final bool readOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => readOnly
            ? AskConsentFlow.showReadOnly(context, ref)
            : AskConsentFlow.prompt(context, ref, preview: preview),
        child: const Text('open'),
      ),
    ),
  );
}

void main() {
  late SettingsHarness h;
  late LlmConsentStore consent;
  late LlmQuotaStore quota;
  setUp(() {
    h = SettingsHarness();
    consent = LlmConsentStore(h.repo, nowMs: () => 1234);
    quota = LlmQuotaStore(h.repo);
  });
  tearDown(() => h.db.close());

  List<Override> ov({bool flag = true}) => [
    askConsentTermsProvider.overrideWithValue(_terms),
    llmConsentStoreProvider.overrideWith((ref) async => consent),
    llmQuotaStoreProvider.overrideWith((ref) async => quota),
    featureFlagProvider(FeatureFlag.askLlm).overrideWithValue(flag),
  ];

  for (final lang in ['ar', 'en']) {
    group('sheet [$lang]', () {
      Future<void> open(WidgetTester tester, {bool readOnly = false}) async {
        await tester.pumpWidget(
          h.app(
            _Opener(preview: readOnly ? null : _segments, readOnly: readOnly),
            locale: Locale(lang),
            overrides: ov(),
          ),
        );
        await settle(tester);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      testWidgets('Allow stores {provider, v, at}', (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('consent-preview')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('consent-allow')));
        await tester.pumpAndSettle();
        final g = await tester.runAsync(() => consent.read(LlmFeature.ask));
        expect(g, const LlmConsentGrant(provider: 'prov-a', v: 1, atMs: 1234));
      });

      testWidgets('Not now stores nothing', (tester) async {
        await open(tester);
        await tester.tap(find.byKey(const ValueKey('consent-not-now')));
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(() => consent.read(LlmFeature.ask)),
          isNull,
        );
      });

      testWidgets('drag down and back store nothing', (tester) async {
        await open(tester);
        await tester.tapAt(const Offset(10, 10)); // scrim
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('consent-allow')), findsNothing);
        await open(tester);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('consent-allow')), findsNothing);
        expect(
          await tester.runAsync(() => consent.read(LlmFeature.ask)),
          isNull,
        );
      });

      testWidgets('read-only: no Allow, no preview', (tester) async {
        await open(tester, readOnly: true);
        expect(find.byKey(const ValueKey('consent-allow')), findsNothing);
        expect(find.byKey(const ValueKey('consent-preview')), findsNothing);
        expect(find.byKey(const ValueKey('consent-not-now')), findsOneWidget);
      });
    });
  }

  testWidgets('buttons stack at 130 percent text and keep 48 dp', (
    tester,
  ) async {
    await tester.pumpWidget(
      h.app(const _Opener(preview: _segments), overrides: ov(), scale: 1.3),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final a = tester.getRect(find.byKey(const ValueKey('consent-allow')));
    final n = tester.getRect(find.byKey(const ValueKey('consent-not-now')));
    expect(n.top, greaterThanOrEqualTo(a.bottom));
    expect(a.height, greaterThanOrEqualTo(48));
    expect(n.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  group('disclosure', () {
    testWidgets('chips per kind, one a11y node, toggle expanded', (
      tester,
    ) async {
      await tester.pumpWidget(
        h.app(
          const Scaffold(
            body: SentDisclosure(segments: _segments, providerName: 'Prov A'),
          ),
          locale: const Locale('en'),
        ),
      );
      await settle(tester);
      final toggle = find.byKey(const ValueKey('sent-disclosure-toggle'));
      expect(find.byType(SentTextView), findsNothing);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      final handle = tester.ensureSemantics();
      SemanticsData data() => tester.getSemantics(toggle).getSemanticsData();
      expect(data().flagsCollection.isExpanded.name, 'isFalse');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('Card 1'), findsOneWidget);
      expect(find.textContaining('Phone number'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Sent: .*Card 1, its number stayed')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('direction follows the first strong character', (tester) async {
      expect(firstStrongDirection(_segments), TextDirection.rtl);
      expect(
        firstStrongDirection(const [
          SentPlaceholder(SentChipKind.bank, 1),
          SentPlain('  How much on '),
        ]),
        TextDirection.ltr,
      );
      expect(firstStrongDirection(const [SentPlain('123')]), isNull);
    });
  });

  group('S-71 row', () {
    Future<void> pump(WidgetTester tester, {bool flag = true}) async {
      await tester.pumpWidget(
        h.app(
          const PrivacyScreen(platform: 'android'),
          overrides: ov(flag: flag),
        ),
      );
      await settle(tester, height: 4000);
    }

    testWidgets('hidden while the flag is off', (tester) async {
      await pump(tester, flag: false);
      expect(find.byKey(const ValueKey('ask-llm-switch')), findsNothing);
      expect(find.textContaining('online helper'), findsNothing);
    });

    testWidgets('on: sheet, Allow, quota unknown line, then off clears', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('ask-llm-quota')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('ask-llm-switch')));
      await tester.tap(find.byKey(const ValueKey('ask-llm-switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consent-preview')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('consent-allow')));
      await tester.pumpAndSettle();
      expect(
        find.text('The count shows after your first online question.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ask-llm-switch')));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => consent.read(LlmFeature.ask)), isNull);
      expect(find.byKey(const ValueKey('ask-llm-quota')), findsNothing);
      expect(
        find.text('Turned off. No question is sent until you allow it again.'),
        findsOneWidget,
      );
    });

    testWidgets('Not now from the switch leaves it off', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ask-llm-switch')));
      await tester.tap(find.byKey(const ValueKey('ask-llm-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('consent-not-now')));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => consent.read(LlmFeature.ask)), isNull);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    });

    testWidgets('quota line hidden while paused', (tester) async {
      await consent.grant(LlmFeature.ask, 'prov-a', 1);
      await quota.pause(LlmFeature.ask);
      await pump(tester);
      expect(find.byKey(const ValueKey('ask-llm-quota')), findsNothing);
    });

    testWidgets('quota line shows the remaining count', (tester) async {
      await consent.grant(LlmFeature.ask, 'prov-a', 1);
      await h.repo.set(
        LlmQuotaSettings.askQuota,
        LlmQuotaSnapshot(
          limit: 5,
          remaining: 3,
          resetsAt: DateTime.now().toUtc().add(const Duration(days: 5)),
        ),
      );
      await pump(tester);
      expect(find.textContaining('3 questions left'), findsOneWidget);
    });

    testWidgets('server-knows list gains the question-text item', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.textContaining('Your question text for the online'),
        findsOneWidget,
      );
      await pump(tester, flag: false);
      expect(
        find.textContaining('Your question text for the online'),
        findsNothing,
      );
    });
  });
}
