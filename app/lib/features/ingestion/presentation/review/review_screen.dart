// T-081: S-14 Review queue. Everything Zaghlol wasn't sure about, one card
// per item. Categorize and dismiss are applied after the Undo snackbar
// closes, so Undo is a plain cancel; leaving the screen applies what is
// pending. No message text is shown here; only the sender, amounts and
// merchant names.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/ui/bank_name_text.dart';
import '../../../../core/l10n/card_number.dart';
import '../../../../core/l10n/digits_mode.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/money_format.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_banner.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_card.dart';
import '../../../../core/ui/z_chip.dart';
import '../../../../core/ui/z_sheet.dart';
import '../../../budget/application/budget_providers.dart'
    show localZoneProvider;
import '../../../capture/presentation/template_builder_screen.dart';
import '../../../transactions/domain/transaction.dart' show TxnDirection;
import '../../../transfers/presentation/exchange_entry_screen.dart';
import '../../data/review_repository.dart' show ReviewException;
import 'review_models.dart';
import 'review_providers.dart';
import '../../../../core/ui/z_haptics.dart';
import '../../../../core/settings/settings_providers.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  ReviewFilter _filter = ReviewFilter.all;

  /// Items hidden while their Undo snackbar is up.
  final Set<String> _hidden = {};
  final Map<String, Future<void> Function()> _pending = {};
  late final ReviewActions _actions;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(reviewActionsProvider);
  }

  @override
  void dispose() {
    final rest = _pending.values.toList();
    _pending.clear();
    for (final run in rest) {
      // FU-173a: a failing job must not surface as an unhandled error.
      unawaited(run().catchError((Object _) {}));
    }
    super.dispose();
  }

  /// Hides [itemId], shows [message] with Undo, applies [run] unless undone.
  void _deferred(String itemId, String message, Future<void> Function() run) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(itemId));
    _pending[itemId] = run;
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(message),
            // A snackbar with an action stays up by default; the pending
            // action must apply after the normal delay.
            persist: false,
            action: SnackBarAction(
              label: l10n.commonActionUndo,
              onPressed: () {
                ZHaptics.light();
                _pending.remove(itemId);
                if (mounted) setState(() => _hidden.remove(itemId));
              },
            ),
          ),
        )
        .closed
        .then((_) async {
          final job = _pending.remove(itemId);
          try {
            if (job != null) await job();
          } on Object {
            // The deferred write failed: show the item again with an error.
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).reviewErrorSaveFailed,
                  ),
                ),
              );
            }
          }
          if (mounted) setState(() => _hidden.remove(itemId));
        });
  }

  Future<void> _now(Future<void> Function() run) async {
    try {
      await run();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).reviewErrorSaveFailed),
        ),
      );
    }
  }

  void _dismiss(String itemId) => _deferred(
    itemId,
    AppLocalizations.of(context).ingestionReviewDismissed,
    () => _actions.dismiss(itemId),
  );

  /// T-272: opens the exchange entry prefilled with the received side; the
  /// entry resolves this item when the exchange is saved.
  Future<void> _recordExchange(ExchangeJumpCardModel card) async {
    final zone = ProviderScope.containerOf(context).read(localZoneProvider);
    final ms = card.asOf.millisecondsSinceEpoch;
    final saved = await showExchangeEntry(
      context,
      prefill: ExchangePrefill(
        toAccountId: card.accountId,
        received: card.amount,
        date: CivilDate.fromLocalMs(ms, zone.offsetAtInstant(ms)),
        reviewItemId: card.itemId,
      ),
    );
    if (saved == true && mounted) {
      ProviderScope.containerOf(context).invalidate(reviewQueueProvider);
    }
  }

  Future<void> _requestBank(MessageCardModel card) async {
    final sent = await showZSheet<bool>(
      context: context,
      title: AppLocalizations.of(context).ingestionRequestBankTitle,
      builder: (_) => _RequestBankForm(
        initialName: card.sender,
        onSend: (name, country, channel) => _actions.requestBank(
          card.itemId,
          name: name,
          country: country,
          channel: channel,
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).ingestionRequestBankSent),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(reviewQueueProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        leadingWidth: 64,
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context)
            ? Center(
                child: BackButton(
                  style: IconButton.styleFrom(
                    fixedSize: const Size(40, 40),
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsetsDirectional.zero,
                    tapTargetSize: MaterialTapTargetSize.padded,
                    backgroundColor: ZColors.of(context).surface,
                    foregroundColor: ZColors.of(context).text,
                    elevation: 3,
                    shadowColor: ZColors.of(context).shadow,
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              ZSpacing.screen,
              0,
              ZSpacing.screen,
              ZSpacing.md,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                header: true,
                child: Text(
                  l10n.ingestionReviewTitle,
                  style: ZType.display.copyWith(
                    color: ZColors.of(context).text,
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _content(queue, l10n)),
        ],
      ),
    );
  }

  Widget _content(
    AsyncValue<List<ReviewCardModel>> queue,
    AppLocalizations l10n,
  ) {
    return queue.when(
      loading: () => const _Skeleton(),
      error: (_, _) => Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        child: ZBanner(
          message: l10n.commonErrorLoadFailed,
          tone: ZBannerTone.error,
          actionLabel: l10n.commonActionTryAgain,
          onAction: () => ref.invalidate(reviewQueueProvider),
        ),
      ),
      data: (all) {
        final visible = all.where((c) => !_hidden.contains(c.itemId)).toList();
        final shown = visible
            .where((c) => _filter == ReviewFilter.all || c.filter == _filter)
            .toList();
        if (visible.isEmpty) return const _Empty();
        return Column(
          children: [
            _Filters(
              selected: _filter,
              total: visible.length,
              onSelect: (f) => setState(() => _filter = f),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: ZSpacing.md),
                itemBuilder: (context, i) => _swipeable(shown[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _swipeable(ReviewCardModel card) {
    final l10n = AppLocalizations.of(context);
    final canAccept =
        (card is MessageCardModel && card.canConfirm) ||
        (card is SuggestionCardModel &&
            !card.ambiguousRefund &&
            !card.isPair) ||
        card is SubscriptionCardModel;
    return Dismissible(
      key: ValueKey(card.itemId),
      direction: canAccept
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      background: const _SwipeBg(accept: true),
      secondaryBackground: const _SwipeBg(accept: false),
      confirmDismiss: (dir) async {
        ZHaptics.light();
        if (dir == DismissDirection.startToEnd) {
          await _now(() => _accept(card));
        } else {
          _dismissCard(card);
        }
        return false;
      },
      child: Semantics(
        customSemanticsActions: {
          if (canAccept)
            CustomSemanticsAction(
              label: l10n.ingestionReviewSwipeAcceptA11y,
            ): () =>
                unawaited(_now(() => _accept(card))),
          CustomSemanticsAction(
            label: l10n.ingestionReviewSwipeDismissA11y,
          ): () =>
              _dismissCard(card),
        },
        child: _cardFor(card),
      ),
    );
  }

  Future<void> _accept(ReviewCardModel card) => switch (card) {
    SubscriptionCardModel() => _actions.confirmSubscription(card),
    // A suggestion with no stored transaction: only a complete one is saved
    // by a swipe; anything else would be lost, so the swipe does nothing.
    MessageCardModel(txnId: null) =>
      card.oneTap ? _confirmGeneric(card) : Future<void>.value(),
    _ => _actions.accept(card.itemId),
  };

  /// SMS-fuzzy: one tap saves a complete generic suggestion, then offers to
  /// teach Zaghlol this message shape (custom template, T-164).
  Future<void> _confirmGeneric(
    MessageCardModel card, {
    bool keep = false,
  }) async {
    var saved = false;
    try {
      saved = await _actions.confirmGeneric(card, keep: keep);
    } on ReviewException {
      saved = false;
    }
    final rawId = card.rawMessageId;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (!saved) {
      // Refused (already resolved, or no longer complete): say so instead of
      // leaving the card as if nothing was tapped.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.reviewErrorSaveFailed)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        // TODO(SMS-fuzzy): copy-deck keys ingestionReviewGenSaved and
        // ingestionReviewGenMakeTemplate (T-087 branch); interim reuse.
        // The teach button lives in the content (its label wraps) instead of
        // a SnackBarAction, whose label overflowed at 1.3x in English.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.accountsEditSaved),
            if (rawId != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () {
                    ZHaptics.light();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    unawaited(_learn(rawId));
                  },
                  child: Text(l10n.templatesBuilderTitle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _learn(String rawMessageId) async {
    final sample = await _actions.templateSample(rawMessageId);
    if (sample == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TemplateBuilderScreen(initialSample: sample),
      ),
    );
  }

  /// T-250: Remove deletes at once through the normal delete path; Undo
  /// puts the transaction back (same as deleting from its detail screen).
  Future<void> _removeOldDue(OldDueCardModel card) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final batchId = await _actions.removeOldDue(card);
    messenger.hideCurrentSnackBar();
    if (batchId == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.ingestionReviewOldDueAlreadyHandled)),
      );
      return;
    }
    final actions = _actions;
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.ingestionReviewOldDueRemoved),
        persist: false,
        action: SnackBarAction(
          label: l10n.commonActionUndo,
          onPressed: () {
            ZHaptics.light();
            // Outlives the screen: no `ref` or `context` here.
            unawaited(
              actions.undoRemoveOldDue(batchId).catchError((Object _) {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.reviewErrorSaveFailed)),
                );
              }),
            );
          },
        ),
      ),
    );
  }

  Future<void> _keepOldDue(OldDueCardModel card) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final kept = await _actions.keepOldDue(card);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            kept ? l10n.ingestionReviewOldDueKept : l10n.reviewErrorSaveFailed,
          ),
        ),
      );
  }

  void _dismissCard(ReviewCardModel card) {
    if (card is SubscriptionCardModel) {
      _deferred(
        card.itemId,
        AppLocalizations.of(context).ingestionReviewDismissed,
        () => _actions.dismissSubscription(card),
      );
    } else {
      _dismiss(card.itemId);
    }
  }

  Widget _cardFor(ReviewCardModel card) => switch (card) {
    CategoryCardModel() => _CategoryCard(
      card: card,
      onPick: (cat, name) => _deferred(
        card.itemId,
        AppLocalizations.of(context).ingestionReviewCategorized(name),
        () => _actions.categorize(card, cat),
      ),
    ),
    MessageCardModel() => _MessageCard(
      card: card,
      onConfirm: () => _now(
        () => card.txnId == null
            ? _confirmGeneric(card)
            : _actions.accept(card.itemId),
      ),
      onKeep: () => _now(() => _confirmGeneric(card, keep: true)),
      onEdit: () => context.push(AppRoutes.add),
      onDismiss: () => _dismiss(card.itemId),
      onRequestBank: () => _requestBank(card),
    ),
    TransferCardModel() => _TransferCard(
      card: card,
      onConfirm: (o) => _now(() => _actions.resolveTransfer(card, o)),
    ),
    SubscriptionCardModel() => _SuggestionShell(
      body: _amountLine(
        context,
        card.amount,
        isIncome: false,
        merchant: card.name,
      ),
      onConfirm: () => _now(() => _actions.confirmSubscription(card)),
      onDismiss: () => _dismissCard(card),
    ),
    ExchangeJumpCardModel() => _ExchangeJumpCard(
      card: card,
      onRecord: () => _now(() => _recordExchange(card)),
      onNo: () => _dismiss(card.itemId),
    ),
    OldDueCardModel() => _OldDueCard(
      card: card,
      onRemove: () => _now(() => _removeOldDue(card)),
      onKeep: () => _now(() => _keepOldDue(card)),
    ),
    SuggestionCardModel(isPair: true) => _PairCard(
      card: card,
      onConfirm: (o) =>
          _now(() => _actions.acceptCandidate(card.itemId, o.txnId)),
      onDismiss: () => _dismiss(card.itemId),
    ),
    SuggestionCardModel() => _SuggestionShell(
      body: _amountLine(
        context,
        card.amount,
        isIncome: card.isIncome,
        merchant: card.merchant,
      ),
      onConfirm: card.ambiguousRefund
          ? null
          : () => _now(() => _actions.accept(card.itemId)),
      onDismiss: () => _dismiss(card.itemId),
    ),
  };
}

