// T-278 (D-86): the small currency cards under the Home hero. One card per
// non-primary currency with activity this month or a balance. Each card is
// that currency's own figures; nothing here adds two currencies.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/amount_semantics.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_sheet.dart';
import '../application/home_read_model.dart';
import 'home_format.dart';

/// At most this many cards show inline; the rest sit behind a `+N` chip.
const int homeCurrencyCardsInline = 3;

/// Opens that currency's view (`/currency/:iso`, T-279). A no-op while no
/// router is above [context] (widget tests, before the route exists).
void openCurrencyView(BuildContext context, Currency currency) {
  GoRouter.maybeOf(context)?.push('/currency/${currency.code}');
}

/// The ≈ line slot (T-280 plugs `HomeApproxLine` in at merge): null means
/// nothing is shown and no space is taken.
final homeApproxSlotBuilder = Provider<WidgetBuilder?>(
  (ref) => null,
  name: 'homeApproxSlotBuilder',
);

/// The cards row with its title, `+N` chip and the ≈ slot. Renders nothing
/// when [cards] is empty (EGP-only users see no currency UI).
class HomeCurrencyCards extends ConsumerWidget {
  const HomeCurrencyCards({
    super.key,
    required this.cards,
    required this.format,
    this.onOpen,
  });

  final List<HomeCurrencyCard> cards;
  final HomeFormat format;

  /// Overrides [openCurrencyView].
  final ValueChanged<Currency>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final open = onOpen ?? (cur) => openCurrencyView(context, cur);
    final shown = cards.take(homeCurrencyCardsInline).toList();
    final rest = cards.skip(homeCurrencyCardsInline).toList();
    final slot = ref.watch(homeApproxSlotBuilder);
    return Column(
      key: const ValueKey('home-currency-cards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ZSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            l.homeCurrencyCardsTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final card in shown)
              HomeCurrencyCardTile(
                card: card,
                format: format,
                onTap: () => open(card.currency),
              ),
            if (rest.isNotEmpty)
              _MoreChip(
                count: rest.length,
                format: format,
                onTap: () => showZSheet<void>(
                  context: context,
                  title: l.homeCurrencyCardsTitle,
                  builder: (ctx) => Padding(
                    padding: const EdgeInsetsDirectional.only(
                      bottom: ZSpacing.xl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final card in rest) ...[
                          HomeCurrencyCardTile(
                            card: card,
                            format: format,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              open(card.currency);
                            },
                          ),
                          const SizedBox(height: ZSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (slot != null) slot(context),
      ],
    );
  }
}

/// One small currency card.
class HomeCurrencyCardTile extends StatelessWidget {
  const HomeCurrencyCardTile({
    super.key,
    required this.card,
    required this.format,
    required this.onTap,
  });

  final HomeCurrencyCard card;
  final HomeFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final left = l.homeCurrencyCardLeft(format.moneyExact(card.left));
    final inOut = l.homeCurrencyCardInOut(
      format.number(card.moneyIn),
      format.number(card.out),
    );
    final label = a11yAmounts(
      l,
      l.homeCurrencyCardA11y(
        card.currency.code,
        format.moneyExact(card.left),
        format.moneyExact(card.moneyIn),
        format.moneyExact(card.out),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        key: ValueKey('home-currency-card-${card.currency.code}'),
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: IntrinsicWidth(
          child: ZCard(
            onTap: onTap,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.md,
              vertical: ZSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(left, style: ZType.titleSmall.copyWith(color: c.text)),
                Text(inOut, style: ZType.caption.copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.count,
    required this.format,
    required this.onTap,
  });

  final int count;
  final HomeFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final shape = BorderRadius.circular(ZRadius.pill);
    return Semantics(
      button: true,
      label: l.homeCurrencyCardMoreA11y(count, format.count(count)),
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: c.surfaceAlt,
        borderRadius: shape,
        child: InkWell(
          key: const ValueKey('home-currency-more'),
          borderRadius: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: ZSpacing.minTarget,
              minHeight: ZSpacing.minTarget,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: ZSpacing.md,
                ),
                child: Text(
                  l.homeCurrencyCardMore(format.count(count)),
                  style: ZType.label.copyWith(color: c.text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
