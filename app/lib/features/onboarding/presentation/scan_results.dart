// T-057: S-06 «دي كروتك؟». Shows what the first scan found: three counts and
// the cards/accounts it created, each with confirm / edit (S-43) / stop
// tracking (ignore rule, T-078). Counts, labels and last-4 only; never a
// message body, sender text or amount. Skipped (onDone) when nothing was
// found; also usable as a sheet via [showScanResultsSheet].

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_sheet.dart';
import '../../accounts/data/accounts_providers.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/presentation/edit_card/edit_card_providers.dart';
import '../../../core/db/daos/capture_controls_dao.dart' show IgnoreChannel;
import '../../capture/application/ignore_rules.dart';
import '../../capture/domain/scan_plan.dart';
import '../../capture/presentation/capture_controls.dart';
import '../../ingestion/data/review_repository.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import 'android_setup.dart' show setupScanProvider;
import 'onboarding_parts.dart';

/// One card or account the scan created.
final class ScanCardItem {
  const ScanCardItem({
    required this.accountId,
    required this.label,
    required this.kind,
    required this.txnCount,
    this.institutionCode,
    this.last4,
    this.looksCredit = false,
  });

  final String accountId;
  final String label;
  final AccountKind kind;
  final int txnCount;
  final String? institutionCode;
  final String? last4;

  /// Credit card with no limit set yet (FR-ACC-05 prompt).
  final bool looksCredit;
}

final class ScanResultsData {
  const ScanResultsData({
    required this.found,
    required this.review,
    required this.cards,
    this.months = kDefaultScanDepthMonths,
  });

  final int found;
  final int review;
  final List<ScanCardItem> cards;
  final int months;

  int get auto => found > review ? found - review : 0;
  bool get isEmpty => found == 0;
}

final scanResultsProvider = FutureProvider<ScanResultsData>((ref) async {
  final scan = await ref.watch(setupScanProvider.future);
  final repo = await ref.watch(accountsRepositoryProvider.future);
  final review = await ref.watch(reviewOpenCountProvider.future);
  final accounts = await repo.list();
  final cards = <ScanCardItem>[];
  for (final a in accounts) {
    if (a.kind == AccountKind.cash) continue;
    final n = await ref.watch(accountTxnCountProvider(a.id).future);
    cards.add(
      ScanCardItem(
        accountId: a.id,
        label: a.label,
        kind: a.kind,
        txnCount: n,
        institutionCode: a.institutionCode,
        last4: a.last4,
        looksCredit: a.kind == AccountKind.credit && a.creditLimit == null,
      ),
    );
  }
  return ScanResultsData(
    found: scan?.current.imported ?? 0,
    review: review,
    cards: cards,
  );
}, name: 'scanResultsProvider');

class ScanResultsScreen extends ConsumerWidget {
  const ScanResultsScreen({
    super.key,
    required this.onDone,
    this.onOpenReview,
    this.onEditCard,
    this.onSetupCredit,
    this.asSheet = false,
  });

  /// "Show me my money" or nothing to show -> Home.
  final VoidCallback onDone;

  /// "Waiting for you" tapped -> S-14.
  final VoidCallback? onOpenReview;

  /// Edit / rename a card -> S-43 edit.
  final void Function(String accountId)? onEditCard;

  /// Credit prompt accepted -> S-43 credit fields.
  final void Function(String accountId)? onSetupCredit;
  final bool asSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(scanResultsProvider);
    final body = data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          _Retry(onRetry: () => ref.invalidate(scanResultsProvider)),
      data: (d) => d.isEmpty
          ? _SkipToHome(onDone: onDone)
          : ScanResultsBody(
              data: d,
              onDone: onDone,
              onOpenReview: onOpenReview,
              onEditCard: onEditCard,
              onSetupCredit: onSetupCredit,
            ),
    );
    if (asSheet) return body;
    return Scaffold(body: SafeArea(child: body));
  }
}

