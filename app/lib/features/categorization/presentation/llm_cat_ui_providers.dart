// T-362: state of the auto-category UI (FR-LCAT-40…44): the discovery card's
// frequency rule, the consent state against the active terms, the quota hint
// and the queue size. Reads only; the one write path is [LlmCatCardActions].
// Nothing here sends anything or logs a merchant name.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/llm_cat_queue_dao.dart';
import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/llm/llm_feature.dart';
import '../../../core/llm/llm_gateway_client.dart';
import '../../../core/llm/llm_quota_snapshot.dart';
import '../../../core/settings/setting_key.dart';
import '../../../core/settings/settings_providers.dart';
import '../data/llm_cat_providers.dart';

/// The card is shown at most this many times, at least this far apart.
const int catCardMaxShown = 3;
const Duration catCardCoolDown = Duration(days: 30);

/// The card needs at least this many distinct eligible merchants.
const int catCardMinMerchants = 3;

/// Settings keys of the card (llm-categorise §7).
abstract final class CatCardSettings {
  /// How many days the card was shown (or dismissed with "Not now").
  static final shown = SettingKey.integer(
    'cat.card_shown',
    byDefault: 0,
    min: 0,
    max: 1000,
  );

  /// When the card was last dismissed (UTC ms); null before the first time.
  static final lastShown = SettingKey.optionalInteger(
    'cat.card_last_shown',
    min: 0,
    max: 1 << 52,
  );

  /// The day (UTC days since epoch) a showing was last counted.
  static final lastCounted = SettingKey.optionalInteger(
    'cat.card_last_counted',
    min: 0,
    max: 1 << 40,
  );

  /// "Don't ask again".
  static final never = SettingKey.boolean('cat.card_never', byDefault: false);
}

/// The card's frequency rule (pure): enough merchants, not "never", fewer
/// than [catCardMaxShown] showings, [catCardCoolDown] since the last one.
bool catCardDue({
  required int eligible,
  required int shown,
  required int? lastShownMs,
  required bool never,
  required DateTime now,
}) {
  if (never || eligible < catCardMinMerchants) return false;
  if (shown >= catCardMaxShown) return false;
  if (lastShownMs != null) {
    final since = now.toUtc().millisecondsSinceEpoch - lastShownMs;
    if (since < catCardCoolDown.inMilliseconds) return false;
  }
  return true;
}

/// True while the stored categorise consent covers the active terms.
/// Invalidate after granting or clearing.
final catConsentGrantedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final terms = ref.watch(llmCatTermsProvider);
  if (terms == null) return false;
  final store = await ref.watch(llmConsentStoreProvider.future);
  return await store.grantFor(LlmFeature.categorise, terms.provider, terms.v) !=
      null;
}, name: 'catConsentGrantedProvider');

/// Distinct merchants that would be sent, counted before any consent.
final catEligibleCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final filler = await ref.watch(llmCatQueueFillerProvider.future);
  return filler.countEligible(now: DateTime.now());
}, name: 'catEligibleCountProvider');

/// The quota hint and the paused mark of the categorise feature.
typedef CatQuotaState = ({LlmQuotaSnapshot? snapshot, bool paused});

final catQuotaStateProvider = FutureProvider.autoDispose<CatQuotaState>((
  ref,
) async {
  final store = await ref.watch(llmQuotaStoreProvider.future);
  final paused = await store.isPaused(LlmFeature.categorise);
  final snap = await store.current(LlmFeature.categorise, DateTime.now());
  return (snapshot: snap, paused: paused);
}, name: 'catQuotaStateProvider');

/// Rows waiting in the send queue.
final catQueueSizeProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return LlmCatQueueDao(db).count();
}, name: 'catQueueSizeProvider');

/// Flag on in a fresh snapshot and the provider known: the only state in
/// which the feature may be offered at all (FU-425: with unknown terms a
/// consent could not be honoured).
final catFeatureOfferedProvider = Provider.autoDispose<bool>(
  (ref) =>
      ref.watch(featureFlagProvider(FeatureFlag.llmCategorise)) &&
      ref.watch(llmCatTermsProvider) != null,
  name: 'catFeatureOfferedProvider',
);

/// Whether the discovery card shows now.
final catCardVisibleProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!ref.watch(catFeatureOfferedProvider)) return false;
  final repo = await ref.watch(settingsRepositoryProvider.future);
  final never = await repo.get(CatCardSettings.never);
  final shown = await repo.get(CatCardSettings.shown);
  final last = await repo.get(CatCardSettings.lastShown);
  if (never || shown >= catCardMaxShown) return false;
  if (await ref.watch(catConsentGrantedProvider.future)) return false;
  final eligible = await ref.watch(catEligibleCountProvider.future);
  return catCardDue(
    eligible: eligible,
    shown: shown,
    lastShownMs: last,
    never: never,
    now: DateTime.now(),
  );
}, name: 'catCardVisibleProvider');

/// The card's showings, "Not now" and "Don't ask again".
abstract final class LlmCatCardActions {
  /// Counts a showing, at most once per (UTC) day, when the card is on
  /// screen; an ignored card then runs out after [catCardMaxShown] days.
  /// Does not invalidate the visibility provider (the card stays up today).
  static Future<void> countShowing(WidgetRef ref, {DateTime? now}) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    final t = (now ?? DateTime.now()).toUtc();
    final last = await repo.get(CatCardSettings.lastCounted);
    final day = t.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    if (last == day) return;
    await repo.set(CatCardSettings.lastCounted, day);
    final shown = await repo.get(CatCardSettings.shown);
    await repo.set(CatCardSettings.shown, shown + 1);
  }

  static Future<void> notNow(WidgetRef ref, {DateTime? now}) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await countShowing(ref, now: now); // no double count on the same day
    await repo.set(
      CatCardSettings.lastShown,
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
    );
    ref.invalidate(catCardVisibleProvider);
  }

  static Future<void> never(WidgetRef ref) async {
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.set(CatCardSettings.never, true);
    ref.invalidate(catCardVisibleProvider);
  }
}

/// A count in the user's digits (Arabic-Indic or Western), for ICU `{n}`.
String catCount(BuildContext context, WidgetRef ref, int n) {
  final lang = Localizations.localeOf(context).languageCode;
  return ref.watch(digitsModeProvider(lang)).render('$n');
}
