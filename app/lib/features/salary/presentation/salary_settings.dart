// T-195 (D-71): "My salary" in the payday settings: amount, currency, payday
// and where it lands. Saving writes the plan only (a setting); nothing is
// counted until the salary is received or confirmed. Remove deletes the
// plan.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_chip.dart';
import '../../../core/ui/z_haptics.dart';
import '../../../core/ui/z_sheet.dart';
import '../../home/presentation/home_format.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../transactions/presentation/edit/txn_form.dart'
    show amountInputFormatters, parseAmount;
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../application/salary_providers.dart';

class SalarySettingsRow extends ConsumerWidget {
  const SalarySettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final plan = ref.watch(salaryPlanProvider).value;
    final format = HomeFormat.of(context, ref);
    final c = ZColors.of(context);
    return SettingsRow(
      key: const ValueKey('settings-salary'),
      title: t.settingsSalaryTitle,
      subtitle: plan == null
          ? t.settingsSalaryUnset
          : t.settingsSalarySummary(
              format.money(plan.amount),
              format.count(plan.day),
            ),
      trailing: Icon(Icons.chevron_right, color: c.textMuted),
      onTap: () => showZSheet<void>(
        context: context,
        title: t.settingsSalaryTitle,
        builder: (_) => const SalarySheet(),
      ),
    );
  }
}

class SalarySheet extends ConsumerStatefulWidget {
  const SalarySheet({super.key});

  @override
  ConsumerState<SalarySheet> createState() => _SalarySheetState();
}

class _SalarySheetState extends ConsumerState<SalarySheet> {
  final _amount = TextEditingController();
  final _day = TextEditingController();
  Currency _currency = Currency.of('EGP');
  String? _accountId;
  bool _seeded = false;
  bool _invalid = false;

  @override
  void dispose() {
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  void _seed() {
    if (_seeded) return;
    _seeded = true;
    final plan = ref.read(salaryPlanProvider).value;
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.read(digitsModeProvider(lang));
    if (plan != null) {
      _currency = plan.currency;
      _accountId = plan.accountId;
      // ignore: no_unmasked_amount - edit-field prefill: the user is editing this amount (T-187 Lead decision).
      _amount.text = digits.render(plan.amount.toCanonicalString());
      _day.text = digits.render('${plan.day}');
    } else {
      _currency = ref.read(primaryCurrencyProvider).value ?? Currency.of('EGP');
      final payday = ref.read(paydayDayProvider).value;
      _day.text = digits.render('${payday ?? 25}');
    }
  }

  Future<void> _save() async {
    final money = parseAmount(_amount.text, _currency).money;
    final day = int.tryParse(normalizeDigits(_day.text.trim()));
    final plan = money == null || day == null
        ? null
        : SalaryPlan.tryCreate(amount: money, day: day, accountId: _accountId);
    if (plan == null) {
      setState(() => _invalid = true);
      return;
    }
    final service = await ref.read(salaryServiceProvider.future);
    await service.setPlan(plan);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final service = await ref.read(salaryServiceProvider.future);
    await service.setPlan(null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    _seed();
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final accounts = ref.watch(txnLookupsProvider).value?.accounts ?? const [];
    final hasPlan = ref.watch(salaryPlanProvider).value != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('salary-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: amountInputFormatters,
          decoration: InputDecoration(
            labelText: t.settingsSalaryAmount,
            suffixText: _currency.code,
          ),
        ),
        const SizedBox(height: ZSpacing.sm),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            for (final code in Currency.featuredCodes)
              ZChip(
                label: code,
                selected: _currency.code == code,
                onTap: () => setState(() => _currency = Currency.of(code)),
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.md),
        TextField(
          key: const ValueKey('salary-day'),
          controller: _day,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t.settingsSalaryDay),
        ),
        const SizedBox(height: ZSpacing.md),
        Text(
          t.settingsSalaryAccount,
          style: ZType.label.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.xs),
        Wrap(
          spacing: ZSpacing.sm,
          runSpacing: ZSpacing.sm,
          children: [
            ZChip(
              label: t.settingsSalaryAccountDefault,
              selected: _accountId == null,
              onTap: () => setState(() => _accountId = null),
            ),
            for (final a in accounts)
              ZChip(
                label: a.last4 == null ? a.label : '${a.label} ${a.last4}',
                selected: _accountId == a.id,
                onTap: () => setState(() => _accountId = a.id),
              ),
          ],
        ),
        if (_invalid)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              t.settingsSalaryInvalid,
              key: const ValueKey('salary-invalid'),
              style: ZType.bodySmall.copyWith(color: c.warningText),
            ),
          ),
        const SizedBox(height: ZSpacing.lg),
        ZButton(
          key: const ValueKey('salary-save'),
          label: t.commonActionSave,
          haptic: ZHaptic.medium,
          expand: true,
          onPressed: _save,
        ),
        if (hasPlan)
          ZButton(
            key: const ValueKey('salary-remove'),
            label: t.settingsSalaryRemove,
            variant: ZButtonVariant.text,
            expand: true,
            onPressed: _remove,
          ),
      ],
    );
  }
}