/// Opens S-06 as a sheet when the scan finished after Home was reached.
Future<void> showScanResultsSheet(
  BuildContext context, {
  required VoidCallback onDone,
  VoidCallback? onOpenReview,
  void Function(String)? onEditCard,
  void Function(String)? onSetupCredit,
}) {
  final l = AppLocalizations.of(context);
  return showZSheet<void>(
    context: context,
    title: l.onboardingScanResultsCardsTitle,
    fullHeight: true,
    builder: (ctx) => ScanResultsScreen(
      asSheet: true,
      onDone: () {
        Navigator.of(ctx).pop();
        onDone();
      },
      onOpenReview: onOpenReview,
      onEditCard: onEditCard,
      onSetupCredit: onSetupCredit,
    ),
  );
}

class _SkipToHome extends StatefulWidget {
  const _SkipToHome({required this.onDone});
  final VoidCallback onDone;
  @override
  State<_SkipToHome> createState() => _SkipToHomeState();
}

class _SkipToHomeState extends State<_SkipToHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: ZButton(
        key: const ValueKey('scan-results-retry'),
        label: l.commonActionTryAgain,
        onPressed: onRetry,
      ),
    );
  }
}

class ScanResultsBody extends ConsumerStatefulWidget {
  const ScanResultsBody({
    super.key,
    required this.data,
    required this.onDone,
    this.onOpenReview,
    this.onEditCard,
    this.onSetupCredit,
  });

  final ScanResultsData data;
  final VoidCallback onDone;
  final VoidCallback? onOpenReview;
  final void Function(String accountId)? onEditCard;
  final void Function(String accountId)? onSetupCredit;

  @override
  ConsumerState<ScanResultsBody> createState() => _BodyState();
}

class _BodyState extends ConsumerState<ScanResultsBody> {
  final Set<String> _confirmed = {};
  final Set<String> _ignored = {};
  bool _creditDismissed = false;

  String _digits(int v) {
    final lang = Localizations.localeOf(context).languageCode;
    return ref.read(digitsModeProvider(lang)).render('$v');
  }

  String _typeName(AppLocalizations l, ScanCardItem i) {
    if (i.looksCredit) return l.onboardingScanResultsGuessCredit;
    return switch (i.kind) {
      AccountKind.debit => l.commonAccountTypeDebit,
      AccountKind.credit => l.commonAccountTypeCredit,
      AccountKind.account => l.commonAccountTypeAccount,
      AccountKind.wallet => l.commonAccountTypeWallet,
      AccountKind.bnpl => l.commonAccountTypeBnpl,
      AccountKind.cash => l.commonAccountTypeCash,
      AccountKind.multiCurrency => l.commonAccountTypeMultiCurrency,
    };
  }

  String? _kindBadge(AppLocalizations l, AccountKind k) => switch (k) {
    AccountKind.debit => l.commonAccountTypeDebit,
    AccountKind.credit => l.commonAccountTypeCredit,
    AccountKind.account => l.commonAccountTypeAccount,
    AccountKind.wallet => l.commonAccountTypeWallet,
    AccountKind.bnpl => l.commonAccountTypeBnpl,
    AccountKind.multiCurrency => l.commonAccountTypeMultiCurrency,
    AccountKind.cash => null,
  };

