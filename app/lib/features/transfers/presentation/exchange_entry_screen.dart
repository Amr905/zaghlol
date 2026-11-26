// T-272 (D-86, WP-4): "I exchanged money" — the manual exchange entry. The
// PO's main path: a bank-counter exchange sends no SMS. Two amounts, each in
// its own currency, typed as text and parsed exactly into minor units; the
// rate shown is only the ratio of the two (never used to convert anything).
// Saving goes through `TransferPairingUseCase.recordExchange` (one database
// transaction: two legs and the pair). Nothing here logs.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_haptics.dart';
import '../../budget/application/budget_providers.dart';
import '../../ingestion/data/review_repository.dart'
    show reviewOpenCountProvider;
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/presentation/edit/txn_edit_providers.dart';
import '../../transactions/presentation/edit/txn_form.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';

/// What the screen starts with (from an "unexplained balance rise"
/// suggestion: the received side is known, the user types what he gave).
final class ExchangePrefill {
  const ExchangePrefill({
    this.toAccountId,
    this.received,
    this.date,
    this.reviewItemId,
  });

  final String? toAccountId;
  final Money? received;
  final CivilDate? date;

  /// The suggestion this entry answers; resolved when the exchange is saved.
  final String? reviewItemId;
}

/// Opens the exchange entry over the root navigator. Completes with true
/// when an exchange was saved.
Future<bool?> showExchangeEntry(
  BuildContext context, {
  ExchangePrefill prefill = const ExchangePrefill(),
}) => Navigator.of(context, rootNavigator: true).push<bool>(
  MaterialPageRoute<bool>(
    fullscreenDialog: true,
    builder: (_) => ExchangeEntryScreen(prefill: prefill),
  ),
);

