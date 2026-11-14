// T-054: Home (S-10). Reads [homeModelProvider] only. iOS gets a large inline
// title; Android a Material 3 collapsing app bar. Contextual cards (T-104)
// are in the banner slot (T-104); the currency switcher (T-116) is not here.

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_currency_switcher.dart';
import '../../budget/application/budget_providers.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/presentation/ios_setup_nudge.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import '../application/card_filter.dart';
import '../application/home_read_model.dart';
import 'cards/home_cards_view.dart';
import 'home_format.dart';
import 'home_widgets.dart';

/// True when the user has set a payday (A-43: none means calendar month).
final homePaydaySetProvider = Provider<bool>((ref) {
  final s = ref.watch(paydayScheduleProvider).value;
  return s != null && (s.eras.length > 1 || s.currentDay != 1);
}, name: 'homePaydaySetProvider');

/// Navigation hooks. Defaults use routes that exist today; the rest stay
/// null (no-op) until their screens land.
class HomeActions {
  const HomeActions({
    this.openSettings,
    this.openBudget,
    this.openSetBudget,
    this.openTransactions,
    this.openSpentTransactions,
    this.openTransaction,
    this.addExpense,
    this.openReview,
    this.openBackup,
    this.openFinishSetup,
    this.openCaptureSettings,
    this.openShare,
    this.mascotSlot,
  });

  final VoidCallback? openSettings;
  final VoidCallback? openBudget;
  final VoidCallback? openSetBudget;
  final VoidCallback? openTransactions;
  final VoidCallback? openSpentTransactions;
  final ValueChanged<String>? openTransaction;
  final VoidCallback? addExpense;
  final VoidCallback? openReview;

  final VoidCallback? openBackup;
  final VoidCallback? openFinishSetup;

  /// T-066: the iOS "Shortcuts went quiet" nudge opens S-61.
  final VoidCallback? openCaptureSettings;

  /// T-117: opens S-73 Share studio.
  final VoidCallback? openShare;

  /// C-14 mascot banner slot, filled by T-104.
  final Widget? mascotSlot;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.actions});

  final HomeActions? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(homeModelProvider);
    final c = ZColors.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final l = AppLocalizations.of(context);
    final a = _resolve(context);
    final settings = IconButton(
      tooltip: l.commonNavSettingsA11y,
      constraints: const BoxConstraints(
        minWidth: ZSpacing.minTarget,
        minHeight: ZSpacing.minTarget,
      ),
      icon: Icon(ios ? CupertinoIcons.gear : Icons.settings_outlined),
      onPressed: a.openSettings,
    );
    final header = Row(
      children: [
        const Expanded(child: _FilterRow()),
        if (a.openShare != null)
          IconButton(
            key: const ValueKey('home-share'),
            tooltip: l.shareStudioShare,
            constraints: const BoxConstraints(
              minWidth: ZSpacing.minTarget,
              minHeight: ZSpacing.minTarget,
            ),
            icon: Icon(ios ? CupertinoIcons.share : Icons.ios_share),
            onPressed: a.openShare,
          ),
        settings,
      ],
    );
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(homeModelProvider.future),
          child: CustomScrollView(
            key: const ValueKey('home-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (ios)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      ZSpacing.screen,
                      ZSpacing.md,
                      ZSpacing.screen,
                      0,
                    ),
                    child: Text(
                      l.appName,
                      key: const ValueKey('home-title-ios'),
                      style: ZType.headline.copyWith(color: c.text),
                    ),
                  ),
                )
              else
                SliverAppBar.medium(
                  key: const ValueKey('home-title-android'),
                  backgroundColor: c.bg,
                  surfaceTintColor: Colors.transparent,
                  title: Text(l.appName),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.screen,
                  ),
                  child: header,
                ),
              ),
              model.when(
                loading: () => const SliverToBoxAdapter(child: _HomeSkeleton()),
                error: (_, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                    child: ZBanner(
                      key: const ValueKey('home-error'),
                      message: l.commonErrorLoadFailed,
                      tone: ZBannerTone.error,
                      actionLabel: l.commonActionTryAgain,
                      onAction: () => ref.invalidate(homeModelProvider),
                    ),
                  ),
                ),
                data: (m) => SliverToBoxAdapter(
                  child: _HomeBody(model: m, actions: a),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: ZSpacing.xxl)),
            ],
          ),
        ),
      ),
    );
  }

  HomeActions _resolve(BuildContext context) {
    final a = actions;
    return HomeActions(
      openSettings: a?.openSettings ?? () => context.go(AppRoutes.zaghlol),
      openBudget: a?.openBudget,
      openSetBudget: a?.openSetBudget,
      openTransactions: a?.openTransactions,
      openSpentTransactions: a?.openSpentTransactions,
      openTransaction: a?.openTransaction,
      addExpense: a?.addExpense ?? () => context.push(AppRoutes.add),
      openReview: a?.openReview ?? () => context.push(AppRoutes.review),
      openBackup: a?.openBackup,
      openFinishSetup: a?.openFinishSetup,
      openCaptureSettings: a?.openCaptureSettings,
      openShare: a?.openShare,
      mascotSlot: a?.mascotSlot,
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: AlignmentDirectional.centerStart,
    child: HomeCardFilterChip(),
  );
}

class _HomeBody extends ConsumerStatefulWidget {
  const _HomeBody({required this.model, required this.actions});

