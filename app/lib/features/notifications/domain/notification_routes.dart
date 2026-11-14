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

final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

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
  return null;
}
