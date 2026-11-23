// T-189: the "not enough data yet" state of a chart, with a Zaghlol line that
// says what is missing ("I need two more months for this chart to show").
// The line comes from the chart's minimum data rule (`ChartNotEnoughData`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../domain/chart_models.dart';
import '../../../../core/theme/z_tokens.dart';
import 'chart_card.dart';
import 'chart_format.dart';

/// The message for [r]: what is missing, or [fallback] when the chart has no
/// data at all (the caller's own empty text).
class ChartNotEnough extends ConsumerWidget {
  const ChartNotEnough({
    super.key,
    required this.result,
    required this.fallback,
    this.action,
  });
  final ChartNotEnoughData<Object?> result;
  final String fallback;
  final Widget? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final digits = ref.watch(
      digitsModeProvider(Localizations.localeOf(context).languageCode),
    );
    final missing = (result.need - result.have).clamp(1, 1 << 30);
    final text = digits.render('$missing');
    final message = switch (result.reason) {
      NotEnoughReason.noData => fallback,
      NotEnoughReason.tooFewTransactions => l.insightsThinNeedTxns(
        missing,
        text,
      ),
      NotEnoughReason.noIncome => l.insightsThinNeedIncome,
      NotEnoughReason.tooFewCycles ||
      NotEnoughReason.tooFewSnapshots ||
      NotEnoughReason.tooFewMerchants => l.insightsThinNeedMonths(
        l.insightsChartsMonthsCount(missing, text),
      ),
    };
    final now = result.current;
    final line = now == null
        ? null
        : l.insightsChartsNetWorthNow(chartMoney(ref, context, now));
    return ChartThinState(
      message: message,
      action: action,
      current: line == null
          ? null
          : Text(
              line,
              key: const Key('thin-current'),
              style: ZType.body.copyWith(color: ZColors.of(context).text),
            ),
    );
  }
}
