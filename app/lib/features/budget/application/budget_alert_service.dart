// T-095: fires budget threshold alerts through the notification service,
// once per threshold per budget per cycle (BR-BUD-02). Several thresholds
// crossed at once (a big purchase) alert only for the highest; the lower
// ones are recorded as fired so they never alert later. Text comes from the
// caller (l10n); the redacted variant keeps the category name and drops
// amounts (Q-33). Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../notifications/data/notification_service.dart';
import '../../notifications/domain/notification_types.dart';
import '../domain/budget_progress.dart';

typedef BudgetAlertText =
    ({String title, String body, String redactedTitle, String redactedBody})
    Function(BudgetProgress progress, int threshold);

final class BudgetAlertService {
  BudgetAlertService({
    required this.notifications,
    required this.markFired,
    required this.text,
    required this.nowMs,
  });

  final NotificationService notifications;

  /// Same contract as the notification service's dedupe claim.
  final Future<bool> Function({
    required String kind,
    required String subjectId,
    required String periodKey,
    required int threshold,
    required int at,
  })
  markFired;
  final BudgetAlertText text;
  final int Function() nowMs;

  /// Evaluates [specs] against [totals] for [cycle]; returns the outcomes of
  /// the alerts raised. [carries]: rollover per budget id.
  Future<List<AlertOutcome>> run(
    Cycle cycle,
    List<BudgetSpec> specs,
    Map<Currency, CycleTotals> totals, {
    Map<String, Money> carries = const {},
  }) async {
    final out = <AlertOutcome>[];
    for (final spec in specs) {
      final p = evaluateBudget(spec, totals, carry: carries[spec.id]);
      if (p.crossed.isEmpty) continue; // also the zero-budget case (EC-24)
      final top = p.crossed.last;
      for (final lower in p.crossed.take(p.crossed.length - 1)) {
        await markFired(
          kind: NotificationType.budgetThreshold.kind,
          subjectId: spec.id,
          periodKey: cycle.key,
          threshold: lower,
          at: nowMs(),
        );
      }
      final t = text(p, top);
      out.add(
        await notifications.notify(
          AlertRequest(
            type: NotificationType.budgetThreshold,
            subjectId: spec.id,
            periodKey: cycle.key,
            threshold: top,
            title: t.title,
            body: t.body,
            redactedTitle: t.redactedTitle,
            redactedBody: t.redactedBody,
            payload: '/budget',
          ),
        ),
      );
    }
    return out;
  }
}
