// WIRE-NAV: the composition of navigation. Every screen's entry-point
// callback is bound here, in one place; screens keep their own internals.
// `main.dart` passes [wiredTabRoots] to `tabRootsProvider` and
// [navigationWiringOverrides] to the root ProviderScope.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';

import '../core/routing/app_router.dart';
import '../core/routing/app_routes.dart';
import '../core/ui/shell/add_sheet.dart' show AddAction;
import '../core/settings/settings_keys.dart';
import '../core/settings/settings_providers.dart';
import '../features/account/presentation/account_launcher.dart';
import '../features/accounts/data/accounts_providers.dart';
import '../features/accounts/domain/account.dart';
import '../features/accounts/presentation/money_tab.dart';
import '../features/gold/application/gating.dart';
import '../features/gold/presentation/gold_ui_ports.dart';
import '../features/gold/presentation/paywall_launcher.dart';
import '../features/home/application/card_filter.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/insights/presentation/charts/charts_providers.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/onboarding/application/setup_steps.dart';
import '../features/onboarding/presentation/android_setup.dart';
import '../features/onboarding/presentation/ios_setup.dart'
    show kSetupStepIosShortcuts;
import '../features/settings/presentation/settings_main_screen.dart';
import '../features/settings/presentation/settings_ports.dart';
import '../features/transactions/presentation/edit/transaction_edit_screen.dart';
import '../features/transactions/presentation/list/txn_list_providers.dart';
import '../features/transfers/presentation/assign_sheet.dart';
import '../features/transfers/presentation/link_transfer_sheet.dart';
import '../features/transfers/presentation/split_sheet.dart';
import 'app_config.dart';
import 'app_screens.dart';

ProviderContainer _container(BuildContext context) =>
    ProviderScope.containerOf(context);

AppScreens _screens(BuildContext context) =>
    _container(context).read(appScreensProvider);

bool _isIos(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// Tab roots and pushed routes of the shell (T-024), with every entry point
/// wired.
final TabRoots wiredTabRoots = TabRoots(
  home: (context) => HomeScreen(actions: _homeActions(context)),
  insights: (context) => insightsTabRoot(context),
  money: (context) => _moneyTab(context),
  zaghlol: (context) => _screens(context).ask(context),
  review: (context) => _screens(context).review(context),
  transactions: (context) => _screens(context).transactions(
    context,
    onOpenTransaction: (id) => openTransactionDetail(context, id),
  ),
  addSelected: wiredAddSelected,
);

/// S-30 entries: Type opens S-13; Asset opens S-44 for Gold and the paywall
/// (S-68) for Free (T-082); the rest only close the sheet.
void wiredAddSelected(BuildContext context, AddAction action) {
  if (action != AddAction.asset) {
    quickAddSelected(context, action);
    return;
  }
  final gold = _container(context).read(entitlementStateProvider).isGold;
  final screens = _screens(context);
  Navigator.of(context, rootNavigator: true).maybePop();
  unawaited(gold ? screens.addAsset(context) : screens.paywall(context));
}

/// Root-scope overrides of the navigation seams other features expose as
/// providers. [navigatorKey] is the root navigator.
List<Override> navigationWiringOverrides(
  GlobalKey<NavigatorState> navigatorKey,
) => [
  // T-146: a blocked gate opens the paywall.
  paywallTriggerOverride(navigatorKey),
  // T-147: the "Sign in" buttons of the Gold messages open S-69.
  goldSignInOpenerOverride(navigatorKey),
  // T-146: terms, privacy and the store's subscription page.
  goldLinkOpenerProvider.overrideWith(
    (ref) => (link) {
      final url = switch (link) {
        GoldLink.terms => AppLinks.terms,
        GoldLink.privacy => AppLinks.privacy,
        GoldLink.manageSubscription => AppLinks.manageSubscription,
      };
      unawaited(ref.read(externalUrlOpenerProvider)(Uri.parse(url)));
    },
  ),
  // T-101: a card row of the cards split chart opens S-41.
  chartCardOpenerProvider.overrideWith(
    (ref) =>
        (context, accountId) =>
            unawaited(openCardDetailById(context, accountId)),
  ),
  // T-162: live status rows of Settings.
  goldPlanProvider.overrideWith(
    (ref) => ref.watch(goldStatusInfoProvider).value?.plan?.key,
  ),
  setupStepsLeftProvider.overrideWith(
    (ref) =>
        stepsLeft(ref.watch(setupProgressProvider).value ?? const <String>{})
            .length,
  ),
];

// ---------------------------------------------------------------- Home

HomeActions _homeActions(BuildContext context) => HomeActions(
  openSettings: () => unawaited(openSettings(context)),
  openBudget: () => unawaited(openBudget(context)),
  openSetBudget: () => unawaited(openBudget(context)),
  openTransactions: () => unawaited(context.push(AppRoutes.transactions)),
  openSpentTransactions: () => unawaited(context.push(AppRoutes.transactions)),
  openTransaction: (id) => unawaited(openTransactionDetail(context, id)),
  openBackup: () => unawaited(openBackup(context)),
  openFinishSetup: () => unawaited(openFinishSetup(context)),
  openCaptureSettings: () => unawaited(openCaptureSettings(context)),
  openShare: () => unawaited(_screens(context).shareStudio(context)),
);

Future<void> openBudget(BuildContext context) => _screens(context).budget(
  context,
  onCategoryTap: (categoryId, _) => unawaited(
    pushScreen<void>(
      context,
      (_) => _FilteredTransactions(categoryId: categoryId),
    ),
  ),
);

/// S-11 opened with a category filter. The list filter is auto-disposed, so
/// this host holds it before the list reads it.
class _FilteredTransactions extends ConsumerStatefulWidget {
  const _FilteredTransactions({required this.categoryId});
  final String categoryId;

  @override
  ConsumerState<_FilteredTransactions> createState() =>
      _FilteredTransactionsState();
}

class _FilteredTransactionsState extends ConsumerState<_FilteredTransactions> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(txnListFilterProvider, (_, _) {});
    final f = ref.read(txnListFilterProvider);
    ref
        .read(txnListFilterProvider.notifier)
        .set(
          f.copyWith(
            period: TxnPeriod.thisCycle,
            categoryIds: {widget.categoryId},
          ),
        );
  }

  @override
  Widget build(BuildContext context) => _screens(context).transactions(
    context,
    onOpenTransaction: (id) => openTransactionDetail(context, id),
  );
}

