// T-196 (D-72): the single notice that follows an automatic detection run.
// One alert per run, however many bills were added; the text comes from the
// caller (l10n) and carries no amount. The dedupe key is (type, subject,
// period = today's date), so a second run on the same day shows nothing new.
// A failing alert is swallowed: the bills are already added and visible.

import '../../notifications/data/notification_service.dart';
import '../../notifications/domain/notification_types.dart';
import '../../../core/db/app_database.dart' show RecurringItemRow;

typedef AutoAddedTextBuilder = AlertRequest Function(
  List<RecurringItemRow> added,
  AlertRequest base,
);

/// `fired_alerts` subject of the notice.
const String autoAddedNoticeSubject = 'auto_added';

/// Returns true when the alert was shown or scheduled. [periodKey] is the
/// local date (ISO).
Future<bool> notifyAutoAdded({
  required List<RecurringItemRow> added,
  required NotificationService notifications,
  required AutoAddedTextBuilder buildText,
  required String periodKey,
}) async {
  if (added.isEmpty) return false;
  final base = AlertRequest(
    type: NotificationType.subscriptionRenewal,
    subjectId: autoAddedNoticeSubject,
    periodKey: periodKey,
    title: '',
    body: '',
    redactedTitle: '',
    redactedBody: '',
    payload: '/insights',
  );
  try {
    final out = await notifications.notify(buildText(added, base));
    return out == AlertOutcome.shown || out == AlertOutcome.scheduled;
  } catch (_) {
    return false;
  }
}
