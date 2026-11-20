// T-188 (FR-CHT-04, D-68): the period control at the top of Charts: a chip
// with the resolved range, previous / next buttons (next stops at today) and
// the sheet with the presets and the custom range picker.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_card.dart';
import '../../../../core/ui/z_chip.dart';
import '../../../../core/ui/z_sheet.dart';
import '../../../budget/application/budget_providers.dart';
import '../../application/chart_period_providers.dart';
import '../../domain/chart_models.dart';
import '../../domain/chart_period_selection.dart';
import 'chart_period_text.dart';

const List<ChartPreset> chartPresetOrder = [
  ChartPreset.thisCycle,
  ChartPreset.lastCycle,
  ChartPreset.thisMonth,
  ChartPreset.lastMonth,
  ChartPreset.last3Months,
  ChartPreset.last6Months,
  ChartPreset.last12Months,
  ChartPreset.thisYear,
  ChartPreset.custom,
];

class ChartPeriodBar extends ConsumerWidget {
  const ChartPeriodBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final resolved = ref.watch(chartsResolvedPeriodProvider).value;
    final text = ChartPeriodText.of(context, ref);
    final notifier = ref.read(chartPeriodSelectionProvider.notifier);
    final c = ZColors.of(context);

    Widget step({
      required Key key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: ZSpacing.minTarget,
        minHeight: ZSpacing.minTarget,
      ),
      // chevron_left / chevron_right mirror themselves in RTL.
      icon: Icon(icon, color: onPressed == null ? c.textMuted : c.text),
      onPressed: onPressed,
    );

    final label = resolved == null ? '' : text.range(resolved.period);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: Row(
        children: [
          step(
            key: const Key('charts-period-prev'),
            icon: Icons.chevron_left,
            tooltip: l.insightsChartsPeriodPrev,
            onPressed: resolved != null && resolved.canStepBack
                ? () => notifier.select(resolved.selection.stepped(1))
                : null,
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
              child: Center(
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: resolved == null
                      ? null
                      : l.insightsChartsPeriodA11y(
                          text.presetName(resolved.selection.preset),
                          label,
                        ),
                  onTap: resolved == null
                      ? null
                      : () => showChartPeriodSheet(context, ref),
                  child: ZChip(
                    key: const Key('charts-period'),
                    label: label,
                    icon: Icons.keyboard_arrow_down_rounded,
                    onTap: resolved == null
                        ? null
                        : () => showChartPeriodSheet(context, ref),
                  ),
                ),
              ),
            ),
          ),
          step(
            key: const Key('charts-period-next'),
            icon: Icons.chevron_right,
            tooltip: l.insightsChartsPeriodNext,
            onPressed: resolved != null && resolved.canStepForward
                ? () => notifier.select(resolved.selection.stepped(-1))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Opens the period sheet and applies the choice.
Future<void> showChartPeriodSheet(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final resolved = ref.read(chartsResolvedPeriodProvider).value;
  if (resolved == null) return;
  final schedule = await ref.read(paydayScheduleProvider.future);
  if (!context.mounted) return;
  final text = ChartPeriodText.of(context, ref);
  final today = ref.read(todayProvider);
  final picked = await showZSheet<ChartPeriodSelection>(
    context: context,
    title: l.insightsChartsPeriodSheetTitle,
    builder: (ctx) => ChartPeriodSheetBody(
      current: resolved.selection,
      currentPeriod: resolved.period,
      today: today,
      schedule: schedule,
      text: text,
      onPick: (s) => Navigator.of(ctx).pop(s),
      onCustom: () async {
        final range = await showDateRangePicker(
          context: ctx,
          firstDate: DateTime(
            ChartPeriodLimits.earliest.year,
            ChartPeriodLimits.earliest.month,
            ChartPeriodLimits.earliest.day,
          ),
          lastDate: DateTime(today.year, today.month, today.day),
          initialDateRange: _initialRange(resolved.period, today),
          helpText: l.transactionsListRangeTitle,
          saveText: l.commonActionDone,
        );
        if (range == null || !ctx.mounted) return;
        Navigator.of(ctx).pop(customSelection(range, today));
      },
    ),
  );
  if (picked != null) {
    await ref.read(chartPeriodSelectionProvider.notifier).select(picked);
  }
}

/// What the picker opens on: the current period, cut at [today] (the picker
/// refuses a range that ends after its last date).
DateTimeRange _initialRange(ChartPeriod period, CivilDate today) {
  final to = period.to > today ? today : period.to;
  final from = period.from > to ? to : period.from;
  return DateTimeRange(
    start: DateTime(from.year, from.month, from.day),
    end: DateTime(to.year, to.month, to.day),
  );
}

/// The custom selection for a picked [range]: never after [today], and the
/// start moves up when the range is longer than the limit.
ChartPeriodSelection customSelection(DateTimeRange range, CivilDate today) {
  var to = CivilDate(range.end.year, range.end.month, range.end.day);
  if (to > today) to = today;
  var from = CivilDate(range.start.year, range.start.month, range.start.day);
  if (from > to) from = to;
  final longest = to.plusDays(-(ChartPeriodLimits.maxCustomDays - 1));
  if (from < longest) from = longest;
  return ChartPeriodSelection.custom(from, to);
}

/// The sheet content: the presets with their ranges and the custom entry.
/// Public so goldens can render it without a route.
class ChartPeriodSheetBody extends StatelessWidget {
  const ChartPeriodSheetBody({
    super.key,
    required this.current,
    required this.currentPeriod,
    required this.today,
    required this.schedule,
    required this.text,
    required this.onPick,
    required this.onCustom,
  });

  final ChartPeriodSelection current;
  final ChartPeriod currentPeriod;
  final CivilDate today;
  final PaydaySchedule schedule;
  final ChartPeriodText text;
  final ValueChanged<ChartPeriodSelection> onPick;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final preset in chartPresetOrder)
          Builder(
            builder: (_) {
              final on = current.preset == preset;
              final isCustom = preset == ChartPreset.custom;
              final subtitle = isCustom
                  ? (on ? text.range(currentPeriod) : null)
                  : text.range(
                      ChartPeriodSelection(preset).resolve(today, schedule),
                    );
              return ZListRow(
                key: Key('charts-period-${preset.name}'),
                title: text.presetName(preset),
                subtitle: subtitle,
                trailing: Icon(
                  on ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: on ? c.primary : c.textMuted,
                ),
                onTap: isCustom
                    ? onCustom
                    : () => onPick(ChartPeriodSelection(preset)),
              );
            },
          ),
      ],
    );
  }
}
