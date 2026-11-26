// T-367 (FU-425/FU-431): the one terms provider and what feeds off it.
// Synthetic data only.
//
// AC -> test map
//  AC1 one provider from the synced config only: 'terms come only from ...'
//  AC2 askConsentTermsProvider (wiring), askLlmTermsProvider and
//      llmCatTermsProvider name the same id/version: 'one value feeds ...'
//  AC3 no id / no names / bad id / stale -> null: 'fail closed ...'
//  AC4 a provider switch no longer matches the stored consent: 'a switch ...'
//  AC5 cursor reset, 409 never changes the stored provider: remote_config_test
//      ('resetCursor'), llm_ask_flow_test and llm_cat_sender_test ('409 ...')

import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/ask_wiring.dart';
import 'package:zaghlol/core/config/remote_config.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/config/remote_config_providers.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_provider_terms.dart';
import 'package:zaghlol/features/ask/application/llm_ask_flow.dart';
import 'package:zaghlol/features/ask/data/llm_ask_providers.dart';
import 'package:zaghlol/features/ask/presentation/consent_sheet.dart';
import 'package:zaghlol/features/categorization/data/llm_cat_providers.dart';

Map<String, dynamic> _block(String name) =>
    ((jsonDecode(
              File('test/fixtures/llm/sync-config-provider-v1.json')
                  .readAsStringSync(),
            ) as Map)['blocks']
            as Map)[name]
        as Map<String, dynamic>;

RemoteConfig _config(String name) {
  final b = _block(name);
  final n = b['providerName'] as Map<String, dynamic>?;
  return RemoteConfig.fromValues(
    (b['values'] as Map).cast<String, String>(),
    providerName: n == null
        ? null
        : LlmProviderNames(ar: n['ar'] as String, en: n['en'] as String),
  );
}

ProviderContainer _container(RemoteConfig c) {
  final k = ProviderContainer(
    overrides: [
      remoteConfigProvider.overrideWith((ref) => Stream.value(c)),
      appLocaleProvider.overrideWithValue(const Locale('ar')),
      ...askLlmWiringOverrides,
    ],
  );
  addTearDown(k.dispose);
  return k;
}

Future<ProviderContainer> _ready(RemoteConfig c) async {
  final k = _container(c);
  k.listen(remoteConfigProvider, (_, _) {});
  await k.read(remoteConfigProvider.future);
  return k;
}

void main() {
  test('terms come only from the synced config block', () async {
    final k = await _ready(_config('luna'));
    final t = k.read(llmProviderTermsProvider)!;
    expect(t.id, 'openai-luna');
    expect(t.nameFor('ar'), 'لونا');
    expect(t.nameFor('en'), 'Luna AI');
  });

  test('one value feeds the sheet, the Ask flow and the categoriser', () async {
    final k = await _ready(_config('luna'));
    final sheet = k.read(askConsentTermsProvider)!;
    final ask = k.read(askLlmTermsProvider)!;
    final cat = k.read(llmCatTermsProvider)!;
    expect(sheet.providerId, 'openai-luna');
    expect(sheet.providerName, 'لونا');
    expect(sheet.version, askLlmConsentVersion);
    expect(ask.provider, sheet.providerId);
    expect(ask.v, sheet.version);
    expect(cat.provider, sheet.providerId);
  });

  for (final name in ['noNames', 'noId', 'emptyArName', 'badId']) {
    test('fail closed: $name gives no terms anywhere', () async {
      final k = await _ready(_config(name));
      expect(k.read(llmProviderTermsProvider), isNull);
      expect(k.read(askConsentTermsProvider), isNull);
      expect(k.read(askLlmTermsProvider), isNull);
      expect(k.read(llmCatTermsProvider), isNull);
    });
  }

  test(
    'fail closed: stale or missing config (defaults) gives no terms',
    () async {
      final k = await _ready(RemoteConfig.defaults);
      expect(k.read(askLlmTermsProvider), isNull);
      expect(k.read(llmCatTermsProvider), isNull);
      expect(k.read(askConsentTermsProvider), isNull);
    },
  );

  test('a switch of provider no longer matches the stored consent', () async {
    const old = LlmConsentGrant(provider: 'openai-luna', v: 1, atMs: 1);
    final a = await _ready(_config('luna'));
    expect(
      old.covers(
        a.read(askLlmTermsProvider)!.provider,
        a.read(askLlmTermsProvider)!.v,
      ),
      isTrue,
    );
    final b = await _ready(_config('switched'));
    final t = b.read(askLlmTermsProvider)!;
    expect(t.provider, 'other-prov');
    expect(old.covers(t.provider, t.v), isFalse);
    expect(b.read(askConsentTermsProvider)!.providerName, 'تانية');
  });
}