/// Outbox channel codes (stored values, not UI text).
const String _channelSms = 'sms';
const String _channelNotification = 'notification';

String _iso(String s) => '\u2068$s\u2069';

/// "{amount} at {merchant}" or just the amount; empty when there is neither.
Widget _amountLine(
  BuildContext context,
  Money? amount, {
  required bool isIncome,
  String? merchant,
}) {
  if (amount == null) return const SizedBox.shrink();
  final l10n = AppLocalizations.of(context);
  final text = _money(context, amount);
  final m = merchant;
  final line = m == null || m.isEmpty
      ? text
      : l10n.ingestionReviewCatAt(text, m);
  return Text(
    line,
    style: ZType.titleSmall.copyWith(color: ZColors.of(context).text),
  );
}

String _money(BuildContext context, Money m) {
  final lang = Localizations.localeOf(context).languageCode;
  final container = ProviderScope.containerOf(context);
  return MoneyFormat.format(
    m,
    languageCode: lang,
    digits: container.read(digitsModeProvider(lang)),
    hidden: container.read(hideAmountsProvider),
  );
}

/// Everything a one-tap Confirm stores beyond the guess line: the kind,
/// the date and the account (bank + last-4, or the bank's account).
String _oneTapDetails(
  BuildContext context,
  MessageCardModel card, {
  String? bankName,
}) {
  final l10n = AppLocalizations.of(context);
  final lang = Localizations.localeOf(context).languageCode;
  final DigitsMode digits = ProviderScope.containerOf(context)
      .read(digitsModeProvider(lang));
  final kind = switch (card.direction) {
    TxnDirection.income => l10n.commonTxnTypeIncome,
    TxnDirection.transferOut ||
    TxnDirection.transferIn => l10n.commonTxnTypeTransfer,
    TxnDirection.refund => l10n.commonTxnTypeRefund,
    _ => l10n.commonTxnTypeExpense,
  };
  final when = card.occurredAt;
  final bank = _iso(bankName ?? card.bankLabel ?? card.sender);
  final last4 = card.last4;
  final account = last4 == null
      ? '$bank · ${l10n.commonAccountTypeAccount}'
      : formatAccountWithCard(bank, last4);
  return [
    kind,
    if (when != null) ZDateFormat.date(when, lang, digits),
    account,
  ].join(' · ');
}

