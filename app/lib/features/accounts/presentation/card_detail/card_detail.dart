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
  });

  final String accountId;

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
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              constraints: const BoxConstraints(
                minWidth: ZSpacing.minTarget,
                minHeight: ZSpacing.minTarget,
              ),
              icon: const BackButtonIcon(),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  name,
                  style: ZType.headline.copyWith(color: c.text),
                ),
              ),
            ),
            IconButton(
              key: const Key('card-detail-edit'),
              tooltip: l.accountsEditTitleEdit,
              constraints: const BoxConstraints(
                minWidth: ZSpacing.minTarget,
                minHeight: ZSpacing.minTarget,
              ),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => openEditCard(context, account),
            ),
            _Menu(account: account, name: name),
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
        _IgnoredBanner(account: account),
        _Header(
          account: account,
          balance: a.balances
              .where((b) => b.currency == cur)
              .cast<AccountBalance?>()
              .firstWhere((_) => true, orElse: () => null),
          cur: cur,
          fmt: fmt,
          nextDue: data.value?.nextDue,
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
          data: (d) => _sections(context, d, lookups, fmt, account),
        ),
        const SizedBox(height: ZSpacing.lg),
        _CaptureRow(account: account, name: name),
      ],
    );
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
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ZSpacing.sm,
              children: [
                Text(
                  l.accountsDetailSpent,
                  style: ZType.title.copyWith(color: c.text),
                ),
                ZChip(label: l.commonPeriodThisCycle, selected: true),
              ],
            ),
            const SizedBox(height: ZSpacing.xs),
            ZMoneyText(
              text: fmt.money(donut.data.total),
              size: ZMoneySize.display,
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
          ZButton(
            label: l.accountsDetailAllTransactions,
            variant: ZButtonVariant.text,
            onPressed: () {
              ref
                  .read(cardFilterProvider.notifier)
                  .selectOnly(widget.accountId);
              widget.onSeeAll?.call();
            },
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
    required this.account,
    required this.balance,
    required this.cur,
    required this.fmt,
    required this.nextDue,
  });

  final Account account;
  final AccountBalance? balance;
  final Currency cur;
  final TxnFmt fmt;
  final CivilDate? nextDue;

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
    if (limit != null && available != null) {
      final usedMinor = (limit.minor - available.minor).clamp(0, limit.minor);
      final pct = limit.minor == 0
          ? 0
          : (usedMinor * 100 / limit.minor).round();
      lines
        ..add(
          Text(
            '${l.accountsDetailAvailable} · '
            '${l.accountsDetailAvailableOf(fmt.money(available), fmt.money(limit))}',
            style: ZType.title.copyWith(color: c.text),
          ),
        )
        ..add(const SizedBox(height: ZSpacing.sm))
        ..add(
          Semantics(
            label: l.accountsDetailLimitUsed(fmt.digits.render('$pct%')),
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZRadius.sm),
              child: LinearProgressIndicator(
                value: limit.minor == 0 ? 0 : usedMinor / limit.minor,
                minHeight: 8,
                color: c.primary,
                backgroundColor: c.primaryContainer,
              ),
            ),
          ),
        )
        ..add(
          Text(
            l.accountsDetailLimitUsed(fmt.digits.render('$pct%')),
            style: ZType.caption.copyWith(color: c.textMuted),
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
    final due = nextDue;
    if (due != null) {
      lines
        ..add(const SizedBox(height: ZSpacing.sm))
        ..add(
          Text(
            l.accountsDetailDue(
              ZDateFormat.date(
                DateTime.utc(due.year, due.month, due.day),
                fmt.lang,
                fmt.digits,
              ),
            ),
            style: ZType.body.copyWith(color: c.text),
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
  const _CaptureRow({required this.account, required this.name});
  final Account account;
  final String name;

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
    return Semantics(
      container: true,
      button: true,
      label: '${l.accountsDetailCapture}: ${spoken.join(', ')}',
      excludeSemantics: true,
      onTap: open,
      child: ZListRow(
        key: const Key('card-detail-capture'),
        title: l.accountsDetailCapture,
        subtitle: parts.join(' · '),
        showChevron: true,
        onTap: open,
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
