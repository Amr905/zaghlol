// T-096 (BR-SUB-03): sends the due reminders through the notifications
// service. The text comes from the caller (l10n); this file only picks the
// items and sets the dedupe key (item id + due date), so a second run on the
// same day shows nothing new. A failing alert doesn't stop the others.

import '../../notifications/data/notification_service.dart';
import '../../notifications/domain/notification_types.dart';
import '../data/recurring_repository.dart';

typedef ReminderTextBuilder = AlertRequest Function(
  DueReminder reminder,
  AlertRequest base,
);

/// Returns how many alerts were shown or scheduled.
Future<int> sendDueReminders({
  required RecurringRepository repository,
  required NotificationService notifications,
  required ReminderTextBuilder buildText,
  bool Function()? shouldStop,
}) async {
  var sent = 0;
  final all = [
    ...await repository.dueReminders(),
    ...await repository.overdueReminders(),
  ];
  for (final r in all) {
    if (shouldStop?.call() ?? false) break; // a restore asked for the gate
    final base = AlertRequest(
      type: NotificationType.upcomingDue,
      subjectId: r.item.id,
      // Overdue reminders use the day count as the threshold, so day 1 and
      // day 3 are separate once-only alerts (never two on the same day).
      threshold: r.overdueDays,
      periodKey: r.dueDate.toIso(),
      title: '',
      body: '',
      redactedTitle: '',
      redactedBody: '',
      payload: 'recurring/${r.item.id}',
    );
    try {
      final out = await notifications.notify(buildText(r, base));
      if (out == AlertOutcome.shown || out == AlertOutcome.scheduled) sent++;
    } catch (_) {
      // The service already released the dedupe claim; try again next run.
    }
  }
  return sent;
}