String _time(BuildContext context, DateTime t) {
  final lang = Localizations.localeOf(context).languageCode;
  final DigitsMode digits = ProviderScope.containerOf(context)
      .read(digitsModeProvider(lang));
  return ZDateFormat.time(t.toLocal(), lang, digits);
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.selected,
    required this.total,
    required this.onSelect,
  });
  final ReviewFilter selected;
  final int total;
  final ValueChanged<ReviewFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ProviderScope.containerOf(context)
        .read(digitsModeProvider(lang));
    final labels = {
      ReviewFilter.all: l10n.ingestionReviewFilterAll(
        digits.render(total.toString()),
      ),
      ReviewFilter.category: l10n.ingestionReviewFilterCategory,
      ReviewFilter.messages: l10n.ingestionReviewFilterMessages,
      ReviewFilter.transfers: l10n.ingestionReviewFilterTransfers,
    };
    return SizedBox(
      height: ZSpacing.minTarget + ZSpacing.md,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: ZSpacing.screen,
        ),
        children: [
          for (final f in ReviewFilter.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
              child: Center(
                child: _FilterPill(
                  label: labels[f]!,
                  selected: f == selected,
                  onTap: () => onSelect(f),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Filter / answer pill: white with a soft shadow, mint when selected
/// (05-review-queue mockup). 48 dp target, 40 dp visual.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final shape = BorderRadius.circular(ZRadius.pill);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: Center(
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? c.primaryContainer : c.surface,
              borderRadius: shape,
              border: selected ? null : c.flatBorder,
              boxShadow: selected
                  ? null
                  : [
                      BoxShadow(
                        color: c.shadow,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: shape,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.lg,
                    vertical: ZSpacing.sm,
                  ),
                  child: Text(
                    label,
                    style: ZType.titleSmall.copyWith(
                      color: selected ? c.primary : c.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.accept});
  final bool accept;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: accept ? c.primaryContainer : c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.card),
      ),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: ZSpacing.xl),
      alignment: accept
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: Icon(
        accept ? Icons.check_rounded : Icons.close_rounded,
        color: c.text,
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.card, required this.onPick});
  final CategoryCardModel card;
  final void Function(String categoryId, String categoryName) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final cats = ref.watch(reviewCategoriesProvider).value ?? const [];
    final amount = _money(context, card.amount);
    final who = card.counterparty ?? card.merchant;
    final title = who == null || who.isEmpty
        ? amount
        : card.counterparty != null
        ? (card.isIncome
              ? l10n.ingestionReviewCatIn(amount, who)
              : l10n.ingestionReviewCatOut(amount, who))
        : l10n.ingestionReviewCatAt(amount, who);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.surfaceAlt,
                  ),
                  child: Icon(Icons.person, color: c.textMuted),
                ),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Text(
                  _iso(title),
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.lg),
          Text(
            l10n.ingestionReviewCatQuestion,
            style: ZType.title.copyWith(color: c.text),
          ),
          const SizedBox(height: ZSpacing.sm),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.xs,
            children: [
              for (final cat in cats)
                _FilterPill(
                  label: ar ? cat.nameAr : cat.nameEn,
                  onTap: () => onPick(cat.id, ar ? cat.nameAr : cat.nameEn),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.card,
    required this.onConfirm,
    required this.onKeep,
    required this.onEdit,
    required this.onDismiss,
    required this.onRequestBank,
  });
  final MessageCardModel card;
  final VoidCallback onConfirm;
  final VoidCallback onKeep;
  final VoidCallback onEdit;
  final VoidCallback onDismiss;
  final VoidCallback onRequestBank;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final amount = card.amount;
    String? guess;
    if (amount != null) {
      final a = _money(context, amount);
      final m = card.merchant;
      guess = card.isIncome
          ? l10n.ingestionReviewGenGuessIn(a)
          : (m == null || m.isEmpty)
          ? l10n.ingestionReviewGenGuessNoMerchant(a)
          : l10n.ingestionReviewGenGuessOut(a, _iso(m));
    }
    final actions = <Widget>[
      if (card.canConfirm)
        ZButton(
          label: l10n.commonActionConfirm,
          haptic: ZHaptic.medium,
          expand: true,
          onPressed: onConfirm,
        ),
      // PO 2026-11-16: a doubtful message can be saved as shown in one tap.
      if (card.txnId == null && !card.oneTap)
        ZButton(
          key: const ValueKey('reviewKeep'),
          label: l10n.ingestionReviewKeep,
          haptic: ZHaptic.medium,
          expand: true,
          onPressed: card.offersKeep ? onKeep : null,
        ),
      ZButton(
        label: card.canConfirm
            ? l10n.commonActionEdit
            : l10n.ingestionReviewUnreadEnter,
        variant: ZButtonVariant.secondary,
        expand: true,
        onPressed: onEdit,
      ),
      ZButton(
        label: l10n.commonActionDismiss,
        variant: card.unreadable
            ? ZButtonVariant.text
            : ZButtonVariant.secondary,
        expand: true,
        onPressed: onDismiss,
      ),
    ];
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: BankNameText(
                  name: card.sender,
                  institutionCode: card.institutionCode,
                  maxLines: 2,
                  compose: (n) => card.unreadable
                      ? l10n.ingestionReviewUnreadTitle(_iso(n))
                      : l10n.ingestionReviewGenFrom(_iso(n)),
                  style: ZType.body.copyWith(color: c.textMuted),
                ),
              ),
              if (card.isNewSender) ...[
                const SizedBox(width: ZSpacing.sm),
                ZPill(
                  label: l10n.ingestionReviewNewBank,
                  tone: ZPillTone.warning,
                ),
              ],
            ],
          ),
          if (guess != null) ...[
            const SizedBox(height: ZSpacing.sm),
            Text(guess, style: ZType.title.copyWith(color: c.text)),
            if (card.oneTap || card.keepable)
              BankNameText(
                textKey: const ValueKey('reviewOneTapDetails'),
                name: card.bankLabel ?? card.sender,
                institutionCode: card.institutionCode,
                maxLines: 3,
                compose: (n) => _oneTapDetails(context, card, bankName: n),
                style: ZType.body.copyWith(color: c.text),
              ),
            Text(
              l10n.ingestionReviewGenLowConfidence,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ],
          if (card.txnId == null && !card.oneTap && !card.keepable)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
              child: Text(
                key: const ValueKey('reviewKeepReason'),
                card.amount == null
                    ? l10n.ingestionReviewKeepNoAmount
                    : l10n.ingestionReviewKeepMissing,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          if (card.originalText != null)
            _OriginalText(text: card.originalText!),
          const SizedBox(height: ZSpacing.lg),
          if (actions.length > 2) ...[
            // Three actions never fit side by side at large text: the main
            // one takes the full width, the other two share the next line
            // (or stack when the text is scaled up).
            actions.first,
            const SizedBox(height: ZSpacing.sm),
            if (MediaQuery.textScalerOf(context).scale(16) > 18)
              for (var i = 1; i < actions.length; i++) ...[
                if (i > 1) const SizedBox(height: ZSpacing.sm),
                actions[i],
              ]
            else
              Row(
                children: [
                  for (var i = 1; i < actions.length; i++) ...[
                    if (i > 1) const SizedBox(width: ZSpacing.sm),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
          ] else
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: ZSpacing.sm),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          if (card.sender.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ZButton(
                label: l10n.ingestionReviewRequestBank,
                variant: ZButtonVariant.text,
                onPressed: onRequestBank,
              ),
            ),
        ],
      ),
    );
  }
}

