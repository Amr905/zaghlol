// T-280 (D-86): the Home "≈ money in, all currencies" line, its explanation
// sheet and Captain Zaghlol's one-off "first foreign currency" notice.
// Always shows "≈" and reads "approximate" to screen readers. Hidden when the
// setting is off or a rate is missing (never a partial total). Plugged into
// Home's approx slot by the Lead. Nothing here logs.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/digits_mode.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_mascot_bubble.dart';
import '../../../core/ui/z_sheet.dart';
import '../../transfers/presentation/exchange_entry_screen.dart'
    show formatRateE9;
import '../../wealth/domain/income_approx.dart';
import '../application/home_approx_providers.dart';
import 'home_format.dart';

class HomeApproxLine extends ConsumerWidget {
  const HomeApproxLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drives the once-only switch-on (Q2); errors are not shown here.
    ref.watch(homeApproxAutoOnProvider);
    final enabled = ref.watch(approxViewEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();
    final notice = ref.watch(approxFirstForeignNoticeProvider).value ?? false;
    final line = ref.watch(homeApproxProvider).value;
    if (!notice && line == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice) const _FirstForeignNotice(),
        if (line != null) HomeApproxLineView(line: line),
      ],
    );
  }
}

class _FirstForeignNotice extends ConsumerWidget {
  const _FirstForeignNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    Future<void> clear({required bool turnOff}) async {
      final repo = await ref.read(settingsRepositoryProvider.future);
      if (turnOff) await repo.set(Settings.approxViewEnabled, false);
      await repo.set(Settings.approxFirstForeignNotice, false);
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ZMascotBubble(message: l.homeMascotFirstForeign),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => clear(turnOff: true),
                child: Text(l.homeApproxNoticeOff),
              ),
              TextButton(
                onPressed: () => clear(turnOff: false),
                child: Text(l.homeApproxNoticeOk),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The line itself, public so tests render it without providers.
class HomeApproxLineView extends ConsumerWidget {
  const HomeApproxLineView({super.key, required this.line});

  final IncomeApproxLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final f = HomeFormat.of(context, ref);
    final amount = f.money(line.total);
    final note = _rateNote(l, f, line);
    return Semantics(
      button: true,
      label: l.homeApproxLineA11y(amount),
      excludeSemantics: true,
      onTap: () => _showSheet(context, ref),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.md),
        onTap: () => _showSheet(context, ref),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.md,
            vertical: ZSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.homeApproxLine(amount),
                style: ZType.label.copyWith(color: c.text),
              ),
              Text(note, style: ZType.caption.copyWith(color: c.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showZSheet<void>(
      context: context,
      title: AppLocalizations.of(context).homeApproxSheetTitle,
      builder: (_) => HomeApproxSheetContent(line: line),
    );
  }
}

String _rateNote(AppLocalizations l, HomeFormat f, IncomeApproxLine line) {
  if (line.stale) return l.homeApproxStale;
  final at = line.rateAsOfMs;
  if (at == null) return l.homeApproxRateNoteBank;
  final date = f.dateOf(DateTime.fromMillisecondsSinceEpoch(at, isUtc: true));
  return line.usesBankRate
      ? l.homeApproxRateNoteBoth(date)
      : l.homeApproxRateNoteDaily(date);
}

/// The sheet body: each currency, its amount, the rate used and where it
/// came from.
class HomeApproxSheetContent extends ConsumerWidget {
  const HomeApproxSheetContent({super.key, required this.line});

  final IncomeApproxLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final f = HomeFormat.of(context, ref);
    Widget row(String title, String? trailing, List<String> notes) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.xl,
        vertical: ZSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ZType.body.copyWith(color: c.text)),
                for (final n in notes)
                  Text(n, style: ZType.caption.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          if (trailing != null)
            Text(trailing, style: ZType.label.copyWith(color: c.text)),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: ZSpacing.xl,
          ),
          child: Text(
            l.homeApproxSheetBody,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
        ),
        row(l.homeApproxSheetOwn, f.money(line.targetMoneyIn), const []),
        for (final r in line.rows)
          row(
            f.currency(r.held),
            r.heldInTarget == null ? null : '≈ ${f.money(r.heldInTarget!)}',
            [
              if (r.held.isPositive) l.homeApproxSheetHeld(f.money(r.held)),
              if (r.heldInTarget != null && r.dailyRatePerUnit != null)
                l.homeApproxSheetDailyRate(
                  f.dateOf(
                    DateTime.fromMillisecondsSinceEpoch(
                      r.dailyRateAsOfMs!,
                      isUtc: true,
                    ),
                  ),
                  f.currency(r.held),
                  f.money(r.dailyRatePerUnit!),
                ),
              if (r.stale) l.homeApproxStale,
              if (r.exchanged.isPositive)
                r.bankRateE9 == null
                    ? l.homeApproxSheetExchanged(f.money(r.exchanged))
                    : l.homeApproxSheetExchangedBank(
                        f.money(r.exchanged),
                        _rateText(f, r.bankRateE9!),
                      ),
            ],
          ),
        const SizedBox(height: ZSpacing.lg),
      ],
    );
  }
}

/// The bank rate in the user's digits and decimal mark.
String _rateText(HomeFormat f, int rateE9) {
  final text = f.digits.render(formatRateE9(rateE9));
  return f.digits == DigitsMode.arabicIndic ? text.replaceAll('.', '٫') : text;
}
