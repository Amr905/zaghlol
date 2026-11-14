// T-084 / S-41: one card or account. Limit/balance header, spend donut by
// category (the slices add up to the card's spend, FR-CARD-02), top
// merchants, a six-cycle trend, recent rows and the capture entry. A
// multi-currency account switches every section with currency chips
// (FR-ACC-06). All numbers are per currency; amounts are ink, never red.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/db/app_database.dart' show IgnoreRuleRow;
import '../../../../core/db/daos/capture_controls_dao.dart' show IgnoreChannel;
import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../capture/presentation/capture_controls.dart';
import '../../../capture/presentation/card_capture_sheet.dart';
import '../../../home/application/card_filter.dart';
import '../../../insights/domain/chart_models.dart';
import '../../../insights/presentation/charts/chart_bodies.dart';
import '../../../mascot/presentation/zaghlol_avatar.dart';
import '../../../transactions/presentation/list/txn_list_providers.dart';
import '../../../transactions/presentation/list/txn_row.dart';
import '../../data/accounts_providers.dart';
import '../../domain/account.dart';
import '../edit_card/add_card_flow.dart';
import '../edit_card/edit_card_providers.dart' show institutionOptionsProvider;
import '../edit_card/merge_flow.dart';
import 'card_detail_providers.dart';

// ICU select keys of accountsDetailIgnoredBanner.
const String _platformIos = 'ios';
const String _platformOther = 'other';

class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({
    super.key,
    required this.accountId,
    this.onSeeAll,
    this.onOpenTransaction,
    this.justAdded = false,
    this.onAddTransaction,
    this.onImportStatement,
  });

  final String accountId;

  /// S-41 right after the add-card flow (mockup 31): shows the "card added"
  /// banner and, with no activity yet, the waiting state with two actions.
  final bool justAdded;

  /// "Add a transaction on this card" (the manual-entry editor).
  final VoidCallback? onAddTransaction;

  /// "Import this card's statement"; the row is hidden while no import entry
  /// exists (null).
  final VoidCallback? onImportStatement;

  /// "All card transactions": the card filter is already set; the shell
  /// opens S-11.
  final VoidCallback? onSeeAll;
  final ValueChanged<String>? onOpenTransaction;

  @override
  ConsumerState<CardDetailScreen> createState() => _State();
}

