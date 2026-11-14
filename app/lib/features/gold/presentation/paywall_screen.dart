// T-146: S-68 Zaghlol Gold (mockup 18). Prices are the store's own strings.
// Every state of the spec: prices loading / failed, ready, purchasing,
// pending, verifying offline, success, cancelled, invalid, already Gold and
// the seat messages. No money is shown that did not come from the store.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../catalog_sync/application/sync_providers.dart';
import '../application/gating.dart';
import '../domain/purchase_outcome.dart';
import '../domain/restore_outcome.dart';
import 'gold_messages.dart';
import 'gold_ui_ports.dart';

/// What the strip under the benefits says.
enum _Notice {
  none,
  purchasing,
  restoring,
  pending,
  verifyOffline,
  success,
  cancelled,
  invalid,
  storeError,
  nothingToRestore,
}

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  GoldPlan? _selected;
  _Notice _notice = _Notice.none;
  GoldMessage? _message;
  bool _noticeDismissed = false;
  StreamSubscription<PurchaseOutcome>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(goldActionsProvider).outcomes.listen(_onPurchase);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  bool get _busy =>
      _notice == _Notice.purchasing || _notice == _Notice.restoring;

  void _set(_Notice n, {GoldMessage? message}) {
    if (!mounted) return;
    setState(() {
      _notice = n;
      _message = message;
    });
  }

  void _onPurchase(PurchaseOutcome o) {
    switch (o) {
      case PurchaseGold():
        _set(_Notice.success);
        unawaited(Navigator.of(context).maybePop(true));
      case PurchaseSeatHeldElsewhere():
        _set(_Notice.none, message: GoldMessage.fromPurchase(o));
      case PurchasePending():
        _set(_Notice.pending);
      case PurchaseQueued():
        _set(_Notice.verifyOffline);
      case PurchaseInvalid() || PurchaseNotOwned():
        _set(_Notice.invalid);
      case PurchaseCancelled():
        _set(_Notice.cancelled);
    }
  }

  Future<void> _buy() async {
    final plan = _selected;
    if (plan == null || _busy) return;
    _set(_Notice.purchasing);
    final started = await ref.read(goldActionsProvider).buy(plan);
    if (!started) _set(_Notice.storeError);
  }

  Future<void> _restore() async {
    if (_busy) return;
    _set(_Notice.restoring);
    final RestoreOutcome o;
    try {
      o = await ref.read(goldActionsProvider).restore();
    } on Object {
      _set(_Notice.storeError);
      return;
    }
    if (!mounted) return;
    final msg = GoldMessage.fromRestore(o);
    if (msg != null) {
      _set(_Notice.none, message: msg);
      return;
    }
    switch (o) {
      case RestoreGold():
        _set(_Notice.success);
        unawaited(Navigator.of(context).maybePop(true));
      case RestoreNothingToRestore():
        _set(_Notice.nothingToRestore);
      case RestorePending():
        _set(_Notice.pending);
      case RestoreNotGold() || RestoreBodyRejected() || RestoreFailed():
        _set(_Notice.invalid);
      default:
        _set(_Notice.storeError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final state = ref.watch(entitlementStateProvider);
    final info =
        ref.watch(goldStatusInfoProvider).value ?? const GoldStatusInfo();
    final offers = ref.watch(goldOffersProvider);
    final status = GoldMessage.fromEntitlement(state, info);
    final link = ref.watch(goldLinkOpenerProvider);

    final benefits = [
      t.goldPaywallBenefitCharts,
      t.goldPaywallBenefitVoice,
      t.goldPaywallBenefitExport,
      t.goldPaywallBenefitBackup,
      t.goldPaywallBenefitAssets,
      t.goldPaywallBenefitCustom,
    ];

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _busy ? null : _restore,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, ZSpacing.minTarget),
                      ),
                      child: Text(t.goldPaywallRestore),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: t.goldPaywallCloseA11y,
                  constraints: const BoxConstraints(
                    minWidth: ZSpacing.minTarget,
                    minHeight: ZSpacing.minTarget,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            ExcludeSemantics(
              child: Icon(Icons.workspace_premium, size: 72, color: c.accent),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              t.goldPaywallTitle,
              textAlign: TextAlign.center,
              style: ZType.headline.copyWith(color: c.text),
            ),
            Text(
              t.goldPaywallHeadline,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.lg),
            for (final b in benefits)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: c.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check, size: 16, color: c.onAccent),
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: Text(b, style: ZType.body.copyWith(color: c.text)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: ZSpacing.md),
            if (status != null) ...[
              GoldMessageCard(message: status, onRestore: _restore),
              const SizedBox(height: ZSpacing.md),
            ],
            if (_message != null) ...[
              GoldMessageCard(message: _message!, onRetry: _restore),
              const SizedBox(height: ZSpacing.md),
            ],
            if (info.supportNoticePending && !_noticeDismissed) ...[
              GoldMessageCard(
                message: const GoldMessage(GoldMessageKind.supportNotice),
                onDismiss: () async {
                  setState(() => _noticeDismissed = true);
                  await ref.read(goldActionsProvider).dismissSupportNotice();
                  ref.invalidate(goldStatusInfoProvider);
                },
              ),
              const SizedBox(height: ZSpacing.md),
            ],
            if (state.isGold)
              _AlreadyGold(
                plan: info.plan,
                onManage: () => link(GoldLink.manageSubscription),
              )
            else
              ..._buyArea(context, offers),
            if (_noticeText(t) case final text?) ...[
              const SizedBox(height: ZSpacing.md),
              Semantics(
                liveRegion: true,
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: ZType.body.copyWith(color: c.text),
                ),
              ),
            ],
            const SizedBox(height: ZSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => link(GoldLink.terms),
                  child: Text(t.goldPaywallTerms),
                ),
                TextButton(
                  onPressed: () => link(GoldLink.privacy),
                  child: Text(t.goldPaywallPrivacy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _noticeText(AppLocalizations t) => switch (_notice) {
    _Notice.none => null,
    _Notice.purchasing => t.goldPaywallPurchasing,
    _Notice.restoring => t.goldAccountRestoring,
    _Notice.pending => t.goldPaywallPending,
    _Notice.verifyOffline => t.goldPaywallVerifyOffline,
    _Notice.success => t.goldPaywallSuccess,
    _Notice.cancelled => t.goldPaywallCancelled,
    _Notice.invalid => t.goldPaywallInvalid,
    _Notice.storeError => t.goldPaywallStoreError,
    _Notice.nothingToRestore => t.goldAccountRestoreNone,
  };

  List<Widget> _buyArea(
    BuildContext context,
    AsyncValue<List<GoldPlanOffer>> offers,
  ) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return offers.when(
      loading: () => [
        Semantics(
          label: t.goldPaywallPricesLoading,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  height: 64,
                  margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(ZRadius.lg),
                  ),
                ),
              Text(
                t.goldPaywallPricesLoading,
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
      error: (_, _) => [
        Text(
          t.goldPaywallPricesFailed,
          textAlign: TextAlign.center,
          style: ZType.body.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Center(
          child: ZButton(
            label: t.commonActionTryAgain,
            variant: ZButtonVariant.secondary,
            onPressed: () => ref.invalidate(goldOffersProvider),
          ),
        ),
      ],
      data: (list) {
        final sel =
            _selected ??
            (list.any((o) => o.plan == GoldPlan.yearly)
                ? GoldPlan.yearly
                : list.first.plan);
        final platform = goldPlatformKey(ref.watch(clientPlatformProvider));
        return [
          RadioGroup<GoldPlan>(
            groupValue: sel,
            onChanged: (p) {
              if (p != null && !_busy) setState(() => _selected = p);
            },
            child: Column(
              children: [
                for (final o in list)
                  _PlanCard(offer: o, selected: o.plan == sel),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          ZButton(
            label: t.goldPaywallContinue,
            variant: ZButtonVariant.gold,
            expand: true,
            loading: _notice == _Notice.purchasing,
            onPressed: _busy ? null : () => unawaited(_buyPlan(sel)),
          ),
          const SizedBox(height: ZSpacing.sm),
          if (sel.renews) ...[
            Text(
              t.goldPaywallRenewalSummary,
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.text),
            ),
            Text(
              t.goldPaywallRenewal(platform),
              textAlign: TextAlign.center,
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
          ] else
            Text(
              t.goldPaywallLifetimeNote,
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.text),
            ),
        ];
      },
    );
  }

  Future<void> _buyPlan(GoldPlan plan) {
    _selected = plan;
    return _buy();
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.offer, required this.selected});
  final GoldPlanOffer offer;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final plan = offer.plan.key;
    final name = t.goldPaywallPlanName(plan);
    final price = t.goldPaywallPlanPrice(plan, offer.storePrice);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$name, $price',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
        child: Material(
          color: selected ? c.primaryContainer : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZRadius.lg),
            side: BorderSide(
              color: selected ? c.primary : c.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(ZRadius.lg),
            onTap: () =>
                RadioGroup.maybeOf<GoldPlan>(context)?.onChanged(offer.plan),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? c.primary : c.textMuted,
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: ZSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                name,
                                style: ZType.titleSmall.copyWith(color: c.text),
                              ),
                              if (offer.plan == GoldPlan.yearly)
                                Container(
                                  padding:
                                      const EdgeInsetsDirectional.symmetric(
                                        horizontal: ZSpacing.sm,
                                        vertical: ZSpacing.xs,
                                      ),
                                  decoration: BoxDecoration(
                                    color: c.zaghlolBg,
                                    borderRadius: BorderRadius.circular(
                                      ZRadius.pill,
                                    ),
                                  ),
                                  child: Text(
                                    t.goldPaywallBestValue,
                                    style: ZType.caption.copyWith(
                                      color: c.accentDark,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // The price string is the store's; keep digits and
                          // symbols in their own direction.
                          Text(
                            price,
                            style: ZType.body.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlreadyGold extends StatelessWidget {
  const _AlreadyGold({required this.plan, required this.onManage});
  final GoldPlan? plan;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      children: [
        Text(
          t.goldPaywallAlreadyGold(GoldPlan.selectKey(plan)),
          textAlign: TextAlign.center,
          style: ZType.titleSmall.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        if (plan?.renews ?? false)
          ZButton(
            label: t.commonActionManage,
            variant: ZButtonVariant.secondary,
            onPressed: onManage,
          ),
      ],
    );
  }
}
