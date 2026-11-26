// T-357: Riverpod wiring (ADR-001) of the auto-category queue and the
// suggestion applier. The sender (T-358) reads:
//   final q = await ref.read(llmCatQueueFillerProvider.future);
//   final keys = await q.pickForSend(now: nowUtc, batchMax: cfg.catBatchMax);
//   final a = await ref.read(aiSuggestionApplierProvider.future);
//   await a.accept(...) / a.noAnswer(...);
// Nothing here sends or logs.

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/config/remote_config_providers.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../ingestion/bundled_registry.dart';
import '../application/llm_cat_queue.dart';
import 'categorizer_ports.dart';
import 'rules_providers.dart';

/// Loads the three name lists (assets/data, T-325). A missing file throws;
/// an empty one makes the eligibility rule refuse everything.
Future<NameLexicon> loadNameLexicon(AssetBundle bundle) async =>
    NameLexicon.fromLines(
      givenNames: await bundle.loadString('assets/data/eg_given_names.txt'),
      honorifics: await bundle.loadString('assets/data/eg_honorifics.txt'),
      businessWords: await bundle.loadString(
        'assets/data/eg_business_words.txt',
      ),
    );

final nameLexiconProvider = FutureProvider<NameLexicon>(
  (ref) => loadNameLexicon(rootBundle),
  name: 'nameLexiconProvider',
);

/// The auto-category consent terms: the remote config's provider id at
/// [catLlmConsentVersion]. Null while the provider isn't known.
final llmCatTermsProvider = Provider<LlmTerms?>((ref) {
  final p = ref.watch(remoteConfigProvider).value?.llmProvider ?? '';
  return p.isEmpty ? null : LlmTerms(provider: p, v: catLlmConsentVersion);
}, name: 'llmCatTermsProvider');

final llmCatQueueFillerProvider = FutureProvider<LlmCatQueueFiller>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final flags = await ref.watch(flagsServiceProvider.future);
  final consent = await ref.watch(llmConsentStoreProvider.future);
  final quota = await ref.watch(llmQuotaStoreProvider.future);
  final registry = await preloadBundledRegistry();
  final events = {
    for (final i in registry.institutions)
      for (final t in i.templates) t.id: t.event,
  };
  return LlmCatQueueFiller(
    db,
    templateEvents: () => events,
    gate: LlmCatGate(
      isFlagOn: () => flags.isOn(FeatureFlag.llmCategorise),
      hasConsent: () async {
        final t = ref.read(llmCatTermsProvider);
        return t != null &&
            await consent.grantFor(LlmFeature.categorise, t.provider, t.v) !=
                null;
      },
      quota: quota,
    ),
    lexicon: () => ref.read(nameLexiconProvider.future),
  );
}, name: 'llmCatQueueFillerProvider');

final aiSuggestionApplierProvider = FutureProvider<AiSuggestionApplier>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final rules = await ref.watch(rulesRepositoryProvider.future);
  return AiSuggestionApplier(
    db,
    newCategorizer: () => Categorizer(driftCategorizerPorts(db, rules)),
  );
}, name: 'aiSuggestionApplierProvider');