class _State extends ConsumerState<CardDetailScreen> {
  String? _currency;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final acc = ref.watch(cardDetailAccountProvider(widget.accountId));
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: acc.when(
          loading: () => const _Loading(key: Key('card-detail-loading')),
          error: (_, _) => _Message(text: l.commonErrorLoadFailed),
          data: (a) => a == null
              ? _Message(text: l.commonErrorLoadFailed)
              : _body(context, a),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AccountWithBalances a) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final account = a.account;
    final currencies = <Currency>[
      account.defaultCurrency,
      for (final b in a.balances)
        if (b.currency != account.defaultCurrency) b.currency,
    ];
    final cur = currencies.firstWhere(
      (x) => x.code == _currency,
      orElse: () => currencies.first,
    );
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final fmt = TxnFmt(lang, digits);
    final name = account.last4 == null
        ? account.label
        : '${account.label} •${digits.render(account.last4!)}';
    final data = ref.watch(
      cardDetailDataProvider((accountId: account.id, currency: cur.code)),
    );
    final lookups = ref.watch(txnLookupsProvider).value;
    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        Row(
          children: [
            _RoundBtn(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              child: const BackButtonIcon(),
            ),
            const Spacer(),
            _Menu(account: account, name: name),
            const SizedBox(width: ZSpacing.sm),
            _RoundBtn(
              key: const Key('card-detail-edit'),
              tooltip: l.accountsEditTitleEdit,
              onPressed: () => openEditCard(context, account),
              child: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.lg),
        Row(
          children: [
            _BankTile(account: account),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      name,
                      style: ZType.headline.copyWith(color: c.text),
                    ),
                  ),
                  if (data.value?.nextDue == null &&
                      widget.justAdded &&
                      account.statementDueDay != null)
                    Text(
                      l.accountsAddedDueDay(
                        digits.render('${account.statementDueDay}'),
                      ),
                      style: ZType.body.copyWith(color: c.textMuted),
                    ),
                  if (data.value?.nextDue case final due?)
                    Text(
                      l.accountsDetailDue(
                        ZDateFormat.date(
                          DateTime.utc(due.year, due.month, due.day),
                          fmt.lang,
                          fmt.digits,
                        ),
                      ),
                      style: ZType.body.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (currencies.length > 1) ...[
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: ZSpacing.sm,
            children: [
              for (final x in currencies)
                ZChip(
                  label: x.code,
                  selected: x == cur,
                  onTap: () => setState(() => _currency = x.code),
                ),
            ],
          ),
        ],
        const SizedBox(height: ZSpacing.md),
        if (widget.justAdded) ...[
          ZBanner(
            key: const Key('card-detail-added'),
            message: l.accountsAddedTitle,
            tone: ZBannerTone.success,
          ),
          const SizedBox(height: ZSpacing.md),
        ],
        _IgnoredBanner(account: account),
        _Header(
          waiting: widget.justAdded,
          account: account,
          balance: a.balances
              .where((b) => b.currency == cur)
              .cast<AccountBalance?>()
              .firstWhere((_) => true, orElse: () => null),
          cur: cur,
          fmt: fmt,
        ),
        const SizedBox(height: ZSpacing.lg),
        ...data.when(
          loading: () => [const _Loading(key: Key('card-detail-data-loading'))],
          error: (_, _) => [
            ZBanner(
              message: l.commonErrorLoadFailed,
              tone: ZBannerTone.warning,
            ),
          ],
          data: (d) => widget.justAdded && d.donut is! ChartReady<CategoryDonut>
              ? _addedEmpty(context, account, fmt)
              : _sections(context, d, lookups, fmt, account),
        ),
        const SizedBox(height: ZSpacing.lg),
        _CaptureRow(account: account, name: name, onSeeAll: widget.onSeeAll),
      ],
    );
  }

  List<Widget> _addedEmpty(BuildContext context, Account account, TxnFmt fmt) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    var bank = account.label;
    for (final o in ref.watch(institutionOptionsProvider)) {
      if (o.code == account.institutionCode) bank = o.name(fmt.lang);
    }
    final last4 = account.last4 == null
        ? ''
        : '•${fmt.digits.render(account.last4!)}';
    return [
      Column(
        key: const Key('card-detail-added-empty'),
        children: [
          // Decorative; it ignores pointers, so it never blocks the screen.
          const ExcludeSemantics(
            child: ZaghlolAvatar(moment: ZaghlolMoment.detective, size: 160),
          ),
          const SizedBox(height: ZSpacing.md),
          Semantics(
            header: true,
            child: Text(
              l.homeEmptyTitle,
              textAlign: TextAlign.center,
              style: ZType.headline.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          Text(
            l.accountsAddedEmptyBody(bank, last4),
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
        ],
      ),
      const SizedBox(height: ZSpacing.lg),
      ZCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (widget.onImportStatement != null) ...[
              _NavRow(
                key: const Key('card-added-import'),
                icon: Icons.description_outlined,
                tint: c.primary,
                title: l.accountsAddedImport,
                subtitle: l.accountsAddedImportSub,
                onTap: widget.onImportStatement,
              ),
              Divider(height: 1, thickness: 1, color: c.outline),
            ],
            _NavRow(
              key: const Key('card-added-manual'),
              icon: Icons.add_rounded,
              tint: c.textMuted,
              title: l.accountsAddedManual,
              subtitle: l.accountsAddedManualSub,
              onTap: widget.onAddTransaction,
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _sections(
    BuildContext context,
    CardDetailData d,
    TxnLookups? lookups,
    TxnFmt fmt,
    Account account,
  ) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final donut = d.donut;
    String nameOf(String? id) {
      final cat = lookups?.category(id);
      return cat == null ? '' : categoryName(cat, fmt.lang);
    }

    if (donut is! ChartReady<CategoryDonut>) {
      return [
        _EmptyPeriod(text: l.accountsDetailEmpty),
        ..._recent(context, d, lookups, fmt),
      ];
    }
    return [
      ZCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.accountsDetailSpent,
                    style: ZType.title.copyWith(color: c.text),
                  ),
                ),
                ZChip(label: l.commonPeriodThisCycle, selected: true),
              ],
            ),
            const SizedBox(height: ZSpacing.xs),
            ZMoneyText(
              text: fmt.money(donut.data.total),
              size: ZMoneySize.title,
              kind: ZMoneyKind.neutral,
            ),
            const SizedBox(height: ZSpacing.md),
            Semantics(
              label: l.accountsDetailDonutA11y,
              child: DonutBody(donut: donut.data, nameOf: nameOf),
            ),
          ],
        ),
      ),
      if (d.merchants case ChartReady<List<MerchantSpend>>(:final data)) ...[
        const SizedBox(height: ZSpacing.lg),
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l.accountsDetailTopMerchants,
                  style: ZType.title.copyWith(color: c.text),
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              MerchantsBody(rows: data),
            ],
          ),
        ),
      ],
      if (d.trend case ChartReady<List<CashFlowPoint>>(:final data)) ...[
        const SizedBox(height: ZSpacing.lg),
        ZCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l.accountsDetailTrend,
                  style: ZType.title.copyWith(color: c.text),
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              CashFlowBody(points: data),
            ],
          ),
        ),
      ],
      if (d.income != null && !d.income!.isZero) ...[
        const SizedBox(height: ZSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                l.accountsDetailIncomeRefunds,
                style: ZType.body.copyWith(color: c.text),
              ),
            ),
            ZMoneyText(text: fmt.money(d.income!), kind: ZMoneyKind.income),
          ],
        ),
      ],
      ..._recent(context, d, lookups, fmt),
    ];
  }

  List<Widget> _recent(
    BuildContext context,
    CardDetailData d,
    TxnLookups? lookups,
    TxnFmt fmt,
  ) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    if (d.recent.isEmpty || lookups == null) return const [];
    return [
      const SizedBox(height: ZSpacing.lg),
      Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                l.accountsDetailRecent,
                style: ZType.title.copyWith(color: c.text),
              ),
            ),
          ),
        ],
      ),
      for (final t in d.recent)
        TxnRow(
          txn: t,
          lookups: lookups,
          fmt: fmt,
          selecting: false,
          selected: false,
          onTap: () => widget.onOpenTransaction?.call(t.id),
          onLongPress: () {},
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    this.waiting = false,
    required this.account,
    required this.balance,
    required this.cur,
    required this.fmt,
  });

  final bool waiting;
  final Account account;
  final AccountBalance? balance;
  final Currency cur;
  final TxnFmt fmt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final limit =
        account.kind == AccountKind.credit && cur == account.defaultCurrency
        ? account.creditLimit
        : null;
    final available = balance?.available;
    final lines = <Widget>[];
    if (waiting && limit != null && available == null) {
      lines
        ..add(
          Row(
            children: [
              Text(
                l.accountsDetailAvailable,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Text(
                  l.accountsDetailAvailableOf('—', fmt.money(limit)),
                  textAlign: TextAlign.end,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: ZSpacing.md))
        ..add(
          ClipRRect(
            borderRadius: BorderRadius.circular(ZRadius.pill),
            child: LinearProgressIndicator(
              value: 0,
              minHeight: 10,
              color: c.primary,
              backgroundColor: c.surfaceAlt,
            ),
          ),
        )
        ..add(const SizedBox(height: ZSpacing.sm))
        ..add(
          Text(
            l.accountsAddedWaitingBalance,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        );
    } else if (limit != null && available != null) {
      final usedMinor = (limit.minor - available.minor).clamp(0, limit.minor);
      final pct = limit.minor == 0
          ? 0
          : (usedMinor * 100 / limit.minor).round();
      lines
        ..add(
          Row(
            children: [
              Text(
                l.accountsDetailAvailable,
                style: ZType.body.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Text(
                  l.accountsDetailAvailableOf(
                    fmt.money(available),
                    fmt.money(limit),
                  ),
                  textAlign: TextAlign.end,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: ZSpacing.md))
        ..add(
          Semantics(
            label: l.accountsDetailLimitUsed(fmt.digits.render('$pct%')),
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.pill),
              child: LinearProgressIndicator(
                value: limit.minor == 0 ? 0 : usedMinor / limit.minor,
                minHeight: 10,
                color: c.primary,
                backgroundColor: c.surfaceAlt,
              ),
            ),
          ),
        )
        ..add(const SizedBox(height: ZSpacing.sm))
        ..add(
          Text(
            l.accountsDetailLimitUsed(fmt.digits.render('$pct%')),
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        );
    } else if (balance?.balance != null) {
      lines
        ..add(
          Text(
            l.accountsDetailBalance,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        )
        ..add(
          ZMoneyText(
            text: fmt.money(balance!.balance!),
            size: ZMoneySize.title,
            kind: ZMoneyKind.neutral,
          ),
        )
        ..add(
          Text(
            l.accountsDetailAsOf(
              ZDateFormat.date(balance!.asOf, fmt.lang, fmt.digits),
            ),
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
        );
    } else {
      lines.add(
        Text(
          l.accountsDetailBalanceUnknown,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
      );
    }
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}

enum _MenuAction { capture, merge, hide }

class _Menu extends ConsumerWidget {
  const _Menu({required this.account, required this.name});
  final Account account;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<_MenuAction>(
      key: const Key('card-detail-menu'),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      constraints: const BoxConstraints(minWidth: 2 * ZSpacing.minTarget),
      onSelected: (a) async {
        switch (a) {
          case _MenuAction.capture:
            if (account.institutionCode == null) return;
            await showCardCaptureSheet(
              context,
              institutionCode: account.institutionCode!,
              last4: account.last4,
              cardName: name,
            );
          case _MenuAction.merge:
            final merged = await runMergeFlow(context, ref, source: account);
            if (merged != null && context.mounted) {
              Navigator.of(context).maybePop();
            }
          case _MenuAction.hide:
            final repo = await ref.read(accountsRepositoryProvider.future);
            await repo.setHidden(account.id, hidden: true);
            if (context.mounted) Navigator.of(context).maybePop();
        }
      },
      itemBuilder: (_) => [
        if (account.institutionCode != null)
          PopupMenuItem(
            value: _MenuAction.capture,
            child: Text(l.accountsDetailMenuCapture),
          ),
        PopupMenuItem(
          value: _MenuAction.merge,
          child: Text(l.accountsDetailMenuMerge),
        ),
        PopupMenuItem(
          value: _MenuAction.hide,
          child: Text(l.accountsDetailMenuHide),
        ),
      ],
    );
  }
}

List<String> _channels(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS
    ? const [IgnoreChannel.sms, IgnoreChannel.applePay]
    : const [IgnoreChannel.sms, IgnoreChannel.notification];

/// Whether the (institution, last4, channel) switch is on (S-62 logic).
bool _on(List<IgnoreRuleRow> rules, Account a, String channel) => !rules.any(
  (r) =>
      r.institutionCode == a.institutionCode &&
      r.channel == channel &&
      (r.last4 == a.last4 || r.last4 == null),
);

class _IgnoredBanner extends ConsumerWidget {
  const _IgnoredBanner({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (account.institutionCode == null) return const SizedBox.shrink();
    final rules = ref.watch(ignoreRulesStreamProvider).value;
    if (rules == null) return const SizedBox.shrink();
    final channels = _channels(context);
    if (channels.any((ch) => _on(rules, account, ch))) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: ZBanner(
        message: l.accountsDetailIgnoredBanner(
          ios ? _platformIos : _platformOther,
        ),
        tone: ZBannerTone.warning,
        actionLabel: l.accountsDetailTrackAgain,
        onAction: () async {
          final controls = await ref.read(captureControlsProvider.future);
          for (final r in rules) {
            if (r.institutionCode == account.institutionCode &&
                r.last4 == account.last4) {
              await controls.remove(r.id);
            }
          }
        },
      ),
    );
  }
}

class _CaptureRow extends ConsumerWidget {
  const _CaptureRow({required this.account, required this.name, this.onSeeAll});
  final Account account;
  final String name;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inst = account.institutionCode;
    if (inst == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final rules = ref.watch(ignoreRulesStreamProvider).value ?? const [];
    final parts = <String>[];
    final spoken = <String>[];
    for (final ch in _channels(context)) {
      final on = _on(rules, account, ch);
      final label = switch (ch) {
        IgnoreChannel.sms => l.commonChannelSmsShort,
        IgnoreChannel.applePay => l.commonChannelApplePay,
        _ => l.commonChannelNotificationsShort,
      };
      parts.add('$label ${on ? '✓' : '✗'}');
      spoken.add(
        '$label ${on ? l.commonChannelOnA11y : l.commonChannelOffA11y}',
      );
    }
    void open() => showCardCaptureSheet(
      context,
      institutionCode: inst,
      last4: account.last4,
      cardName: name,
    );
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(ZRadius.card),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ZRadius.card),
        child: Column(
          children: [
            Semantics(
              container: true,
              button: true,
              label: '${l.accountsDetailCapture}: ${spoken.join(', ')}',
              excludeSemantics: true,
              onTap: open,
              child: _NavRow(
                key: const Key('card-detail-capture'),
                icon: Icons.chat_bubble_outline_rounded,
                tint: c.primary,
                title: l.accountsDetailCapture,
                trailing: parts.join(' · '),
                onTap: open,
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: c.outline,
              indent: ZSpacing.lg,
              endIndent: ZSpacing.lg + 56,
            ),
            _NavRow(
              icon: Icons.description_outlined,
              tint: c.textMuted,
              title: l.accountsDetailAllTransactions,
              onTap: () {
                ref.read(cardFilterProvider.notifier).selectOnly(account.id);
                onSeeAll?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.lg,
            vertical: ZSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                ),
                child: Icon(icon, color: c.onPrimary),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ZType.body.copyWith(color: c.text)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: ZType.bodySmall.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Flexible(
                  child: Text(
                    trailing!,
                    style: ZType.bodySmall.copyWith(color: c.textMuted),
                    textAlign: TextAlign.end,
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                color: c.textMuted,
                textDirection: Directionality.of(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White circular top-bar button (mockup 14).
class _RoundBtn extends StatelessWidget {
  const _RoundBtn({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Material(
      color: c.surface,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: c.shadow,
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints(
          minWidth: ZSpacing.minTarget,
          minHeight: ZSpacing.minTarget,
        ),
        icon: child,
        onPressed: onPressed,
      ),
    );
  }
}

class _BankTile extends StatelessWidget {
  const _BankTile({required this.account});
  final Account account;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final word = account.label.trim().split(RegExp(r'\s+')).first;
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
      child: account.kind == AccountKind.cash
          ? Icon(Icons.payments_rounded, color: c.primary)
          : Text(
              (word.length > 4 ? word.substring(0, 1) : word).toUpperCase(),
              style: ZType.label.copyWith(
                color: c.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ZCard(
      key: const Key('card-detail-empty'),
      child: Column(
        children: [
          // Decorative; it ignores pointers, so it never blocks the screen.
          const ExcludeSemantics(
            child: ZaghlolAvatar(moment: ZaghlolMoment.sleep, size: 96),
          ),
          const SizedBox(height: ZSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(ZRadius.card),
              ),
              child: const SizedBox(height: 96, width: double.infinity),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
    child: ZBanner(message: text, tone: ZBannerTone.warning),
  );
}