Future<void> openTransactionDetail(BuildContext context, String id) =>
    _screens(context).transactionDetail(
      context,
      id,
      onSplit: (id) => unawaited(showSplitSheet(context, id)),
      onLinkTransfer: (id) => unawaited(showLinkTransferSheet(context, id)),
      onMoneyBackFor: (id) => unawaited(showAssignSheet(context, id)),
    );

// --------------------------------------------------------------- Money

Widget _moneyTab(BuildContext context) => MoneyTab(
  onAdd: () => unawaited(
    _screens(context).startAddCard(
      context,
      onSaved: (a) => unawaited(openCardDetailFor(context, a)),
      onOpenExisting: (a) => unawaited(openCardDetailFor(context, a)),
    ),
  ),
  onOpenAccount: (a) => unawaited(openCardDetailFor(context, a)),
  onCompare: () => unawaited(
    _screens(context).compareCards(
      context,
      onOpenTransactions: () => unawaited(context.push(AppRoutes.transactions)),
    ),
  ),
  onOpenAssetsPaywall: () => unawaited(_screens(context).paywall(context)),
  onAddAsset: () => unawaited(_screens(context).addAsset(context)),
  onOpenPrices: () => unawaited(_screens(context).prices(context)),
);

Future<void> openCardDetailFor(BuildContext context, Account account) =>
    _screens(context).cardDetail(
      context,
      account,
      onOpenTransactions: () {
        // S-41 "All card transactions": show only this card.
        _container(context)
            .read(cardFilterProvider.notifier)
            .selectOnly(account.id);
        unawaited(context.push(AppRoutes.transactions));
      },
      onOpenTransaction: (id) => unawaited(openTransactionDetail(context, id)),
    );

/// The chart's card rows only know the id.
Future<void> openCardDetailById(BuildContext context, String accountId) async {
  final repo = await _container(context)
      .read(accountsRepositoryProvider.future);
  final account = await repo.byId(accountId);
  if (account == null || !context.mounted) return;
  await openCardDetailFor(context, account);
}

