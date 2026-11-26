// T-281 (D-86, FU-365): S-12 for an exchange. Both legs as one unit: what
// was given and got (each in its own currency, never converted), both
// accounts, the bank's rate, the date and the source. Read-only; Delete
// lives in the screen's menu and removes both legs together.

import 'package:flutter/material.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../../accounts/presentation/account_type.dart';
import '../../domain/exchange.dart';
import '../list/txn_exchange_row.dart';
import '../list/txn_list_providers.dart';
import '../list/txn_row.dart';

class ExchangeDetailBody extends StatelessWidget {
  const ExchangeDetailBody({
    super.key,
    required this.exchange,
    required this.lookups,
    required this.fmt,
    required this.onUnlink,
    this.referenceNo,
    this.footer,
  });

  final TxnExchange exchange;
  final TxnLookups lookups;
  final TxnFmt fmt;
  final VoidCallback onUnlink;
  final String? referenceNo;

  /// "How Zaghlol read this" (the source message), built by the screen.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final x = exchange;
    String account(String id) {
      final a = lookups.account(id);
      return a == null
          ? kNoValueDash
          : accountNameWithType(l, accountName(a, fmt), a.kind);
    }

    final rate = x.rate;
    final when = ZDateFormat.date(x.sent.occurredAt, fmt.lang, fmt.digits);
    final time = ZDateFormat.time(x.sent.occurredAt, fmt.lang, fmt.digits);
    final fields = <(String, String)>[
      (l.transactionsExchangeFieldSent, fmt.money(x.sent.amount.abs())),
      (l.transactionsExchangeFieldFrom, account(x.sent.accountId)),
      (l.transactionsExchangeFieldReceived, fmt.money(x.received.amount.abs())),
      (l.transactionsExchangeFieldTo, account(x.received.accountId)),
      if (rate != null && !fmt.hidden)
        (
          l.transactionsExchangeFieldRate,
          // One left-to-right run in both locales: "1 USD = 49.50 EGP".
          '\u2066${l.transactionsExchangeRateValue(fmt.digits.render('1'), rate.rateBase.code, exchangeRateText(rate.rateE9, fmt), rate.rateQuote.code)}\u2069',
        ),
      (l.transactionsDetailFieldDate, l.commonDateDateTime(when, time)),
      (l.transactionsDetailFieldSource, sourceLabel(l, x.sent.source)),
      if (referenceNo != null)
        (l.transactionsDetailFieldReference, fmt.digits.render(referenceNo!)),
    ];
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.lg,
        0,
        ZSpacing.lg,
        ZSpacing.xl,
      ),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
          child: ZBanner(
            message: l.transactionsExchangeBanner,
            actionLabel: l.commonActionUnlink,
            onAction: onUnlink,
          ),
        ),
        Column(
          children: [
            ZCategoryTile(
              size: 64,
              color: c.primary,
              child: Icon(Icons.currency_exchange, color: c.primary, size: 30),
            ),
            const SizedBox(height: ZSpacing.lg),
            Text(
              exchangeTitle(l, x, fmt),
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              exchangeRateLine(l, x, fmt),
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: ZSpacing.xl),
        ZCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            children: [
              for (var k = 0; k < fields.length; k++)
                _Field(
                  label: fields[k].$1,
                  value: fields[k].$2,
                  divider: k > 0,
                ),
            ],
          ),
        ),
        if (footer != null) ...[const SizedBox(height: ZSpacing.lg), footer!],
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.divider,
  });

  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (divider)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: ZSpacing.lg),
              child: Divider(height: 1, thickness: 1, color: c.outline),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.lg,
                vertical: ZSpacing.md,
              ),
              child: Row(
                children: [
                  Text(label, style: ZType.body.copyWith(color: c.textMuted)),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: ZType.titleSmall.copyWith(
                        color: c.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
