// T-343: Riverpod wiring of the online Ask flow. No presentation code here.
// For the consent sheet (T-345) and the chat (T-346):
//   - override [consentPrompterProvider] with the sheet (the default declines,
//     so nothing is ever sent without one);
//   - [askLlmTermsProvider] is the provider id and consent version the sheet
//     must record; null while the provider isn't known (nothing is sent);
//   - [askQuotaSnapshotProvider] feeds the counter ("-" when null);
//   - [llmAskFlowProvider] gives the flow: `flow.ask(text, stop: signal)`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/config/remote_config_providers.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/llm/llm_provider_terms.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../ingestion/bundled_registry.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../catalog_sync/application/sync_providers.dart'
    show llmConfigResyncProvider;
import '../../wealth/data/prices_providers.dart';
import '../../wealth/domain/price_feed.dart' show Approx;
import '../../insights/data/chart_providers.dart';
import '../application/llm_ask_flow.dart';
import '../application/plan_executor.dart';
import 'ask_entities_source.dart';
import 'ask_providers.dart';
import 'llm_ask_client.dart';
import 'mask_sources_drift.dart';

/// The consent sheet. T-345 overrides this; the default says "Not now".
final consentPrompterProvider = Provider<ConsentPrompter>(
  (ref) => const DecliningConsentPrompter(),
  name: 'consentPrompterProvider',
);

/// Whether the phone has a network. No connectivity plugin is in the app, so
/// the default is "yes" and a send that can't connect ends as offline with
/// nothing queued (`LlmOffline`).
final askOnlineCheckProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () async => true,
  name: 'askOnlineCheckProvider',
);

/// The terms the user agrees to: the one provider of
/// [llmProviderTermsProvider] at the sheet's version. Null while the provider
/// or its names aren't known (nothing is sent).
final askLlmTermsProvider = Provider<LlmTerms?>((ref) {
  final p = ref.watch(llmProviderTermsProvider);
  return p == null ? null : LlmTerms(provider: p.id, v: askLlmConsentVersion);
}, name: 'askLlmTermsProvider');

/// The stored quota snapshot (null: unknown or past `resetsAt`).
final askQuotaSnapshotProvider = FutureProvider<LlmQuotaSnapshot?>((ref) async {
  final store = await ref.watch(llmQuotaStoreProvider.future);
  return store.current(LlmFeature.ask, DateTime.now().toUtc());
}, name: 'askQuotaSnapshotProvider');

/// FU-426: the gold and USD/EGP quotes of the wealth price feed, for the
/// investment illustrations. A price the feed doesn't have is simply left out:
/// the band that needs it is not shown (never guessed). A failed read gives no
/// quotes at all.
final askInvestPricesProvider = FutureProvider<InvestPrices>((ref) async {
  final rate = ref.watch(remoteConfigProvider).value?.cdExampleRateBp ?? 2000;
  final egp = Currency.of('EGP');
  try {
    final repo = await ref.watch(pricesRepositoryProvider.future);
    final gold = <GoldQuote>[];
    for (final karat in const [24, 21, 18]) {
      final symbol = GoldSymbols.forKarat(karat);
      if (symbol == null) continue;
      final q = await repo.price(symbol, egp);
      if (q == null || q.perUnit != 'g' || q.price.currency != egp) continue;
      gold.add(
        GoldQuote(
          karat: karat,
          pricePerGram: q.price,
          asOf: DateTime.fromMillisecondsSinceEpoch(q.asOfMs, isUtc: true),
        ),
      );
    }
    final usd = Currency.of('USD');
    final fx = await repo.convertApprox(Money(usd, 100), egp);
    return InvestPrices(
      gold: gold,
      usdEgp: fx is Approx && fx.asOfMs != null
          ? InvestFxQuote(
              egpPerUsd: fx.amount,
              asOf: DateTime.fromMillisecondsSinceEpoch(
                fx.asOfMs!,
                isUtc: true,
              ),
            )
          : null,
      certificateRateBp: rate,
    );
  } on Object {
    return InvestPrices(certificateRateBp: rate);
  }
}, name: 'askInvestPricesProvider');

final planExecutorProvider = FutureProvider<PlanExecutor>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final charts = await ref.watch(chartRepositoryProvider.future);
  final accounts = await ref.watch(accountsRepositoryProvider.future);
  final cycles = await ref.watch(cycleRepositoryProvider.future);
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final cfg = ref.watch(remoteConfigProvider).value;
  return PlanExecutor(
    charts: charts,
    accounts: () => accounts.listWithBalances(includeHidden: true),
    cycleBudgets: cycles.cycleBudgets,
    schedule: () async => schedule,
    entities: () =>
        loadAskEntities(db, () => accounts.list(includeHidden: true)),
    today: () => ref.read(todayProvider),
    prices: () => ref.read(askInvestPricesProvider.future),
    now: DateTime.now,
    suggestThresholds: SuggestThresholds(
      s1Pct: cfg?.s1Pct ?? 15,
      s4SharePct: cfg?.s4SharePct ?? 20,
      s4SavingPct: cfg?.s4SavingPct ?? 25,
    ),
  );
}, name: 'planExecutorProvider');

final llmAskFlowProvider = FutureProvider<LlmAskFlow>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final accounts = await ref.watch(accountsRepositoryProvider.future);
  final engine = await ref.watch(askEngineProvider.future);
  final executor = await ref.watch(planExecutorProvider.future);
  final flags = await ref.watch(flagsServiceProvider.future);
  final gateway = await ref.watch(llmGatewayClientProvider.future);
  final registry = await preloadBundledRegistry();
  final names = [for (final i in registry.institutions) InstitutionNames.of(i)];
  return LlmAskFlow(
    local: engine.ask,
    sources: () => MaskSourcesDrift.load(
      db,
      accounts: () => accounts.list(includeHidden: true),
      registry: names,
    ),
    client: GatewayLlmAskClient(gateway),
    execute: executor.execute,
    consent: await ref.watch(llmConsentStoreProvider.future),
    quota: await ref.watch(llmQuotaStoreProvider.future),
    prompter: ref.watch(consentPrompterProvider),
    isFlagOn: () => flags.isOn(FeatureFlag.askLlm),
    terms: () => ref.read(askLlmTermsProvider),
    resyncConfig: ref.read(llmConfigResyncProvider),
    now: () => DateTime.now().toUtc(),
    isOnline: ref.watch(askOnlineCheckProvider),
  );
}, name: 'llmAskFlowProvider');