  final HomeModel model;
  final HomeActions actions;

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  int _page = 0;
  final _pager = PageController();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = widget.model;
    final a = widget.actions;
    final format = HomeFormat.of(context, ref);
    final paydaySet = ref.watch(homePaydaySetProvider);
    final smsOn = ref.watch(captureSmsEnabledProvider).value ?? false;
    final supported = ref.watch(captureSupportedProvider);
    final isEmpty = m.recent.isEmpty;
    final figures = m.currencies;
    final page = figures.isEmpty ? 0 : _page.clamp(0, figures.length - 1);
    final scale = MediaQuery.textScalerOf(context);

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.screen,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: ZSpacing.sm),
          if (m.scanInProgress) ...[
            ZBanner(
              key: const ValueKey('home-scan-banner'),
              message: l.homeBannerScanning(0, format.count(0)),
            ),
            const SizedBox(height: ZSpacing.md),
          ],
          if (figures.isEmpty)
            _EmptyHero(key: const ValueKey('home-hero-empty'))
          else if (figures.length == 1)
            _Page(
              figures: figures.first,
              model: m,
              format: format,
              paydaySet: paydaySet,
              actions: a,
            )
          else ...[
            ZCurrencySwitcher(
              codes: [for (final f in figures) f.currency.code],
              selected: figures[page].currency.code,
              onSelected: (code) => _pager.animateToPage(
                figures.indexWhere((f) => f.currency.code == code),
                duration: ZMotion.standard,
                curve: ZMotion.curve,
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            SizedBox(
              key: const ValueKey('home-pager'),
              height: scale.scale(300),
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  for (final f in figures)
                    _Page(
                      figures: f,
                      model: m,
                      format: format,
                      paydaySet: paydaySet,
                      actions: a,
                    ),
                ],
              ),
            ),
            HomePagerDots(count: figures.length, index: page),
          ],
          IosSetupNudge(
            onCheck: a.openCaptureSettings,
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
          ),
          if (a.mascotSlot != null) ...[
            const SizedBox(height: ZSpacing.md),
            a.mascotSlot!,
          ] else
            HomeContextualCards(
              hasTransactions: !isEmpty,
              openSetBudget: a.openSetBudget,
              openBackup: a.openBackup,
              openFinishSetup: a.openFinishSetup,
            ),
          if (m.reviewCount > 0) ...[
            const SizedBox(height: ZSpacing.md),
            HomeReviewPill(
              key: const ValueKey('home-review'),
              count: m.reviewCount,
              format: format,
              onTap: a.openReview,
            ),
          ],
          const SizedBox(height: ZSpacing.lg),
          if (isEmpty)
            _Empty(
              filtered: m.cardFilter.isNotEmpty,
              waiting: supported && smsOn,
              onAdd: a.addExpense,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.homeFeedTitle,
                    style: ZType.title.copyWith(
                      color: ZColors.of(context).text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: a.openTransactions,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      ZSpacing.minTarget,
                      ZSpacing.minTarget,
                    ),
                  ),
                  child: Text(l.commonActionSeeAll),
                ),
              ],
            ),
            ZCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final item in m.recent)
                    HomeFeedRow(
                      key: ValueKey('home-row-${item.record.id}'),
                      item: item,
                      format: format,
                      today: m.today,
                      onTap: a.openTransaction,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.figures,
    required this.model,
    required this.format,
    required this.paydaySet,
    required this.actions,
  });

  final HomeCurrencyFigures figures;
  final HomeModel model;
  final HomeFormat format;
  final bool paydaySet;
  final HomeActions actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: ZSpacing.xs),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeHero(
          figures: figures,
          model: model,
          format: format,
          paydaySet: paydaySet,
          onTap: actions.openBudget,
          onSetBudget: actions.openSetBudget,
        ),
        const SizedBox(height: ZSpacing.sm),
        HomeKpis(
          figures: figures,
          format: format,
          onSpentTap: actions.openSpentTransactions,
        ),
      ],
    ),
  );
}

/// Hero when there is no data at all: no zeros (spec "Empty").
class _EmptyHero extends StatelessWidget {
  const _EmptyHero({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return ZCard(
      color: c.primaryContainer,
      padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
      child: Text(
        l.homeHeroSetBudgetHint,
        style: ZType.title.copyWith(color: c.onPrimaryContainer),
      ),
    );
  }
}

/// C-28 empty state; names the active card filter (EC-61).
class _Empty extends ConsumerWidget {
  const _Empty({
    required this.filtered,
    required this.waiting,
    required this.onAdd,
  });

  final bool filtered;
  final bool waiting;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final String title;
    final String? body;
    if (filtered) {
      final accounts = ref.watch(homeAccountsProvider).value ?? const [];
      final names = homeFilterNames(accounts, ref.watch(cardFilterProvider));
      title = l.homeEmptyFilter(names.join(', '));
      body = null;
    } else {
      title = l.homeEmptyTitle;
      body = waiting ? l.homeEmptyBodyWaiting : l.homeEmptyBodyAdd;
    }
    return Semantics(
      container: true,
      child: Column(
        key: const ValueKey('home-empty'),
        children: [
          const ZaghlolAvatar(size: 96),
          const SizedBox(height: ZSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ZType.title.copyWith(color: c.text),
          ),
          if (body != null) ...[
            const SizedBox(height: ZSpacing.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ],
          const SizedBox(height: ZSpacing.lg),
          if (filtered)
            ZButton(
              label: l.commonActionClearFilter,
              variant: ZButtonVariant.secondary,
              onPressed: () => ref.read(cardFilterProvider.notifier).clear(),
            )
          else if (!waiting)
            ZButton(label: l.homeEmptyAdd, onPressed: onAdd),
        ],
      ),
    );
  }
}

/// Loading: skeleton hero and rows.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
    );
    return Padding(
      key: const ValueKey('home-skeleton'),
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: ExcludeSemantics(
        child: Column(
          children: [
            block(150),
            block(64),
            for (var i = 0; i < 5; i++) block(56),
          ],
        ),
      ),
    );
  }
}
