// T-079: one transaction row and the day header of S-11. Spending is shown
// in ink, never red; the sign is part of the text (05-theme-2026 section 3).

import 'package:flutter/material.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/date_format.dart';
import '../../../../core/l10n/digits_mode.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/money_format.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_components.dart';
import '../../domain/transaction.dart';
import 'txn_list_providers.dart';

/// Locale-aware formatting shared by the rows and headers.
final class TxnFmt {
  const TxnFmt(this.lang, this.digits);
  final String lang;
  final DigitsMode digits;

  String money(Money m) =>
      MoneyFormat.format(m, languageCode: lang, digits: digits);
  String count(int n) => digits.render('$n');
}

/// The amount with the sign the direction implies (the stored amount is the
/// magnitude).
Money signedAmount(TransactionRecord t) {
  final a = t.amount.abs();
  return switch (t.direction) {
    TxnDirection.expense || TxnDirection.fee || TxnDirection.transferOut => -a,
    _ => a,
  };
}

/// Whether the row counts toward the day total.
bool countsInTotal(TransactionRecord t) =>
    !t.isInternal && t.status == TxnStatus.posted;

ZMoneyKind moneyKindOf(TransactionRecord t) {
  if (t.isInternal) return ZMoneyKind.neutral;
  return switch (t.direction) {
    TxnDirection.expense || TxnDirection.fee => ZMoneyKind.expense,
    TxnDirection.income || TxnDirection.refund => ZMoneyKind.income,
    _ => ZMoneyKind.neutral,
  };
}

Color _parseColor(String hex, Color fallback) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return v == null ? fallback : Color(0xFF000000 | v);
}

String sourceLabel(AppLocalizations l, TxnSource s) => switch (s) {
  TxnSource.sms => l.commonSourceSms,
  TxnSource.notification => l.commonSourceNotification,
  TxnSource.shortcut => l.commonSourceShortcut,
  TxnSource.applePay => l.commonSourceApplePay,
  TxnSource.ocr => l.commonSourceScan,
  TxnSource.pdf => l.commonSourceStatement,
  TxnSource.csv => l.commonSourceCsv,
  TxnSource.voice => l.commonSourceVoice,
  TxnSource.manual => l.commonSourceManual,
  TxnSource.share => l.commonSourceShared,
};

String categoryName(TxnCategory c, String lang) =>
    lang == 'ar' ? c.nameAr : c.nameEn;

String accountName(TxnAccount a, TxnFmt f) =>
    a.last4 == null ? a.label : '${a.label} •${f.digits.render(a.last4!)}';

class TxnRow extends StatelessWidget {
  const TxnRow({
    super.key,
    required this.txn,
    required this.lookups,
    required this.fmt,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final TransactionRecord txn;
  final TxnLookups lookups;
  final TxnFmt fmt;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cat = lookups.category(txn.categoryId);
    final acc = lookups.account(txn.accountId);
    final cardName = acc == null ? '' : accountName(acc, fmt);
    final merchant = txn.merchantNorm ?? txn.merchantRaw ?? txn.note ?? '';
    final title = txn.isInternal ? l.transactionsRowInternalTitle : merchant;
    final time = ZDateFormat.time(txn.occurredAt, fmt.lang, fmt.digits);
    final subtitle = txn.status == TxnStatus.declined
        ? l.transactionsRowDeclined
        : l.transactionsRowSubtitle(cardName, sourceLabel(l, txn.source), time);
    final amountText = fmt.money(signedAmount(txn));
    final catName = cat == null ? '' : categoryName(cat, fmt.lang);
    final Widget leading = selecting
        ? Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? c.primary : c.textMuted,
            size: 40,
          )
        : ZCategoryTile(
            color: _parseColor(cat?.color ?? '', c.primary),
            child: Text(cat?.icon ?? '•', style: ZType.title),
          );
    return Semantics(
      container: true,
      selected: selected,
      onLongPress: onLongPress,
      label: l.transactionsRowLabelA11y(
        amountText,
        cardName,
        catName,
        title,
        time,
      ),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: ZListRow(
          title: title,
          subtitle: subtitle,
          leading: leading,
          trailing: ZMoneyText(
            text: amountText,
            kind: moneyKindOf(txn),
            size: ZMoneySize.body,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Day header: the label and, per currency, the day's net (D-28: totals are
/// never mixed across currencies).
class TxnDayHeader extends StatelessWidget {
  const TxnDayHeader({
    super.key,
    required this.label,
    required this.totals,
    required this.fmt,
  });

  final String label;
  final List<Money> totals;
  final TxnFmt fmt;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.lg,
        ZSpacing.lg,
        ZSpacing.lg,
        ZSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: ZType.label.copyWith(color: c.textMuted),
              ),
            ),
          ),
          Wrap(
            spacing: ZSpacing.sm,
            children: [
              for (final m in totals)
                ZMoneyText(
                  text: fmt.money(m),
                  kind: m.isNegative ? ZMoneyKind.expense : ZMoneyKind.income,
                  size: ZMoneySize.caption,
                  semanticsLabel: l.transactionsListDayTotalA11y(fmt.money(m)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
