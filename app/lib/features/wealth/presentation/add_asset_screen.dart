// T-121: Add asset (S-44). Gold only: a Free user opening it sees the locked
// state and the paywall hook fires (S-68). Typed amounts are normalized and
// parsed exactly (`asset_form.dart`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/daos/assets_dao.dart';
import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../gold/application/gating.dart';
import '../data/net_worth_providers.dart';
import '../data/prices_providers.dart';
import 'asset_form.dart';
import 'assets_providers.dart';

class AddAssetScreen extends ConsumerStatefulWidget {
  const AddAssetScreen({super.key, this.onSaved});

  /// Called after a successful save; defaults to popping the route.
  final VoidCallback? onSaved;

  @override
  ConsumerState<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends ConsumerState<AddAssetScreen> {
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _paid = TextEditingController();
  AssetFormType? _type;
  GoldKind _kind = GoldKind.k21;
  Currency _currency = Currency.of('EGP');
  Currency _paidCurrency = Currency.of('EGP');
  String _payout = CertificatePayout.monthly;
  CivilDate? _boughtOn;
  CivilDate? _maturity;
  Map<AssetField, AssetFieldError> _errors = const {};
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(entitlementStateProvider).isGold) {
        ref.read(paywallTriggerProvider)(GoldCapability.investmentAssets);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _quantity, _amount, _rate, _paid]) {
      c.dispose();
    }
    super.dispose();
  }

  CivilDate get _today {
    final n = ref.read(pricesClockProvider)().toLocal();
    return CivilDate(n.year, n.month, n.day);
  }

  Future<void> _save() async {
    final result = validateAssetForm(
      AssetFormInput(
        type: _type,
        goldKind: _kind,
        name: _name.text,
        quantity: _quantity.text,
        amount: _amount.text,
        currency: _currency,
        rate: _rate.text,
        payout: _payout,
        boughtOn: _boughtOn,
        maturity: _maturity,
        pricePaid: _paid.text,
        pricePaidCurrency: _paidCurrency,
      ),
      today: _today,
    );
    setState(() {
      _errors = result.errors;
      _failed = false;
    });
    if (!result.isValid) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(netWorthRepositoryProvider.future);
      await repo.addAsset(result.draft!);
      ref.invalidate(assetsOverviewProvider);
      ref.invalidate(pricesScreenProvider);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).wealthAssetSaved)),
      );
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        Navigator.of(context).maybePop();
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  String? _err(AppLocalizations l10n, AssetField field) {
    final e = _errors[field];
    if (e == null) return null;
    final c = field == AssetField.pricePaid ? _paidCurrency : _currency;
    return switch (e) {
      AssetFieldError.type => l10n.wealthAssetErrorType,
      AssetFieldError.name => l10n.commonValidationNameRequired,
      AssetFieldError.grams => l10n.wealthAssetErrorGrams,
      AssetFieldError.gramsDecimals => l10n.wealthAssetErrorGramsDecimals,
      AssetFieldError.count => l10n.commonValidationAmountRequired,
      AssetFieldError.amount => l10n.commonValidationAmountRequired,
      AssetFieldError.amountDecimals => l10n.commonValidationAmountDecimals(
        c.exponent,
        c.code,
        '${c.exponent}',
      ),
      AssetFieldError.currency => l10n.commonValidationCurrencyRequired,
      AssetFieldError.rate => l10n.wealthAssetErrorRate('$maxRatePercent'),
      AssetFieldError.maturity => l10n.commonValidationChoiceRequired,
      AssetFieldError.maturityOrder => l10n.wealthAssetErrorMaturity,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        leading: IconButton(
          tooltip: l10n.commonActionClose,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Semantics(
          header: true,
          child: Text(
            l10n.wealthAssetTitleAdd,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
        ),
        actions: [
          if (gold)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: ZSpacing.md),
              child: Center(
                child: ZButton(
                  label: l10n.commonActionSave,
                  onPressed: _saving ? null : _save,
                  variant: ZButtonVariant.text,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: gold ? _form(context, l10n) : _locked(context, l10n),
      ),
    );
  }

  Widget _locked(BuildContext context, AppLocalizations l10n) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      child: ZCard(
        key: const Key('asset-locked'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, color: c.accentDark),
            const SizedBox(height: ZSpacing.md),
            Text(
              l10n.accountsOverviewAssetsLocked,
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.md),
            ZButton(
              label: l10n.commonGoldUnlock,
              variant: ZButtonVariant.gold,
              onPressed: () => ref.read(paywallTriggerProvider)(
                GoldCapability.investmentAssets,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(AppLocalizations l10n, AssetFormType t) => switch (t) {
    AssetFormType.gold => l10n.commonAssetTypeGold,
    AssetFormType.certificate => l10n.commonAssetTypeCertificate,
    AssetFormType.cash => l10n.commonAssetTypeForeignCash,
    AssetFormType.stocks => l10n.commonAssetTypeStocks,
    AssetFormType.property => l10n.commonAssetTypeProperty,
    AssetFormType.car => l10n.commonAssetTypeCar,
  };

  String _payoutLabel(AppLocalizations l10n, String p) => switch (p) {
    CertificatePayout.monthly => l10n.commonCadenceMonthly,
    CertificatePayout.quarterly => l10n.commonCadenceQuarterly,
    CertificatePayout.semiAnnual => l10n.commonCadenceSemiannual,
    CertificatePayout.annual => l10n.commonCadenceYearly,
    _ => l10n.wealthAssetCertMaturity,
  };

  Widget _form(BuildContext context, AppLocalizations l10n) {
    final c = ZColors.of(context);
    final t = _type;
    Widget gap() => const SizedBox(height: ZSpacing.md);
    final typeError = _err(l10n, AssetField.type);
    return ListView(
      padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
      children: [
        if (_failed) ...[
          ZBanner(
            message: l10n.commonErrorSaveFailed,
            tone: ZBannerTone.warning,
          ),
          gap(),
        ],
        Semantics(
          header: true,
          child: Text(
            l10n.wealthAssetType,
            style: ZType.label.copyWith(color: c.text),
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            for (final v in AssetFormType.values)
              ZChip(
                label: _typeLabel(l10n, v),
                selected: t == v,
                onTap: () => setState(() {
                  _type = v;
                  _errors = const {};
                }),
              ),
          ],
        ),
        if (typeError != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
            child: Text(
              typeError,
              style: ZType.caption.copyWith(color: c.dangerText),
            ),
          ),
        gap(),
        if (t == AssetFormType.gold) ...[
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              for (final k in GoldKind.values)
                ZChip(
                  label: k == GoldKind.coin
                      ? l10n.commonKaratCoin
                      : l10n.commonKaratLabel('${k.karat}'),
                  selected: _kind == k,
                  onTap: () => setState(() => _kind = k),
                ),
            ],
          ),
          gap(),
          _field(
            controller: _quantity,
            label: _kind == GoldKind.coin
                ? l10n.wealthAssetCoinCount
                : l10n.wealthAssetGoldGrams,
            helper: _kind == GoldKind.coin
                ? null
                : l10n.wealthAssetGoldGramsHint,
            error: _err(l10n, AssetField.quantity),
          ),
          gap(),
          _dateField(
            l10n,
            '${l10n.wealthAssetBoughtOn} (${l10n.wealthAssetOptional})',
            _boughtOn,
            (d) => setState(() => _boughtOn = d),
            last: _today,
          ),
          gap(),
          _moneyRow(
            l10n,
            label: '${l10n.wealthAssetPricePaid} (${l10n.wealthAssetOptional})',
            controller: _paid,
            currency: _paidCurrency,
            onCurrency: (v) => setState(() => _paidCurrency = v),
            error: _err(l10n, AssetField.pricePaid),
          ),
        ],
        if (t == AssetFormType.certificate) ...[
          _field(
            controller: _name,
            label: l10n.wealthAssetCertBank,
            error: _err(l10n, AssetField.name),
            text: true,
          ),
          gap(),
          _moneyRow(
            l10n,
            label: l10n.wealthAssetCertPrincipal,
            controller: _amount,
            currency: _currency,
            onCurrency: (v) => setState(() => _currency = v),
            error: _err(l10n, AssetField.amount),
          ),
          gap(),
          _field(
            controller: _rate,
            label: '${l10n.wealthAssetCertRate} (%)',
            error: _err(l10n, AssetField.rate),
          ),
          gap(),
          DropdownButtonFormField<String>(
            initialValue: _payout,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.wealthAssetCertPayout),
            items: [
              for (final p in const [
                CertificatePayout.monthly,
                CertificatePayout.quarterly,
                CertificatePayout.semiAnnual,
                CertificatePayout.annual,
                CertificatePayout.atMaturity,
              ])
                DropdownMenuItem(value: p, child: Text(_payoutLabel(l10n, p))),
            ],
            onChanged: (v) => setState(() => _payout = v ?? _payout),
          ),
          gap(),
          _dateField(
            l10n,
            '${l10n.wealthAssetBoughtOn} (${l10n.wealthAssetOptional})',
            _boughtOn,
            (d) => setState(() => _boughtOn = d),
            last: _today,
          ),
          gap(),
          _dateField(
            l10n,
            l10n.wealthAssetCertMaturity,
            _maturity,
            (d) => setState(() => _maturity = d),
            error: _err(l10n, AssetField.maturity),
          ),
        ],
        if (t == AssetFormType.cash)
          _moneyRow(
            l10n,
            label: l10n.wealthAssetCashAmount,
            controller: _amount,
            currency: _currency,
            onCurrency: (v) => setState(() => _currency = v),
            error: _err(l10n, AssetField.amount),
            currencyLabel: l10n.wealthAssetCashCurrency,
          ),
        if (t == AssetFormType.stocks ||
            t == AssetFormType.property ||
            t == AssetFormType.car) ...[
          _field(
            controller: _name,
            label: l10n.wealthAssetName,
            error: _err(l10n, AssetField.name),
            text: true,
          ),
          gap(),
          _moneyRow(
            l10n,
            label: l10n.wealthAssetValue,
            controller: _amount,
            currency: _currency,
            onCurrency: (v) => setState(() => _currency = v),
            error: _err(l10n, AssetField.amount),
            currencyLabel: t == AssetFormType.stocks
                ? l10n.wealthAssetStocksCurrency
                : l10n.wealthAssetCashCurrency,
            helper: l10n.wealthAssetValueHint,
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? helper,
    String? error,
    bool text = false,
  }) => TextField(
    controller: controller,
    keyboardType: text
        ? TextInputType.text
        : const TextInputType.numberWithOptions(decimal: true),
    textDirection: text ? null : TextDirection.ltr,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      errorText: error,
      errorMaxLines: 2,
    ),
  );

  Widget _moneyRow(
    AppLocalizations l10n, {
    required String label,
    required TextEditingController controller,
    required Currency currency,
    required ValueChanged<Currency> onCurrency,
    String? error,
    String? currencyLabel,
    String? helper,
  }) {
    final all = [
      for (final code in Currency.featuredCodes) Currency.of(code),
      ...(Currency.active
          .where((x) => !Currency.featuredCodes.contains(x.code))
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<Currency>(
          initialValue: currency,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: currencyLabel ?? l10n.wealthAssetCashCurrency,
          ),
          items: [
            for (final cur in all)
              DropdownMenuItem(value: cur, child: Text(cur.code)),
          ],
          onChanged: (v) {
            if (v != null) onCurrency(v);
          },
        ),
        const SizedBox(height: ZSpacing.md),
        _field(
          controller: controller,
          label: label,
          error: error,
          helper: helper,
        ),
      ],
    );
  }

  Widget _dateField(
    AppLocalizations l10n,
    String label,
    CivilDate? value,
    ValueChanged<CivilDate> onPicked, {
    CivilDate? last,
    String? error,
  }) {
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final shown = value == null
        ? ''
        : ZDateFormat.date(
            DateTime(value.year, value.month, value.day),
            lang,
            digits,
          );
    return Semantics(
      button: true,
      label: '$label $shown',
      excludeSemantics: true,
      child: InkWell(
        onTap: () async {
          final today = _today;
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime(
              (value ?? today).year,
              (value ?? today).month,
              (value ?? today).day,
            ),
            firstDate: DateTime(1990),
            lastDate: last == null
                ? DateTime(today.year + 50)
                : DateTime(last.year, last.month, last.day),
          );
          if (picked != null) {
            onPicked(CivilDate(picked.year, picked.month, picked.day));
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            suffixIcon: Icon(Icons.calendar_today_rounded, color: c.textMuted),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ZSpacing.minTarget - 24,
            ),
            child: Text(shown, style: ZType.body.copyWith(color: c.text)),
          ),
        ),
      ),
    );
  }
}
