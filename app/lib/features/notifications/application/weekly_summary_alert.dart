// T-100: the Friday weekly summary (FR-NTF-01). Covers the seven local days
// before today, one alert per currency with spend (never summed across
// currencies). Figures come from the chart repository (T-105), which already
// excludes internal transfers. The redacted variant carries no amounts. Send
// time is the caller's schedule; quiet hours still apply through the service.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../insights/data/chart_repository.dart';
import '../../insights/domain/chart_models.dart';
import '../data/notification_service.dart';
import '../domain/notification_types.dart';

typedef WeeklyAlertText =
    ({String title, String body, String redactedTitle, String redactedBody})
    Function(Money spent, String? topCategoryId);

/// The seven local days ending the day before [today].
ChartPeriod weeklySummaryPeriod(CivilDate today) =>
    ChartPeriod(today.plusDays(-7), today.plusDays(-1));

final class WeeklySummaryAlert {
  WeeklySummaryAlert({
    required this.notifications,
    required this.currencies,
    required this.donut,
    required this.text,
  });

  /// Reads the figures from the chart repository.
  factory WeeklySummaryAlert.over(
    ChartRepository charts, {
    required NotificationService notifications,
    required WeeklyAlertText text,
  }) => WeeklySummaryAlert(
    notifications: notifications,
    currencies: charts.currenciesWithActivity,
    donut: charts.categoryDonut,
    text: text,
  );

  final NotificationService notifications;
  final Future<List<Currency>> Function(ChartPeriod) currencies;
  final Future<ChartResult<CategoryDonut>> Function(ChartPeriod, ChartFilter)
  donut;
  final WeeklyAlertText text;

  Future<List<AlertOutcome>> run(CivilDate today) async {
    final period = weeklySummaryPeriod(today);
    final out = <AlertOutcome>[];
    for (final currency in await currencies(period)) {
      final r = await donut(period, ChartFilter(currency: currency));
      if (r is! ChartReady<CategoryDonut>) continue;
      final d = r.data;
      if (d.total.minor <= 0 || d.slices.isEmpty) continue;
      final top = d.slices.reduce(
        (a, b) => b.amount.minor > a.amount.minor ? b : a,
      );
      final t = text(d.total, top.categoryId);
      out.add(
        await notifications.notify(
          AlertRequest(
            type: NotificationType.weeklySummary,
            subjectId: currency.code,
            periodKey: period.key,
            title: t.title,
            body: t.body,
            redactedTitle: t.redactedTitle,
            redactedBody: t.redactedBody,
            payload: '/insights',
          ),
        ),
      );
    }
    return out;
  }
}
