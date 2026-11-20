// T-195 (D-71): the expected salary on Home. One row from payday until the
// salary is received, recorded or skipped: title, due day, the planned
// amount (muted: it is not counted yet) and three choices. Never a
// transaction: nothing here changes a total until "It arrived".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_card.dart';
import '../../../core/ui/z_money_text.dart';
import '../../budget/application/budget_providers.dart';
import '../../home/presentation/home_format.dart';
import '../../transactions/presentation/edit/txn_edit_providers.dart';
import '../application/salary_providers.dart';
import '../application/salary_service.dart';

class ExpectedSalaryRow extends ConsumerStatefulWidget {
  const ExpectedSalaryRow({super.key});

  @override
  ConsumerState<ExpectedSalaryRow> createState() => _ExpectedSalaryRowState();
}

class _ExpectedSalaryRowState extends ConsumerState<ExpectedSalaryRow> {
  /// "Not yet" hides the row for this session only; nothing is written.
  CivilDate? _hiddenFor;
  bool _busy = false;

  Future<void> _arrived(ExpectedSalary e) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final format = HomeFormat.of(context, ref);
    try {
      final service = await ref.read(salaryServiceProvider.future);
      final today = ref.read(todayProvider);
      // The default cash account must exist before it can receive the salary.
      if (e.accountId == null) {
        await ref.read(defaultCashAccountIdProvider.future);
      }
      var result = await service.confirmReceived(e.payday, today: today);
      if (result is SalaryFoundExisting) {
        if (!mounted) return;
        final same = await askSalarySame(context, format.money(result.amount));
        if (same == null) return;
        if (same) {
          await service.linkExisting(e.payday, result.txnId);
        } else {
          result = await service.confirmReceived(
            e.payday,
            today: today,
            allowDuplicate: true,
          );
        }
      }
      ref.invalidate(expectedSalaryProvider);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.salaryRecorded)));
    } on SafeException {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.salaryErrorGeneric)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip(ExpectedSalary e) async {
    if (_busy) return;
    final service = await ref.read(salaryServiceProvider.future);
    await service.skip(e.payday);
    ref.invalidate(expectedSalaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final e = ref.watch(expectedSalaryProvider).value;
    if (e == null || _hiddenFor == e.payday) return const SizedBox.shrink();
    return ExpectedSalaryCard(
      expected: e,
      busy: _busy,
      onArrived: () => _arrived(e),
      onNotYet: () => setState(() => _hiddenFor = e.payday),
      onSkip: () => _skip(e),
    );
  }
}

/// "Is that your salary?": true = the same one (tie it), false = another
/// income (add it), null = cancelled.
Future<bool?> askSalarySame(BuildContext context, String amount) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => SalaryFoundDialog(
        amount: amount,
        onAnswer: (v) => Navigator.of(ctx).pop(v),
      ),
    );

class SalaryFoundDialog extends StatelessWidget {
  const SalaryFoundDialog({
    super.key,
    required this.amount,
    required this.onAnswer,
  });

  final String amount;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.salaryFoundTitle),
      content: Text(l.salaryFoundBody(amount)),
      actions: [
        TextButton(
          key: const ValueKey('salary-found-no'),
          onPressed: () => onAnswer(false),
          child: Text(l.salaryFoundNo),
        ),
        TextButton(
          key: const ValueKey('salary-found-yes'),
          onPressed: () => onAnswer(true),
          child: Text(l.salaryFoundYes),
        ),
      ],
    );
  }
}

/// The row itself, public so goldens render it without providers.
class ExpectedSalaryCard extends ConsumerWidget {
  const ExpectedSalaryCard({
    super.key,
    required this.expected,
    required this.onArrived,
    required this.onNotYet,
    required this.onSkip,
    this.busy = false,
  });

  final ExpectedSalary expected;
  final bool busy;
  final VoidCallback onArrived;
  final VoidCallback onNotYet;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final format = HomeFormat.of(context, ref);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
      child: ZCard(
        key: const ValueKey('home-expected-salary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: ZSpacing.minTarget,
                    child: Icon(
                      Icons.payments_outlined,
                      color: c.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.salaryExpectedTitle,
                        style: t.titleMedium?.copyWith(color: c.text),
                      ),
                      ZMoneyText(
                        text: format.number(expected.amount),
                        unit: format.currency(expected.amount),
                        kind: ZMoneyKind.neutral,
                        size: ZMoneySize.title,
                        semanticsLabel: format.money(expected.amount),
                      ),
                      Text(
                        l.salaryExpectedSub(format.count(expected.payday.day)),
                        style: t.bodyMedium?.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.md),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                ZButton(
                  key: const ValueKey('salary-arrived'),
                  label: l.salaryActionArrived,
                  size: ZButtonSize.small,
                  loading: busy,
                  onPressed: onArrived,
                ),
                ZButton(
                  key: const ValueKey('salary-not-yet'),
                  label: l.salaryActionNotYet,
                  size: ZButtonSize.small,
                  variant: ZButtonVariant.secondary,
                  onPressed: busy ? null : onNotYet,
                ),
                ZButton(
                  key: const ValueKey('salary-skip'),
                  label: l.salaryActionSkip,
                  size: ZButtonSize.small,
                  variant: ZButtonVariant.text,
                  onPressed: busy ? null : onSkip,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
