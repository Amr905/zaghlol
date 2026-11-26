// T-281 (D-86, plan §1 S-11): an exchange is one row in S-11. «غيّرت
// {from} ← {to}» with the bank's rate and "not spending" under it. Both
// amounts stay in their own currency (bidi-isolated runs); nothing is
// converted or summed. Nothing here logs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database_providers.dart';
import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/amount_semantics.dart';
import '../../../../core/ui/z_components.dart';
import '../../../transfers/presentation/exchange_entry_screen.dart'
    show formatRateE9;
import '../../data/exchange_reader.dart';
import '../../data/transactions_providers.dart';
import '../../domain/exchange.dart';
import 'txn_list_providers.dart';
import 'txn_row.dart';

/// The exchanges among the loaded list rows, keyed by both leg ids. Under a
/// currency filter only one leg is loaded; the pair is still found, so the
/// exchange keeps its one row.
final txnExchangesProvider =
    FutureProvider.autoDispose<Map<String, TxnExchange>>((ref) async {
      final list = await ref.watch(txnListProvider.future);
      final ids = [
        for (final t in list.items)
          if (t.isInternal) t.id,
      ];
      if (ids.isEmpty) return const {};
      final db = await ref.watch(appDatabaseProvider.future);
      final repo = await ref.watch(transactionRepositoryProvider.future);
      return ExchangeReader(db, repo).forTransactions(ids);
    }, name: 'txnExchangesProvider');

/// The second line: the bank rate and "not spending". With amounts hidden
/// (D-67) only "not spending".
String exchangeRateLine(AppLocalizations l, TxnExchange x, TxnFmt fmt) {
  final rate = x.rate;
  if (rate == null || fmt.hidden) return l.transactionsExchangeNotSpending;
  return l.transactionsExchangeRate(
    fmt.digits.render(formatRateE9(rate.rateE9)),
  );
}

/// The exchange title «غيّرت {from} ← {to}».
String exchangeTitle(AppLocalizations l, TxnExchange x, TxnFmt fmt) =>
    l.transactionsExchangeTitle(
      fmt.money(x.sent.amount.abs()),
      fmt.money(x.received.amount.abs()),
    );

class TxnExchangeRow extends StatelessWidget {
  const TxnExchangeRow({
    super.key,
    required this.exchange,
    required this.fmt,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.divider = false,
  });

  final TxnExchange exchange;
  final TxnFmt fmt;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final x = exchange;
    final title = exchangeTitle(l, x, fmt);
    final rateLine = exchangeRateLine(l, x, fmt);
    final time = ZDateFormat.time(x.sent.occurredAt, fmt.lang, fmt.digits);
    final Widget leading = selecting
        ? Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? c.primary : c.textMuted,
            size: 40,
          )
        : ZCategoryTile(
            size: 44,
            color: c.primary,
            child: Icon(Icons.currency_exchange, color: c.primary, size: 22),
          );
    return Semantics(
      container: true,
      selected: selected,
      onLongPress: onLongPress,
      label: a11yAmounts(
        l,
        l.transactionsExchangeRowA11y(
          fmt.money(x.sent.amount.abs()),
          fmt.money(x.received.amount.abs()),
          rateLine,
          time,
        ),
      ),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (divider)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 72),
                child: Divider(height: 1, thickness: 1, color: c.outline),
              ),
            ZListRow(
              title: title,
              subtitle: rateLine,
              leading: leading,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}
