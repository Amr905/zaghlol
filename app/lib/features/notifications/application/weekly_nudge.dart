// T-228 (FU-258 #3): the weekly summary reaches the user even when the app is
// not opened on Friday. Whenever the app runs it schedules a generic nudge
// for the next Friday at 10:00 local, through the notifications service (the
// per-type toggle and quiet hours apply). The week's figures cannot be known
// ahead of time and native code computes nothing, so the nudge is the same
// amount-free text whether or not amounts are hidden. When the app does run on
// that Friday, the real summary replaces it (the nudge is cancelled first).
// Scheduling the same Friday again replaces the earlier alarm (same id).

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../data/notification_service.dart';
import '../domain/notification_types.dart';

/// Local hour of the nudge (same as the bill reminders, 10:00).
const weeklyNudgeHour = 10;

/// `AlertRequest.subjectId` of the nudge (the real summary uses the currency).
const weeklyNudgeSubject = 'nudge';

/// Mon = 0 ... Sun = 6.
int _weekday(CivilDate d) => (d.epochDay + 3) % 7;

/// The first Friday strictly after [today].
CivilDate nextFriday(CivilDate today) {
  final ahead = (4 - _weekday(today)) % 7;
  return today.plusDays(ahead == 0 ? 7 : ahead);
}

/// Schedules the nudge for [nextFriday]. Returns false when nothing was
/// scheduled (type off, or the time is gone). Never throws.
Future<bool> scheduleWeeklyNudge({
  required NotificationService notifications,
  required CivilDate today,
  required String title,
  required String body,
}) async {
  try {
    final friday = nextFriday(today);
    return await notifications.scheduleAt(
      AlertRequest(
        type: NotificationType.weeklySummary,
        subjectId: weeklyNudgeSubject,
        periodKey: friday.toIso(),
        title: title,
        body: body,
        redactedTitle: title,
        redactedBody: body,
        payload: '/insights',
      ),
      DateTime(friday.year, friday.month, friday.day, weeklyNudgeHour),
    );
  } on Object {
    return false;
  }
}

/// Drops the nudge of [day] (shown or waiting): the real summary takes over.
Future<void> cancelWeeklyNudge(
  NotificationService notifications,
  CivilDate day,
) => notifications.cancelAlerts(
  type: NotificationType.weeklySummary,
  subjectId: weeklyNudgeSubject,
  periodKey: day.toIso(),
  thresholds: const [0],
);
