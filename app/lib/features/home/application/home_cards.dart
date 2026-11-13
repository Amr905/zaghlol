// T-104 (FR-ONB-04/10/11): what contextual cards Home shows. Builds the
// [SetupContext] for the T-097 engine from the cycle engine, budgets and
// backup state, and decides on the one-time app-lock offer and the finish
// setup card. No UI here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/application/budget_providers.dart';
import '../../onboarding/application/contextual.dart';
import '../../onboarding/application/setup_steps.dart';
import '../../security/domain/app_lock_controller.dart';

/// Slug in `setup_suggestions_handled` for the app-lock offer (FR-ONB-04).
const String appLockOfferSlug = 'app_lock';

/// A salary-like credit the payday suggestion quotes.
final class SalaryCredit {
  const SalaryCredit(this.date, this.amount);
  final CivilDate date;
  final Money amount;
}

/// Seam: the latest income credit that looks like a salary. No source produces
/// it yet (FU-144), so the payday card stays off until one overrides this.
final setupSalaryCreditProvider = FutureProvider<SalaryCredit?>(
  (ref) async => null,
  name: 'setupSalaryCreditProvider',
);

/// Seam: a backup exists (Drive/iCloud). Overridden when the backup UI lands.
final setupBackupExistsProvider = FutureProvider<bool>(
  (ref) async => false,
  name: 'setupBackupExistsProvider',
);

final setupInstalledOnSettingProvider = settingProvider(
  Settings.setupInstalledOn,
);
final setupHandledProvider = settingProvider(Settings.setupSuggestionsHandled);

/// First-run day: written once, then read back.
final setupInstalledOnProvider = FutureProvider<CivilDate>((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  final stored = await repo.get(Settings.setupInstalledOn);
  if (stored != null) return CivilDate.fromEpochDay(stored);
  final today = ref.read(todayProvider);
  await repo.set(Settings.setupInstalledOn, today.epochDay);
  return today;
}, name: 'setupInstalledOnProvider');

final setupContextProvider = FutureProvider<SetupContext>((ref) async {
  final today = ref.watch(todayProvider);
  final installed = await ref.watch(setupInstalledOnProvider.future);
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final repo = await ref.watch(cycleRepositoryProvider.future);
  final budgets = await repo.cycleBudgets();
  final eras = await ref.watch(paydayErasProvider.future);
  final salary = await ref.watch(setupSalaryCreditProvider.future);
  final backup = await ref.watch(setupBackupExistsProvider.future);
  // The first full cycle starts after the one the user installed in.
  final firstFull = schedule.cycleOn(
    schedule.cycleOn(installed).end.plusDays(1),
  );
  return SetupContext(
    today: today,
    installedOn: installed,
    paydayConfigured: eras != null,
    hasBudgets: budgets.isNotEmpty,
    backupExists: backup,
    latestSalaryCredit: salary?.date,
    firstCycleEnd: firstFull.end,
  );
}, name: 'setupContextProvider');

final class HomeCards {
  const HomeCards({
    this.suggestion,
    this.salary,
    this.offerAppLock = false,
    this.stepsLeft = 0,
  });

  final SetupSuggestion? suggestion;
  final Money? salary;
  final bool offerAppLock;
  final int stepsLeft;

  bool get isEmpty => suggestion == null && !offerAppLock && stepsLeft == 0;
}

/// [hasTransactions]: the app-lock offer waits until there is data to protect.
final homeCardsProvider = FutureProvider.family<HomeCards, bool>((
  ref,
  hasTransactions,
) async {
  final handled = await ref.watch(setupHandledProvider.future);
  final lockOn = await ref.watch(appLockEnabledProvider.future);
  final progress = await ref.watch(setupProgressProvider.future);
  final ctx = await ref.watch(setupContextProvider.future);
  final salary = await ref.watch(setupSalaryCreditProvider.future);
  final s = nextSetupSuggestion(ctx, handled: handled);
  return HomeCards(
    suggestion: s,
    salary: s?.kind == SetupSuggestionKind.payday ? salary?.amount : null,
    offerAppLock:
        hasTransactions && !lockOn && !handled.contains(appLockOfferSlug),
    stepsLeft: stepsLeft(progress).length,
  );
}, name: 'homeCardsProvider');

/// Writes the card actions. Uses providers, never widgets, for storage.
class HomeCardActions {
  HomeCardActions(this._ref);
  final Ref _ref;

  Future<void> handle(SetupSuggestionKind kind) async {
    final repo = await _ref.read(settingsRepositoryProvider.future);
    await SetupSuggestionStore(repo).markHandled(kind);
  }

  Future<void> acceptPayday(int day) async {
    final store = await _ref.read(paydayScheduleStoreProvider.future);
    await store.setPayday(day);
    await handle(SetupSuggestionKind.payday);
  }

  /// Turns app lock on (OS check first). Also hides amounts in notifications
  /// (FU-130). The offer is then spent. Returns the result for the UI.
  Future<EnableLockResult> enableAppLock(String reason) async {
    final r = await _ref
        .read(appLockControllerProvider.notifier)
        .enable(reason);
    if (r == EnableLockResult.enabled) {
      final repo = await _ref.read(settingsRepositoryProvider.future);
      await repo.set(Settings.hideAmountsNotifications, true);
      final now = await repo.get(Settings.setupSuggestionsHandled);
      await repo.set(Settings.setupSuggestionsHandled, {
        ...now,
        appLockOfferSlug,
      });
    }
    return r;
  }
}

final homeCardActionsProvider = Provider<HomeCardActions>(
  HomeCardActions.new,
  name: 'homeCardActionsProvider',
);
