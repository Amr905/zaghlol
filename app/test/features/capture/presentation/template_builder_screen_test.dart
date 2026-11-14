// T-164: S-65 widget tests, ar + en, RTL, text scale 1.3. Synthetic data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/capture/application/template_builder.dart';
import 'package:zaghlol/features/capture/presentation/template_builder_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../settings/settings_harness.dart';

class FakeStore implements TemplateBuilderStore {
  FakeStore({this.history = const [], this.review = const []});

  final List<String> history;
  final List<TemplateSample> review;
  final List<Map<String, Object?>> saved = [];
  bool failSave = false;

  @override
  Future<List<TemplateSample>> reviewSamples() async => review;

  @override
  Future<List<String>> senderHistory(String sender, String channel) async =>
      history;

  @override
  Future<void> saveTemplate({
    required String id,
    required String sender,
    required String channel,
    required Map<String, Object?> template,
    required String sampleHash,
    required int createdAt,
  }) async {
    if (failSave) throw StateError('db');
    saved.add({
      'id': id,
      'sender': sender,
      'channel': channel,
      'template': template,
      'hash': sampleHash,
    });
  }
}

const sampleEn = 'XYZ: You paid 220.00 USD at AMAZON on 23/10';
final similar = [
  'XYZ: You paid 10.00 USD at SHOP A on 01/10',
  'XYZ: You paid 20.00 USD at SHOP B on 02/10',
  'XYZ: Your code is 5555',
];

Widget host(
  SettingsHarness h,
  FakeStore store, {
  String lang = 'en',
  double scale = 1.0,
  bool dark = false,
  List<GoldCapability>? paywall,
}) => h.app(
  const TemplateBuilderScreen(),
  locale: Locale(lang),
  scale: scale,
  dark: dark,
  overrides: [
    templateBuilderStoreProvider.overrideWithValue(store),
    paywallTriggerProvider.overrideWithValue((c) => paywall?.add(c)),
  ],
);

void setGold(WidgetTester t, bool gold) {
  final c = ProviderScope.containerOf(t.element(find.byType(Scaffold).first));
  c.read(entitlementStateProvider.notifier).debugOverride(gold);
}

void bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(1000, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> tapChip(WidgetTester t, String group) async {
  final f = find.byKey(ValueKey('tag_$group'));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pump();
}

void main() {
  for (final lang in ['en', 'ar']) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('empty state, locked for Free ($lang x$scale)', (t) async {
        bigScreen(t);
        final h = SettingsHarness();
        addTearDown(h.db.close);
        final paywall = <GoldCapability>[];
        await t.pumpWidget(
          host(h, FakeStore(), lang: lang, scale: scale, paywall: paywall),
        );
        await t.pumpAndSettle();
        final l = AppLocalizations.of(
          t.element(find.byType(TemplateBuilderScreen)),
        );
        expect(find.text(l.templatesBuilderEmpty), findsOneWidget);
        expect(find.text(l.templatesBuilderLockedBody), findsOneWidget);
        expect(find.text(l.templatesBuilderPrivate), findsOneWidget);
        expect(
          Directionality.of(t.element(find.byType(TemplateBuilderScreen))),
          lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        await t.tap(find.text(l.commonGoldUnlock));
        expect(paywall, [GoldCapability.customSmsRegex]);
        expect(t.takeException(), isNull);
      });

      testWidgets('tag, test and save as Gold ($lang x$scale)', (t) async {
        bigScreen(t);
        final h = SettingsHarness();
        addTearDown(h.db.close);
        final store = FakeStore(history: similar);
        await t.pumpWidget(host(h, store, lang: lang, scale: scale));
        await t.pumpAndSettle();
        setGold(t, true);
        await t.pump();
        final l = AppLocalizations.of(
          t.element(find.byType(TemplateBuilderScreen)),
        );

        await t.enterText(find.byType(TextField).first, sampleEn);
        await t.pump();
        // Words: XYZ(0) You(1) paid(2) 220.00(3) USD(4) at(5) AMAZON(6) ...
        await t.tap(find.byKey(const ValueKey('token_3')));
        await t.pump();
        await tapChip(t, 'amount');
        await t.tap(find.byKey(const ValueKey('token_4')));
        await t.pump();
        await tapChip(t, 'cur');
        await t.tap(find.byKey(const ValueKey('token_6')));
        await t.pump();
        await tapChip(t, 'merchant');
        await t.enterText(find.byType(TextField).last, 'XYZ');
        await t.pumpAndSettle();

        final done = '2';
        final total = '3';
        expect(
          find.textContaining(
            l.templatesBuilderTestResult(
              lang == 'ar' ? '٢' : done,
              lang == 'ar' ? '٣' : total,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(l.templatesBuilderTestFailTitle), findsOneWidget);

        await t.ensureVisible(find.text(l.templatesBuilderSave));
        await t.tap(find.text(l.templatesBuilderSave));
        await t.pumpAndSettle();
        expect(store.saved, hasLength(1));
        final row = store.saved.single;
        expect(row['sender'], 'XYZ');
        expect(row['hash'], matches(RegExp(r'^[0-9a-f]{64}$')));
        final json = row['template']! as Map<String, Object?>;
        expect(CustomTemplateSpec.fromJson(json), isNotNull);
        // The tagged values never reach storage.
        expect(json.toString(), isNot(contains('220.00')));
        expect(json.toString(), isNot(contains('AMAZON')));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('range selection: two taps tag a multi-word merchant', (t) async {
    bigScreen(t);
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final store = FakeStore();
    await t.pumpWidget(host(h, store));
    await t.pumpAndSettle();
    setGold(t, true);
    await t.pump();
    await t.enterText(
      find.byType(TextField).first,
      'XYZ: paid 50.00 EGP at Test Cafe Cairo today',
    );
    await t.pump();
    // XYZ(0) paid(1) 50.00(2) EGP(3) at(4) Test(5) Cafe(6) Cairo(7) today(8)
    await t.tap(find.byKey(const ValueKey('token_2')));
    await tapChip(t, 'amount');
    await t.tap(find.byKey(const ValueKey('token_5')));
    await t.tap(find.byKey(const ValueKey('token_6')));
    await tapChip(t, 'merchant');
    await t.enterText(find.byType(TextField).last, 'XYZ');
    await t.pumpAndSettle();
    final l = AppLocalizations.of(
      t.element(find.byType(TemplateBuilderScreen)),
    );
    await t.ensureVisible(find.text(l.templatesBuilderSave));
    await t.tap(find.text(l.templatesBuilderSave));
    await t.pumpAndSettle();
    expect(store.saved, hasLength(1));
  });

  testWidgets('save without amount or sender shows the field errors', (
    t,
  ) async {
    bigScreen(t);
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final store = FakeStore();
    await t.pumpWidget(host(h, store));
    await t.pumpAndSettle();
    setGold(t, true);
    await t.pump();
    final l = AppLocalizations.of(
      t.element(find.byType(TemplateBuilderScreen)),
    );
    await t.enterText(find.byType(TextField).first, sampleEn);
    await t.pump();
    await t.ensureVisible(find.text(l.templatesBuilderSave));
    await t.tap(find.text(l.templatesBuilderSave));
    await t.pump();
    expect(find.text(l.templatesBuilderErrorAmount), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('token_3')));
    await tapChip(t, 'amount');
    await t.ensureVisible(find.text(l.templatesBuilderSave));
    await t.tap(find.text(l.templatesBuilderSave));
    await t.pump();
    expect(find.text(l.templatesBuilderErrorSender), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('a Free user cannot save even through the controller', (t) async {
    bigScreen(t);
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final store = FakeStore();
    final paywall = <GoldCapability>[];
    await t.pumpWidget(host(h, store, paywall: paywall));
    await t.pumpAndSettle();
    final c = ProviderScope.containerOf(
      t.element(find.byType(TemplateBuilderScreen)),
    );
    final ok = await c.read(templateBuilderProvider.notifier).save();
    expect(ok, isFalse);
    expect(paywall, [GoldCapability.customSmsRegex]);
    expect(store.saved, isEmpty);
  });

  testWidgets('picking from the review queue fills sample and sender', (
    t,
  ) async {
    bigScreen(t);
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final store = FakeStore(
      history: similar,
      review: const [
        TemplateSample(sender: 'XYZ', channel: 'sms', body: sampleEn),
      ],
    );
    await t.pumpWidget(host(h, store));
    await t.pumpAndSettle();
    setGold(t, true);
    await t.pump();
    final l = AppLocalizations.of(
      t.element(find.byType(TemplateBuilderScreen)),
    );
    await t.tap(find.text(l.templatesBuilderFromReview));
    await t.pumpAndSettle();
    await t.tap(find.text('XYZ').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('token_3')), findsOneWidget);
    expect(find.text('XYZ'), findsWidgets);
  });

  test('state and sample toString are redacted', () {
    expect(
      const TemplateBuilderState(sample: 'secret').toString(),
      isNot(contains('secret')),
    );
    expect(
      const TemplateSample(
        sender: 's',
        channel: 'sms',
        body: 'secret',
      ).toString(),
      isNot(contains('secret')),
    );
  });
}
