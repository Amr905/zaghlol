// T-195 (D-71): the one nudge per payday, "did your salary arrive?". It
// follows the notification settings of the due-date type (its toggle,
// channel and quiet hours), carries no amount, and opens Home. The dedupe
// key is (type, subject, period = the payday), so it shows once per payday
// however often the job runs. A failing alert is swallowed.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../notifications/data/notification_service.dart';
import '../../notifications/domain/notification_types.dart';
import 'salary_matching.dart';
import 'salary_service.dart';

/// `fired_alerts` subject of the nudge.
const String salaryCheckSubject = 'salary_check';

/// Reconciles received credits, then nudges when the window of the latest
/// payday is over and nothing is tied to it. True when an alert was shown or
/// scheduled.
Future<bool> runSalaryCheck({
  required SalaryMatching matching,
  required SalaryService service,
  required NotificationService notifications,
  required CivilDate today,
  required AlertRequest Function(AlertRequest base) buildText,
  bool Function()? shouldStop,
}) async {
  await matching.reconcile(today: today);
  if (shouldStop?.call() ?? false) return false;
  final payday = await service.nudgeDue(today);
  if (payday == null) return false;
  final base = AlertRequest(
    type: NotificationType.upcomingDue,
    subjectId: salaryCheckSubject,
    periodKey: payday.toIso(),
    title: '',
    body: '',
    redactedTitle: '',
    redactedBody: '',
    payload: '/home',
  );
  try {
    final out = await notifications.notify(buildText(base));
    return out == AlertOutcome.shown || out == AlertOutcome.scheduled;
  } catch (_) {
    return false;
  }
}