/// S-43 for [accountId]: opened from the scan results (edit / set up credit).
Future<void> openEditCardById(BuildContext context, String accountId) async {
  final repo = await _container(context)
      .read(accountsRepositoryProvider.future);
  final account = await repo.byId(accountId);
  if (account == null || !context.mounted) return;
  await _screens(context).editCard(
    context,
    account,
    onOpenCapture: (a) =>
        unawaited(_screens(context).cardCaptureSheet(context, a)),
  );
}

// ------------------------------------------------------------ Settings

Future<void> openSettings(BuildContext context) =>
    _screens(context).settings(context, settingsDestinations(context));

SettingsDestinations settingsDestinations(BuildContext context) =>
    SettingsDestinations(
      onGold: () => unawaited(_screens(context).paywall(context)),
      onFinishSetup: () => unawaited(openFinishSetup(context)),
      onCapture: () => unawaited(openCaptureSettings(context)),
      onCategories: () => unawaited(_screens(context).categories(context)),
      onBackup: () => unawaited(openBackup(context)),
      onAccount: () => unawaited(_screens(context).account(context)),
    );

Future<void> openCaptureSettings(BuildContext context) =>
    _screens(context).captureSettings(
      context,
      goldActive: _container(context).read(entitlementStateProvider).isGold,
      onOpenTemplates: () {
        // Custom templates are Gold: Free users meet the paywall instead.
        if (!_container(context).read(entitlementStateProvider).isGold) {
          unawaited(_screens(context).paywall(context));
          return;
        }
        unawaited(_screens(context).templateBuilder(context));
      },
    );

Future<void> openBackup(BuildContext context) => _screens(context).backup(
  context,
  iCloud: _isIos(context),
  onOpenRestore: () =>
      unawaited(openRestore(context, replacesExistingData: true)),
);

Future<void> openRestore(
  BuildContext context, {
  void Function({required bool regrantDue})? onRestored,
  bool replacesExistingData = false,
}) => _screens(context).restore(
  context,
  replacesExistingData: replacesExistingData,
  iCloud: _isIos(context),
  onRestored:
      onRestored ??
      ({required bool regrantDue}) =>
          Navigator.of(context).popUntil((r) => r.isFirst),
  onStartFresh: () => Navigator.of(context).maybePop(),
  onUpdateApp: () => unawaited(
    _container(context)
        .read(externalUrlOpenerProvider)(Uri.parse(AppLinks.storePage)),
  ),
);

/// "Finish setup" (Home card, Settings row): the Android permission steps
/// again. iOS has no such screen yet.
Future<void> openFinishSetup(BuildContext context) async {
  if (_isIos(context)) {
    await pushScreen<void>(
      context,
      (ctx) => iosSetupScreen(
        ctx,
        onDone: () => Navigator.of(ctx).maybePop(),
        onSkipped: (slug) {
          unawaited(recordSetupSkip(_container(ctx), slug));
          Navigator.of(ctx).maybePop();
        },
      ),
    );
    return;
  }
  await pushScreen<void>(
    context,
    (ctx) => _screens(ctx).androidSetup(
      onDone: () => Navigator.of(ctx).maybePop(),
      onSkipped: (slug) {
        unawaited(recordSetupSkip(_container(ctx), slug));
        Navigator.of(ctx).maybePop();
      },
    ),
  );
}

/// S-03 with its first-expense and online-bank-help exits wired. Voice entry
/// (S-31) is not built yet, so "Say it" opens the typed editor (S-13).
Widget iosSetupScreen(
  BuildContext context, {
  required VoidCallback onDone,
  required void Function(String slug) onSkipped,
}) => _screens(context).iosSetup(
  onDone: onDone,
  onSkipped: onSkipped,
  onSay: () => unawaited(showTransactionEditor(context)),
  onType: () => unawaited(showTransactionEditor(context)),
  onOnlineBanks: () => unawaited(openCaptureSettings(context)),
);

/// FR-ONB-11: `android_sms` / `android_notif` -> `skip_sms` /
/// `skip_notifications` in `setup_progress`.
Future<void> recordSetupSkip(ProviderContainer c, String slug) async {
  final step = switch (slug) {
    kSetupStepSms => 'sms',
    kSetupStepNotifications => 'notifications',
    kSetupStepIosShortcuts => 'shortcuts',
    _ => null,
  };
  if (step == null) return;
  final repo = await c.read(settingsRepositoryProvider.future);
  final now = await repo.get(Settings.setupProgress);
  await repo.set(Settings.setupProgress, {...now, skippedSlug(step)});
}