/// SMS-AUTO: the original message, collapsed. The text stays on screen only
/// (selectable; the text's own script decides its direction).
class _OriginalText extends StatefulWidget {
  const _OriginalText({required this.text});
  final String text;

  @override
  State<_OriginalText> createState() => _OriginalTextState();
}

class _OriginalTextState extends State<_OriginalText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('reviewOriginalText'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        onExpansionChanged: (v) => setState(() => _open = v),
        title: Text(
          _open
              ? l10n.ingestionReviewHideOriginal
              : l10n.ingestionReviewShowOriginal,
          style: ZType.body.copyWith(color: c.textMuted),
        ),
        children: [
          SelectableText(
            widget.text,
            key: const ValueKey('reviewOriginalBody'),
            style: ZType.bodySmall.copyWith(color: c.text),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatefulWidget {
  const _TransferCard({required this.card, required this.onConfirm});
  final TransferCardModel card;
  final void Function(ReviewTransferOption? option) onConfirm;

  @override
  State<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<_TransferCard> {
  /// `-1` is "Not my transfer"; null is no choice yet.
  int? _choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final card = widget.card;
    return ZCard(
      child: RadioGroup<int>(
        groupValue: _choice,
        onChanged: (v) => setState(() => _choice = v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ingestionReviewXferTitle(
                _money(context, card.amount),
                _iso(card.accountLabel),
              ),
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            for (var i = 0; i < card.options.length; i++)
              _option(
                i,
                l10n.ingestionReviewXferOption(
                  _money(context, card.options[i].amount),
                  _iso(card.options[i].accountLabel),
                  _time(context, card.options[i].occurredAt),
                ),
              ),
            _option(-1, l10n.ingestionReviewXferNotMine),
            const SizedBox(height: ZSpacing.sm),
            ZButton(
              label: l10n.commonActionConfirm,
              haptic: ZHaptic.medium,
              onPressed: _choice == null
                  ? null
                  : () => widget.onConfirm(
                      _choice == -1 ? null : card.options[_choice!],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(int value, String label) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
    child: RadioListTile<int>(
      value: value,
      contentPadding: EdgeInsetsDirectional.zero,
      title: Text(label, style: ZType.body),
    ),
  );
}

/// Reimbursement / FX pair suggestion: lists the candidate expenses; a link is
/// made only for the one the user picked (the only one is pre-selected).
class _PairCard extends StatefulWidget {
  const _PairCard({
    required this.card,
    required this.onConfirm,
    required this.onDismiss,
  });
  final SuggestionCardModel card;
  final void Function(ReviewTransferOption option) onConfirm;
  final VoidCallback onDismiss;

  @override
  State<_PairCard> createState() => _PairCardState();
}

class _PairCardState extends State<_PairCard> {
  int? _choice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final card = widget.card;
    final opts = card.candidates;
    final choice = opts.length == 1 ? 0 : _choice;
    String xfer(ReviewTransferOption o) => l10n.ingestionReviewXferOption(
      _money(context, o.amount),
      _iso(o.accountLabel),
      _time(context, o.occurredAt),
    );
    return ZCard(
      child: RadioGroup<int>(
        groupValue: choice,
        onChanged: (v) => setState(() => _choice = v),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _amountLine(
              context,
              card.amount,
              isIncome: card.isIncome,
              merchant: card.merchant,
            ),
            for (var i = 0; i < opts.length; i++)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: ZSpacing.minTarget,
                ),
                child: RadioListTile<int>(
                  value: i,
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(
                    (opts[i].merchant ?? '').isNotEmpty
                        ? _iso(opts[i].merchant!)
                        : xfer(opts[i]),
                    style: ZType.body,
                  ),
                  subtitle: (opts[i].merchant ?? '').isEmpty
                      ? null
                      : Text(xfer(opts[i]), style: ZType.body),
                ),
              ),
            const SizedBox(height: ZSpacing.sm),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                ZButton(
                  label: l10n.commonActionConfirm,
                  haptic: ZHaptic.medium,
                  onPressed: choice == null
                      ? null
                      : () => widget.onConfirm(opts[choice]),
                ),
                ZButton(
                  label: l10n.commonActionDismiss,
                  variant: ZButtonVariant.text,
                  onPressed: widget.onDismiss,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionShell extends StatelessWidget {
  const _SuggestionShell({
    required this.body,
    required this.onConfirm,
    required this.onDismiss,
  });
  final Widget body;
  final VoidCallback? onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              if (onConfirm != null)
                ZButton(
                  label: l10n.commonActionConfirm,
                  haptic: ZHaptic.medium,
                  onPressed: onConfirm,
                ),
              ZButton(
                label: l10n.commonActionDismiss,
                variant: ZButtonVariant.text,
                onPressed: onDismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// T-272: "Did you exchange money? Your EGP rose by about X."
class _ExchangeJumpCard extends StatelessWidget {
  const _ExchangeJumpCard({
    required this.card,
    required this.onRecord,
    required this.onNo,
  });
  final ExchangeJumpCardModel card;
  final VoidCallback onRecord;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final container = ProviderScope.containerOf(context);
    final digits = container.read(digitsModeProvider(lang));
    final colors = ZColors.of(context);
    final amount = MoneyFormat.format(
      card.amount,
      languageCode: lang,
      digits: digits,
      withCurrency: false,
      dropZeroFraction: true,
      hidden: container.read(hideAmountsProvider),
    );
    return ZCard(
      key: ValueKey('exchange-jump-${card.itemId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.ingestionReviewExchangeJumpQuestion(
              MoneyFormat.currencyLabel(
                card.amount.currency,
                languageCode: lang,
              ),
              amount,
            ),
            style: ZType.body.copyWith(color: colors.text),
          ),
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              ZButton(
                label: l10n.ingestionReviewExchangeJumpYes,
                haptic: ZHaptic.medium,
                onPressed: onRecord,
              ),
              ZButton(
                label: l10n.ingestionReviewExchangeJumpNo,
                variant: ZButtonVariant.text,
                onPressed: onNo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// T-250: "This was a payment-due reminder, not spending — remove it?"
class _OldDueCard extends StatelessWidget {
  const _OldDueCard({
    required this.card,
    required this.onRemove,
    required this.onKeep,
  });
  final OldDueCardModel card;
  final VoidCallback onRemove;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ProviderScope.containerOf(context)
        .read(digitsModeProvider(lang));
    final colors = ZColors.of(context);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.ingestionReviewOldDueQuestion,
            style: ZType.body.copyWith(color: colors.text),
          ),
          const SizedBox(height: ZSpacing.sm),
          _amountLine(
            context,
            card.amount,
            isIncome: false,
            merchant: card.merchant,
          ),
          Text(
            ZDateFormat.date(card.occurredAt.toLocal(), lang, digits),
            style: ZType.bodySmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              ZButton(
                label: l10n.ingestionReviewOldDueRemove,
                haptic: ZHaptic.medium,
                onPressed: onRemove,
              ),
              ZButton(
                label: l10n.ingestionReviewOldDueKeep,
                variant: ZButtonVariant.text,
                onPressed: onKeep,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: c.primary),
            const SizedBox(height: ZSpacing.md),
            Text(
              AppLocalizations.of(context).ingestionReviewEmptyTitle,
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(ZRadius.card),
                ),
                child: const SizedBox(height: 120, width: double.infinity),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestBankForm extends StatefulWidget {
  const _RequestBankForm({required this.initialName, required this.onSend});
  final String initialName;
  final Future<void> Function(String name, String country, String channel)
  onSend;

  @override
  State<_RequestBankForm> createState() => _RequestBankFormState();
}

class _RequestBankFormState extends State<_RequestBankForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final TextEditingController _country = TextEditingController(text: 'EG');
  String _channel = _channelSms;
  bool _busy = false;
  bool _failed = false;
  String? _nameError;
  String? _countryError;

  @override
  void dispose() {
    _name.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final country = _country.text.trim().toUpperCase();
    final nameBad = name.length < 2 || name.length > 60;
    final countryBad = !RegExp(r'^[A-Z]{2}$').hasMatch(country);
    setState(() {
      _nameError = nameBad
          ? l10n.ingestionRequestBankNameLength('2', '60')
          : null;
      _countryError = countryBad
          ? l10n.ingestionRequestBankCountryRequired
          : null;
      _failed = false;
    });
    if (nameBad || countryBad) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(name, country, _channel);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _name,
          inputFormatters: [LengthLimitingTextInputFormatter(60)],
          decoration: InputDecoration(
            labelText: l10n.ingestionRequestBankName,
            errorText: _nameError,
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        TextField(
          controller: _country,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(2)],
          decoration: InputDecoration(
            labelText: l10n.ingestionRequestBankCountry,
            errorText: _countryError,
          ),
        ),
        const SizedBox(height: ZSpacing.md),
        Text(
          l10n.ingestionRequestBankChannel,
          style: ZType.label.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.sm,
          children: [
            ZChip(
              label: l10n.commonSourceSms,
              selected: _channel == _channelSms,
              onTap: () => setState(() => _channel = _channelSms),
            ),
            ZChip(
              label: l10n.commonSourceNotification,
              selected: _channel == _channelNotification,
              onTap: () => setState(() => _channel = _channelNotification),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.md),
        Text(
          l10n.ingestionRequestBankPrivacy,
          style: ZType.bodySmall.copyWith(color: c.textMuted),
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: ZBanner(
              message: l10n.ingestionRequestBankFailed,
              tone: ZBannerTone.error,
            ),
          ),
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: l10n.commonActionSend,
          loading: _busy,
          expand: true,
          onPressed: _send,
        ),
        const SizedBox(height: ZSpacing.md),
      ],
    );
  }
}
