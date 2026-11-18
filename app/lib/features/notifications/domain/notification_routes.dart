// NOTIF-GW: what a tapped notification opens. The payload of a notification is
// a route id (see the `payload:` of each alert), never data. Anything outside
// this allow-list opens nothing, so a spoofed intent can only land on a screen
// the app already has.

sealed class NotificationTarget {
  const NotificationTarget();
}

/// The Insights tab (budget alerts and the weekly summary).
final class InsightsTarget extends NotificationTarget {
  const InsightsTarget();
}

/// One transaction (duplicate-charge alerts).
final class TransactionTarget extends NotificationTarget {
  const TransactionTarget(this.id);
  final String id;
}

/// The backup screen (backup failure and reminder).
final class BackupTarget extends NotificationTarget {
  const BackupTarget();
}

/// The "Mark as paid" action of an overdue reminder. [dueDate] (yyyy-mm-dd) is
/// the occurrence the reminder was about: a stale action never pays a later
/// one.
final class MarkPaidTarget extends NotificationTarget {
  const MarkPaidTarget(this.id, this.dueDate);
  final String id;
  final String dueDate;
}

final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Null: unknown or malformed; nothing opens.
NotificationTarget? notificationTargetFor(String? route) {
  if (route == null || route.length > 96) return null;
  switch (route) {
    case '/budget':
    case '/insights':
      return const InsightsTarget();
    case '/settings/backup':
      return const BackupTarget();
  }
  const prefix = '/transactions/';
  if (route.startsWith(prefix)) {
    final id = route.substring(prefix.length);
    if (_id.hasMatch(id)) return TransactionTarget(id);
  }
  const rec = '/recurring/';
  if (route.startsWith(rec)) {
    final parts = route.substring(rec.length).split('/');
    if (parts.isNotEmpty && _id.hasMatch(parts[0])) {
      // Bills live in the Insights tab.
      if (parts.length == 1) return const InsightsTarget();
      if (parts.length == 3 && parts[1] == 'paid' && _date.hasMatch(parts[2])) {
        return MarkPaidTarget(parts[0], parts[2]);
      }
    }
  }
  return null;
}
