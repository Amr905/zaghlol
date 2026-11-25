// T-266 (US-P05): a debit card linked to its bank account, on S-41.
// - Debit card: the "Linked account" card (pick / change / unlink), or the
//   question "Is this card on your <bank> account?" when a same-bank account
//   exists. Nothing is linked without the user's tap.
// - Linked card: the header shows the account's balance (the card has none).
// - Account: the cards linked to it and "Set current amount" (the T-199
//   typed balance, true as of now).
// Amounts are ink, never red. Nothing here logs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/card_number.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../transactions/presentation/list/txn_row.dart' show TxnFmt;
import '../../../wealth/presentation/balance_source_text.dart';
import '../../../wealth/presentation/net_worth_breakdown_providers.dart';
import '../../../wealth/presentation/net_worth_breakdown_screen.dart'
    show showSetBalanceSheet;
import '../../data/accounts_providers.dart';
import '../../domain/account.dart';
import '../../domain/accounts_repository.dart';
import '../money_overview_provider.dart';
import 'card_detail_providers.dart';

/// The accounts a card could be linked to, best first.
final linkTargetsProvider = FutureProvider.family<List<LinkTarget>, String>((
  ref,
  cardId,
) async {
  final repo = await ref.watch(accountsRepositoryProvider.future);
  return repo.linkTargets(cardId);
}, name: 'linkTargetsProvider');

/// The live cards linked to an account.
final linkedCardsProvider = FutureProvider.family<List<Account>, String>((
  ref,
  accountId,
) async {
  final repo = await ref.watch(accountsRepositoryProvider.future);
  return repo.cardsLinkedTo(accountId);
}, name: 'linkedCardsProvider');

void _refresh(WidgetRef ref) {
  ref
    ..invalidate(cardDetailAccountProvider)
    ..invalidate(linkTargetsProvider)
    ..invalidate(linkedCardsProvider)
    ..invalidate(netWorthBreakdownProvider)
    ..invalidate(moneyOverviewProvider);
}

String _name(Account a) => formatAccountWithCard(a.label, a.last4);

Future<void> _run(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(AccountsRepository repo) body,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final failed = AppLocalizations.of(context).accountsLinkFailed;
  try {
    final repo = await ref.read(accountsRepositoryProvider.future);
    await body(repo);
  } on Object {
    messenger?.showSnackBar(SnackBar(content: Text(failed)));
  } finally {
    _refresh(ref);
  }
}

/// Links [card] to [targetId] (the user's tap).
Future<void> linkCardTo(
  BuildContext context,
  WidgetRef ref,
  Account card,
  String targetId,
) => _run(
  context,
  ref,
  (repo) => repo.linkCard(cardId: card.id, accountId: targetId),
);

/// The picker: every account the card can be linked to, best first.
Future<void> showLinkPicker(
  BuildContext context,
  WidgetRef ref,
  Account card,
) => showZSheet<void>(
  context: context,
  title: AppLocalizations.of(context).accountsLinkSheetTitle,
  builder: (ctx) => _LinkPicker(card: card),
);

class _LinkPicker extends ConsumerWidget {
  const _LinkPicker({required this.card});
  final Account card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final targets = ref.watch(linkTargetsProvider(card.id));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l.accountsLinkSheetHint,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.md),
        ...targets.when(
          loading: () => [const LinearProgressIndicator()],
          error: (_, _) => [Text(l.commonErrorLoadFailed)],
          data: (ts) => ts.isEmpty
              ? [
                  Text(
                    l.accountsLinkNoTargets,
                    key: const Key('card-link-none'),
                    style: ZType.body.copyWith(color: c.text),
                  ),
                ]
              : [
                  for (final t in ts)
                    ListTile(
                      key: Key('card-link-target-${t.account.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        t.account.id == card.linkedAccountId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: c.primary,
                      ),
                      title: Text(
                        _name(t.account),
                        style: ZType.body.copyWith(color: c.text),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await linkCardTo(context, ref, card, t.account.id);
                      },
                    ),
                ],
        ),
      ],
    );
  }
}

Future<bool?> _confirmUnlink(BuildContext context) {
  final l = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('card-unlink-confirm'),
      title: Text(l.accountsLinkUnlinkTitle),
      content: Text(l.accountsLinkUnlinkBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.commonActionCancel),
        ),
        TextButton(
          key: const Key('card-unlink-yes'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.accountsLinkUnlink),
        ),
      ],
    ),
  );
}

/// The link card of S-41: for a debit card its link, for an account its
/// cards and the "Set current amount" action; nothing for other kinds.
class CardLinkSection extends ConsumerWidget {
  const CardLinkSection({
    super.key,
    required this.account,
    required this.cur,
    this.onOpenCard,
  });

  final Account account;

  /// The currency the screen shows (the current amount is typed in it).
  final Currency cur;

