// NOTIF-GW: a tap on a local notification opens its screen. The payload is a
// route id (never data); `notificationTargetFor` is the allow-list. A tap that
// launched the app is read once at start; later taps arrive as events.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/routing/app_router.dart';
import '../core/routing/app_routes.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/recurring/presentation/bills_providers.dart';
import '../features/notifications/domain/notification_routes.dart';
import 'app_navigation.dart';

class NotificationTapLifecycle extends ConsumerStatefulWidget {
  const NotificationTapLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationTapLifecycle> createState() =>
      _NotificationTapLifecycleState();
}

class _NotificationTapLifecycleState
    extends ConsumerState<NotificationTapLifecycle> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    final source = ref.read(notificationTapSourceProvider);
    _sub = source.taps.listen(_open);
    // After the first frame, so the router and navigator exist.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final route = await source.takeLaunchRoute();
      if (mounted && route != null) _open(route);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _open(String route) {
    final target = notificationTargetFor(route);
    if (target == null) return;
    openNotificationTarget(
      target,
      router: ref.read(appRouterProvider).go,
      context: rootNavigatorKey.currentContext,
      markPaid: (id, due) async {
        try {
          await ref.read(billsActionsProvider).markPaid(id, expectedDue: due);
        } catch (_) {
          // Locked or unavailable: the app is open on the bills; nothing
          // else to do. Never echo the error.
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens [target]. [router] goes to a location; [context] is the root
/// navigator's, for the pushed screens (null: not ready, nothing opens).
void openNotificationTarget(
  NotificationTarget target, {
  required void Function(String location) router,
  required BuildContext? context,
  Future<void> Function(String id, String dueDate)? markPaid,
}) {
  switch (target) {
    case InsightsTarget():
      router(AppRoutes.insights);
    case TransactionTarget(:final id):
      if (context != null) unawaited(openTransactionDetail(context, id));
    case MarkPaidTarget(:final id, :final dueDate):
      // Opens the bills first, then pays: the user sees the row change.
      router(AppRoutes.insights);
      if (markPaid != null) unawaited(markPaid(id, dueDate));
    case BackupTarget():
      if (context != null) unawaited(openBackup(context));
  }
}