  Future<void> _ignore(ScanCardItem item) async {
    final code = item.institutionCode;
    if (code == null) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final controls = await ref.read(captureControlsProvider.future);
      for (final ch in const [IgnoreChannel.sms, IgnoreChannel.notification]) {
        await controls.add(
          IgnoreTarget(institutionCode: code, last4: item.last4, channel: ch),
        );
      }
      if (!mounted) return;
      setState(() => _ignored.add(item.accountId));
      messenger?.showSnackBar(SnackBar(content: Text(l.captureIgnoreSaved)));
    } on Object {
      // Nothing changed; the card stays listed and the user can retry.
    }
  }

  /// Header "Edit" link (mockup 24): pick the card to edit (S-43). One card
  /// goes straight to the editor.
  Future<void> _pickToEdit(List<ScanCardItem> cards) async {
    if (cards.length == 1) {
      widget.onEditCard?.call(cards.single.accountId);
      return;
    }
    final l = AppLocalizations.of(context);
    final picked = await showZSheet<String>(
      context: context,
      title: l.onboardingScanResultsCardsTitle,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in cards)
            ListTile(
              key: ValueKey('scan-edit-${i.accountId}'),
              minVerticalPadding: ZSpacing.md,
              title: Text(i.label),
              subtitle: (i.last4 == null || i.last4!.isEmpty)
                  ? null
                  : Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('•••• ${i.last4}'),
                    ),
              onTap: () => Navigator.of(ctx).pop(i.accountId),
            ),
        ],
      ),
    );
    if (picked != null) widget.onEditCard?.call(picked);
  }

  Future<void> _openCard(ScanCardItem item) async {
    final l = AppLocalizations.of(context);
    await showZSheet<void>(
      context: context,
      title: item.label,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZButton(
            key: const ValueKey('scan-card-confirm'),
            label: l.commonActionConfirm,
            expand: true,
            onPressed: () {
              setState(() => _confirmed.add(item.accountId));
              Navigator.of(ctx).pop();
            },
          ),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            key: const ValueKey('scan-card-edit'),
            label: l.commonActionEdit,
            variant: ZButtonVariant.secondary,
            expand: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onEditCard?.call(item.accountId);
            },
          ),
          const SizedBox(height: ZSpacing.sm),
          ZButton(
            key: const ValueKey('scan-card-ignore'),
            label: l.captureSettingsAddIgnore,
            variant: ZButtonVariant.secondary,
            expand: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_ignore(item));
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final d = widget.data;
    final cards = d.cards
        .where((i) => !_ignored.contains(i.accountId))
        .toList();
    final credit = _creditDismissed
        ? null
        : cards.where((i) => i.looksCredit).firstOrNull;
    final period = l.commonPeriodInLastMonths(d.months, _digits(d.months));
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
            children: [
              const SizedBox(height: ZSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.onboardingScanResultsTitle,
                          style: ZType.headline.copyWith(color: c.text),
                        ),
                        const SizedBox(height: ZSpacing.xs),
                        Text(
                          l.onboardingScanResultsFound(
                            d.found,
                            _digits(d.found),
                            period,
                          ),
                          style: ZType.body.copyWith(color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  const OnbMascot(moment: ZaghlolMoment.proud, size: 96),
                ],
              ),
              const SizedBox(height: ZSpacing.lg),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Stat(
                        key: const ValueKey('stat-auto'),
                        value: _digits(d.auto),
                        label: l.onboardingScanResultsStatAuto,
                        valueColor: c.primary,
                      ),
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: _Stat(
                        key: const ValueKey('stat-review'),
                        value: _digits(d.review),
                        label: l.onboardingScanResultsStatReview,
                        valueColor: c.warningText,
                        onTap: d.review > 0 ? widget.onOpenReview : null,
                      ),
                    ),
                    const SizedBox(width: ZSpacing.md),
                    Expanded(
                      child: _Stat(
                        key: const ValueKey('stat-cards'),
                        value: _digits(cards.length),
                        label: l.onboardingScanResultsStatCards,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZSpacing.lg),
              if (cards.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.onboardingScanResultsCardsTitle,
                        style: ZType.title.copyWith(color: c.text),
                      ),
                    ),
                    if (widget.onEditCard != null)
                      ZButton(
                        key: const ValueKey('scan-edit-cards'),
                        label: l.commonActionEdit,
                        variant: ZButtonVariant.text,
                        size: ZButtonSize.small,
                        onPressed: () => unawaited(_pickToEdit(cards)),
                      ),
                  ],
                ),
                const SizedBox(height: ZSpacing.md),
                ZCard(
                  padding: const EdgeInsetsDirectional.symmetric(
                    vertical: ZSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      for (final (n, i) in cards.indexed) ...[
                        if (n > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: c.outline,
                            indent: ZSpacing.lg,
                            endIndent: ZSpacing.lg,
                          ),
                        _CardRow(
                          item: i,
                          tone: n,
                          subtitle: l.onboardingScanResultsCardSubtitle(
                            i.txnCount,
                            _digits(i.txnCount),
                            _typeName(l, i),
                          ),
                          badge: i.looksCredit
                              ? l.onboardingScanResultsCreditBadge
                              : _kindBadge(l, i.kind),
                          badgeWarn: i.looksCredit,
                          confirmed: _confirmed.contains(i.accountId),
                          onTap: () => _openCard(i),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (credit != null) ...[
                const SizedBox(height: ZSpacing.md),
                ZCard(
                  key: const ValueKey('scan-credit-prompt'),
                  color: c.zaghlolBg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.onboardingScanResultsCreditPrompt(credit.label),
                              style: ZType.bodySmall.copyWith(color: c.text),
                            ),
                            const SizedBox(height: ZSpacing.md),
                            Wrap(
                              spacing: ZSpacing.sm,
                              runSpacing: ZSpacing.xs,
                              children: [
                                ZButton(
                                  size: ZButtonSize.small,
                                  key: const ValueKey('scan-credit-yes'),
                                  label: l.onboardingScanResultsCreditYes,
                                  onPressed: () => widget.onSetupCredit?.call(
                                    credit.accountId,
                                  ),
                                ),
                                ZButton(
                                  size: ZButtonSize.small,
                                  key: const ValueKey('scan-credit-later'),
                                  label: l.commonActionLater,
                                  variant: ZButtonVariant.secondary,
                                  onPressed: () =>
                                      setState(() => _creditDismissed = true),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ZSpacing.sm),
                      const OnbMascot(
                        moment: ZaghlolMoment.detective,
                        size: 64,
                      ),
                    ],
                  ),
                ),
              ],
              if (cards.isNotEmpty) ...[
                const SizedBox(height: ZSpacing.md),
                Text(
                  l.onboardingScanResultsNotMineHint,
                  textAlign: TextAlign.center,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          child: ZButton(
            key: const ValueKey('scan-show-me'),
            label: l.onboardingScanResultsShowMe,
            expand: true,
            onPressed: widget.onDone,
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.onTap,
  });
  final String value;
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$value, $label',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: ZCard(
          onTap: onTap,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.sm,
            vertical: ZSpacing.md,
          ),
          child: Column(
            children: [
              Text(
                value,
                style: ZType.headline.copyWith(color: valueColor ?? c.text),
              ),
              const SizedBox(height: ZSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: ZType.caption.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.item,
    required this.subtitle,
    required this.confirmed,
    required this.onTap,
    required this.tone,
    this.badge,
    this.badgeWarn = false,
  });
  final ScanCardItem item;
  final String subtitle;
  final String? badge;
  final bool badgeWarn;
  final bool confirmed;
  final int tone;
  final VoidCallback onTap;

  String get _initials {
    final src = (item.institutionCode ?? item.label).trim();
    final t = src.length <= 4 ? src : src.substring(0, 4);
    return t.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final (tileBg, tileFg) = switch (tone % 3) {
      0 => (c.primaryContainer, c.primary),
      1 => (c.surfaceAlt, c.textMuted),
      _ => (c.zaghlolBg, c.warningText),
    };
    return Semantics(
      button: true,
      label: '${item.label}, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.lg,
              vertical: ZSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tileBg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _initials,
                    maxLines: 1,
                    style: ZType.caption.copyWith(
                      color: tileFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: ZType.label.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: ZType.caption.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: ZSpacing.sm),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: ZSpacing.md,
                      vertical: ZSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: badgeWarn ? c.zaghlolBg : c.primaryContainer,
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                    ),
                    child: Text(
                      badge!,
                      style: ZType.label.copyWith(
                        color: badgeWarn ? c.warningText : c.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: ZSpacing.xs),
                Icon(
                  confirmed ? Icons.check_circle : (Icons.chevron_right),
                  color: confirmed ? c.primary : c.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