/// `rateE9` (1e-9 units) as a decimal with 2 to 4 fraction digits, rounded
/// half up at the 4th. Integer math only; ASCII digits (the caller renders
/// them per locale).
String formatRateE9(int rateE9) {
  if (rateE9 <= 0) return '0';
  final scaled = (rateE9 + 50000) ~/ 100000; // 4 decimals
  final whole = scaled ~/ 10000;
  var frac = (scaled % 10000).toString().padLeft(4, '0');
  while (frac.length > 2 && frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  return '$whole.$frac';
}

/// Currencies offered without a full picker (the full ISO picker is T-273).
const List<String> _offered = [
  'EGP',
  'USD',
  'EUR',
  'SAR',
  'AED',
  'KWD',
  'QAR',
  'GBP',
];

class ExchangeEntryScreen extends ConsumerStatefulWidget {
  const ExchangeEntryScreen({
    super.key,
    this.prefill = const ExchangePrefill(),
  });

  final ExchangePrefill prefill;

  @override
  ConsumerState<ExchangeEntryScreen> createState() =>
      _ExchangeEntryScreenState();
}

class _ExchangeEntryScreenState extends ConsumerState<ExchangeEntryScreen> {
  final _sent = TextEditingController();
  late final TextEditingController _received;
  String? _fromAccount;
  String? _toAccount;
  Currency? _fromCurrency;
  Currency? _toCurrency;
  CivilDate? _date;
  bool _submitted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _toAccount = p.toAccountId;
    _toCurrency = p.received?.currency;
    _received = TextEditingController(
      text: p.received == null ? '' : _plain(p.received!),
    );
    _date = p.date;
  }

  /// Canonical decimal text of [m] (`29700.00`), never via a double.
  static String _plain(Money m) {
    final e = m.currency.exponent;
    final s = m.minor.abs().toString().padLeft(e + 1, '0');
    return e == 0
        ? s
        : '${s.substring(0, s.length - e)}.${s.substring(s.length - e)}';
  }

  @override
  void dispose() {
    _sent.dispose();
    _received.dispose();
    super.dispose();
  }

  CivilDate _today() => ref.read(todayProvider);

  Money? _parse(TextEditingController c, Currency? cur) =>
      cur == null ? null : parseAmount(c.text, cur).money;

  bool get _sameCurrency =>
      _fromCurrency != null && _fromCurrency == _toCurrency;

  bool get _valid =>
      _fromAccount != null &&
      _toAccount != null &&
      !_sameCurrency &&
      _parse(_sent, _fromCurrency) != null &&
      _parse(_received, _toCurrency) != null;

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_valid || _saving) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final uc = await ref.read(transferPairingUseCaseProvider.future);
      final date = _date ?? _today();
      final nowUtc = ref.read(clockProvider)().toUtc();
      final zone = ref.read(localZoneProvider);
      final offset = zone.offsetAtInstant(nowUtc.millisecondsSinceEpoch);
      final at = date.epochDay == _today().epochDay
          ? nowUtc
          : DateTime.fromMillisecondsSinceEpoch(
              date.epochDay * 86400000 + 12 * 3600000 - offset * 60000,
              isUtc: true,
            );
      await uc.recordExchange(
        fromAccountId: _fromAccount!,
        sent: _parse(_sent, _fromCurrency)!,
        toAccountId: _toAccount!,
        received: _parse(_received, _toCurrency)!,
        occurredAt: at,
        tzOffsetMin: offset,
        resolveItemId: widget.prefill.reviewItemId,
      );
      ref
        ..invalidate(txnListProvider)
        ..invalidate(reviewOpenCountProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.exchangeEntrySaved)));
      navigator.pop(true);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l.exchangeEntryFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final lk = ref.watch(txnLookupsProvider).value;
    final cash = ref.watch(defaultCashAccountIdProvider).value;
    final primary = ref.watch(primaryCurrencyProvider).value;
    final accounts = lk?.accounts ?? const <TxnAccount>[];
    Currency? currencyOf(String? id) =>
        id == null ? null : Currency.tryOf(lk?.account(id)?.currencyCode ?? '');
    if (lk != null) {
      _fromAccount ??= accounts
          .where((a) => a.currencyCode != primary?.code)
          .map((a) => a.id)
          .firstOrNull;
      _fromAccount ??= cash ?? accounts.firstOrNull?.id;
      _toAccount ??= cash ?? accounts.firstOrNull?.id;
      _fromCurrency ??= currencyOf(_fromAccount);
      _toCurrency ??= primary ?? currencyOf(_toAccount);
    }
    final codes = <String>{
      ?_fromCurrency?.code,
      ?_toCurrency?.code,
      ?primary?.code,
      for (final a in accounts) a.currencyCode,
      ..._offered,
    }.where((code) => Currency.tryOf(code) != null).toList();

    final sent = _parse(_sent, _fromCurrency);
    final received = _parse(_received, _toCurrency);
    final rate = sent == null || received == null
        ? null
        : impliedRateE9(sent, received);
    final date = _date ?? _today();

    String label(TxnAccount a) =>
        a.last4 == null ? a.label : '${a.label} •${digits.render(a.last4!)}';

    Widget side({
      required String title,
      required String? account,
      required ValueChanged<String?> onAccount,
      required Currency? currency,
      required ValueChanged<Currency> onCurrency,
      required TextEditingController amount,
      required Key key,
    }) => Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: ZType.title.copyWith(color: c.text)),
        const SizedBox(height: ZSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: accounts.any((a) => a.id == account) ? account : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.exchangeEntryAccount),
          items: [
            for (final a in accounts)
              DropdownMenuItem(value: a.id, child: Text(label(a))),
          ],
          onChanged: onAccount,
        ),
        const SizedBox(height: ZSpacing.sm),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: currency?.code,
                decoration: InputDecoration(labelText: l.exchangeEntryCurrency),
                items: [
                  for (final code in codes)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: (code) {
                  final cur = code == null ? null : Currency.tryOf(code);
                  if (cur != null) onCurrency(cur);
                },
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            Expanded(
              flex: 3,
              child: TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: amountInputFormatters,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  errorText:
                      _submitted &&
                          (currency == null ||
                              parseAmount(amount.text, currency).money == null)
                      ? l.commonValidationAmountRequired
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.exchangeEntryTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            Text(
              l.exchangeEntryIntro,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.lg),
            side(
              key: const ValueKey('exchange-sent'),
              title: l.exchangeEntrySent,
              account: _fromAccount,
              onAccount: (id) => setState(() {
                _fromAccount = id;
                _fromCurrency = currencyOf(id) ?? _fromCurrency;
              }),
              currency: _fromCurrency,
              onCurrency: (cur) => setState(() => _fromCurrency = cur),
              amount: _sent,
            ),
            const SizedBox(height: ZSpacing.lg),
            side(
              key: const ValueKey('exchange-received'),
              title: l.exchangeEntryReceived,
              account: _toAccount,
              onAccount: (id) => setState(() {
                _toAccount = id;
                _toCurrency = currencyOf(id) ?? _toCurrency;
              }),
              currency: _toCurrency,
              onCurrency: (cur) => setState(() => _toCurrency = cur),
              amount: _received,
            ),
            if (_sameCurrency) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                l.exchangeEntrySameCurrency,
                style: ZType.bodySmall.copyWith(color: c.dangerText),
              ),
            ],
            const SizedBox(height: ZSpacing.md),
            ListTile(
              contentPadding: EdgeInsetsDirectional.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(l.exchangeEntryDate),
              subtitle: Text(
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(DateTime(date.year, date.month, date.day)),
              ),
              onTap: () async {
                final t = _today();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(date.year, date.month, date.day),
                  firstDate: DateTime(t.year - 2),
                  lastDate: DateTime(t.year, t.month, t.day),
                );
                if (picked != null) {
                  setState(
                    () => _date = CivilDate(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  );
                }
              },
            ),
            if (rate != null) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(
                key: const ValueKey('exchange-rate'),
                l.exchangeEntryRate(
                  MoneyFormat.currencyLabel(_fromCurrency!, languageCode: lang),
                  digits.render(formatRateE9(rate)),
                  MoneyFormat.currencyLabel(_toCurrency!, languageCode: lang),
                ),
                style: ZType.body.copyWith(color: c.text),
              ),
            ],
            const SizedBox(height: ZSpacing.xl),
            ZButton(
              key: const ValueKey('exchange-save'),
              label: l.exchangeEntrySave,
              expand: true,
              loading: _saving,
              haptic: ZHaptic.medium,
              onPressed: () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
