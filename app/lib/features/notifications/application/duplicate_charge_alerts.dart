// T-100: raises the duplicate-charge alert through NotificationService. The
// text is the caller's (l10n) and is built from the merchant name and amount
// only, never a raw message; the redacted variant carries neither.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../data/notification_service.dart';
import '../domain/duplicate_charge.dart';
import '../domain/notification_types.dart';

typedef DuplicateAlertText =
    ({String title, String body, String redactedTitle, String redactedBody})
    Function(DuplicateCluster cluster, Money amount);

final class DuplicateChargeAlerts {
  DuplicateChargeAlerts({
    required this.notifications,
    required this.text,
    required this.recent,
  });

  final NotificationService notifications;
  final DuplicateAlertText text;

  /// Live expense transactions at or after [fromMs] (UTC ms).
  final Future<List<DupTxn>> Function(int fromMs) recent;

  /// Looks at the window before [nowMs] and alerts once per cluster (the
  /// fired_alerts key is the cluster's earliest transaction).
  Future<List<AlertOutcome>> run(int nowMs) async {
    final from = nowMs - 2 * duplicateWindow.inMilliseconds;
    final out = <AlertOutcome>[];
    for (final c in findDuplicateCharges(await recent(from))) {
      final t = text(
        c,
        Money(Currency.of(c.first.currency), c.first.amountMinor),
      );
      out.add(
        await notifications.notify(
          AlertRequest(
            type: NotificationType.duplicateCharge,
            subjectId: c.first.id,
            periodKey: 'dup',
            title: t.title,
            body: t.body,
            redactedTitle: t.redactedTitle,
            redactedBody: t.redactedBody,
            payload: '/transactions/${c.first.id}',
          ),
        ),
      );
    }
    return out;
  }
}