  /// Opens a linked card's S-41.
  final ValueChanged<Account>? onOpenCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (account.kind.canBeLinked) return _cardSide(context, ref);
    if (account.kind.canHoldCards) return _accountSide(context, ref);
    return const SizedBox.shrink();
  }

  Widget _cardSide(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final target = account.linkedAccountId;
    final children = <Widget>[
      Semantics(
        header: true,
        child: Text(
          l.accountsLinkTitle,
          style: ZType.title.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.sm),
    ];
    if (target != null) {
      final linked = ref.watch(cardDetailAccountProvider(target)).value;
      children
        ..add(
          Text(
            linked == null ? '' : _name(linked.account),
            key: const Key('card-linked-name'),
            style: ZType.body.copyWith(color: c.text),
          ),
        )
        ..add(
          Wrap(
            spacing: ZSpacing.sm,
            children: [
              TextButton(
                key: const Key('card-link-change'),
                onPressed: () => showLinkPicker(context, ref, account),
                child: Text(l.accountsLinkChange),
              ),
              TextButton(
                key: const Key('card-link-unlink'),
                onPressed: () async {
                  final ok = await _confirmUnlink(context);
                  if (ok != true || !context.mounted) return;
                  await _run(
                    context,
                    ref,
                    (repo) => repo.unlinkCard(account.id),
                  );
                },
                child: Text(l.accountsLinkUnlink),
              ),
            ],
          ),
        );
    } else {
      final targets = ref.watch(linkTargetsProvider(account.id)).value;
      final best = targets == null || targets.isEmpty ? null : targets.first;
      if (best != null && best.isSuggestion) {
        children
          ..add(
            Text(
              l.accountsLinkSuggest(_name(best.account)),
              key: const Key('card-link-suggest'),
              style: ZType.body.copyWith(color: c.text),
            ),
          )
          ..add(
            Wrap(
              spacing: ZSpacing.sm,
              children: [
                TextButton(
                  key: const Key('card-link-yes'),
                  onPressed: () =>
                      linkCardTo(context, ref, account, best.account.id),
                  child: Text(l.accountsLinkSuggestYes),
                ),
                TextButton(
                  key: const Key('card-link-pick'),
                  onPressed: () => showLinkPicker(context, ref, account),
                  child: Text(l.accountsLinkPick),
                ),
              ],
            ),
          );
      } else {
        children
          ..add(
            Text(
              l.accountsLinkNone,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          )
          ..add(
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('card-link-pick'),
                onPressed: () => showLinkPicker(context, ref, account),
                child: Text(l.accountsLinkPick),
              ),
            ),
          );
      }
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.lg),
      child: ZCard(
        key: const Key('card-link-section'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _accountSide(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cards = ref.watch(linkedCardsProvider(account.id)).value ?? const [];
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.lg),
      child: ZCard(
        key: const Key('account-link-section'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('account-set-current'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showSetBalanceSheet(
                  context,
                  ref,
                  accountId: account.id,
                  name: account.label,
                  currency: cur,
                  isLiability: false,
                ),
                label: Text(l.accountsSetCurrentAmount),
              ),
            ),
            if (cards.isNotEmpty) ...[
              const SizedBox(height: ZSpacing.sm),
              Semantics(
                header: true,
                child: Text(
                  l.accountsCardsOnAccount,
                  style: ZType.title.copyWith(color: c.text),
                ),
              ),
              for (final card in cards)
                ListTile(
                  key: Key('account-linked-card-${card.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.credit_card, color: c.textMuted),
                  title: Text(
                    _name(card),
                    style: ZType.body.copyWith(color: c.text),
                  ),
                  onTap: onOpenCard == null ? null : () => onOpenCard!(card),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The header of a linked debit card: the balance is the account's.
class LinkedCardHeader extends ConsumerWidget {
  const LinkedCardHeader({
    super.key,
    required this.account,
    required this.cur,
    required this.fmt,
  });

  final Account account;
  final Currency cur;
  final TxnFmt fmt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final target = account.linkedAccountId!;
    final linked = ref.watch(cardDetailAccountProvider(target)).value;
    final worth = ref.watch(netWorthBreakdownProvider).value;
    BreakdownLine? line;
    for (final x in worth?.lines ?? const <BreakdownLine>[]) {
      if (x.refId == target && x.unit == cur.code && x.isAccount) line = x;
    }
    final amount = line?.amount;
    return ZCard(
      key: const Key('card-linked-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.accountsDetailBalance,
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
          if (amount != null)
            ZMoneyText(
              text: fmt.money(amount),
              size: ZMoneySize.title,
              kind: ZMoneyKind.neutral,
            )
          else
            Text(
              l.accountsDetailBalanceUnknown,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          Text(
            l.accountsLinkBalanceOn(
              linked == null ? '' : _name(linked.account),
            ),
            style: ZType.caption.copyWith(color: c.textMuted),
          ),
          if (line != null && amount != null)
            Text(
              balanceSourceText(l, line, lang: fmt.lang, digits: fmt.digits),
              style: ZType.caption.copyWith(color: c.textMuted),
            ),
        ],
      ),
    );
  }
}
