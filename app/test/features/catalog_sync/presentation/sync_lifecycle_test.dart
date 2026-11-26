// B96-m4/m5: the categorise hook in SyncLifecycle. Synthetic names only.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_providers.dart';
import 'package:zaghlol/features/catalog_sync/presentation/sync_lifecycle.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_queue.dart';
import 'package:zaghlol/features/categorization/application/llm_cat_sender.dart';
import 'package:zaghlol/features/categorization/data/llm_cat_sender_providers.dart';
import 'package:zaghlol/features/gold/application/entitlement.dart';
import 'package:zaghlol/features/gold/application/gold_providers.dart';

final class _Db extends Fake implements AppDatabase {}

final class _Filler extends Fake implements LlmCatQueueFiller {
  @override
  Future<List<String>> pickForSend({
    required DateTime now,
    required int batchMax,
  }) async => ['synthetic merchant'];
}

final class _Applier extends Fake implements AiSuggestionApplier {}

class _Probe {
  int calls = 0;
  final List<LlmLang> langs = [];
  Completer<void>? hold;
  Object? error;
}

LlmCatSender _sender(_Probe p, {LlmTerms? terms}) => LlmCatSender(
  _Db(),
  filler: _Filler(),
  applier: _Applier(),
  call:
      ({
        required merchants,
        required lang,
        required terms,
        required requestId,
      }) async {
        p.calls++;
        p.langs.add(lang);
        await p.hold?.future;
        throw p.error ?? LlmConsentRequired();
      },
  newRequestId: () => '0AAAAAAAAAAAAAAAAAAAAAAAA1',
  terms: () => terms,
  batchMax: () => 20,
  allowedCategoryIds: () async => {},
);

Future<void> _mount(
  WidgetTester t,
  LlmCatSender s, {
  Locale? locale = const Locale('ar'),
}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        llmCatSenderProvider.overrideWith((ref) async => s),
        appLocaleProvider.overrideWithValue(locale),
        entitlementServiceProvider.overrideWith((ref) => throw StateError('x')),
        purchaseServiceProvider.overrideWith((ref) => throw StateError('x')),
        syncOrchestratorProvider.overrideWith(
          (ref) async => throw StateError('x'),
        ),
      ],
      child: const Directionality(
        textDirection: TextDirection.ltr,
        child: SyncLifecycle(child: SizedBox()),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  const terms = LlmTerms(provider: 'openai-luna', v: 1);

  testWidgets('flag off (no terms): start + resume make zero requests', (
    t,
  ) async {
    final p = _Probe();
    await _mount(t, _sender(p));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 50));
    expect(p.calls, 0);
  });

  testWidgets('foreground + sync burst: at most one send', (t) async {
    final p = _Probe()..hold = Completer<void>();
    await _mount(t, _sender(p, terms: terms));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 50));
    p.hold!.complete();
    await t.pump(const Duration(milliseconds: 50));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 50));
    expect(p.calls, 1);
  });

  testWidgets('language: the app locale setting en gives en', (t) async {
    final p = _Probe();
    await _mount(t, _sender(p, terms: terms), locale: const Locale('en'));
    expect(p.langs, [LlmLang.en]);
  });

  testWidgets('language: the app locale setting ar gives ar', (t) async {
    final p = _Probe();
    await _mount(t, _sender(p, terms: terms), locale: const Locale('ar'));
    expect(p.langs, [LlmLang.ar]);
  });

  testWidgets('a sender error is swallowed and never logged', (t) async {
    final logs = <String?>[];
    final old = debugPrint;
    debugPrint = (m, {wrapWidth}) => logs.add(m);
    final p = _Probe()..error = StateError('merchant Hassan Kosharyx');
    try {
      await _mount(t, _sender(p, terms: terms));
    } finally {
      debugPrint = old;
    }
    expect(p.calls, 1);
    expect(t.takeException(), isNull);
    expect(logs.join(), isNot(contains('Hassan')));
  });
}
