// T-100: binds the backup alert sink (T-152) to NotificationService, with
// l10n text. Failure and reminder alerts carry no amounts, so the redacted
// text is the same.

import '../../../core/l10n/generated/app_localizations.dart';
import '../../backup/application/schedule.dart';
import '../data/notification_service.dart';
import '../domain/notification_types.dart';

BackupAlertSink backupAlertSinkOver(
  NotificationService notifications,
  AppLocalizations Function() l10n,
) => (kind, {required periodKey}) async {
  final l = l10n();
  final failure = kind == BackupAlertKind.failure;
  final title = failure
      ? l.notificationsAlertBackupTitle
      : l.notificationsAlertBackupReminderTitle;
  final body = failure
      ? l.notificationsAlertBackupBody
      : l.notificationsAlertBackupReminderBody;
  await notifications.notify(
    AlertRequest(
      type: NotificationType.backupFailure,
      subjectId: failure ? 'backup_failure' : 'backup_reminder',
      periodKey: periodKey,
      title: title,
      body: body,
      redactedTitle: title,
      redactedBody: body,
      payload: '/settings/backup',
    ),
  );
};
