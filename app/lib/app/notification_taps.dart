// NOTIF-GW: a tap on a local notification opens its screen. The payload is a
// route id (never data); `notificationTargetFor` is the allow-list. A tap that
// launched the app is read once at start; later taps arrive as events.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/date_format.dart';
import '../core/l10n/locale_providers.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/routing/app_router.dart';
import '../core/routing/app_routes.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;

import '../features/notifications/application/notification_providers.dart';
import '../features/recurring/presentation/bills_providers.dart';
import '../features/security/domain/app_lock_controller.dart';
import '../features/notifications/domain/notification_routes.dart';
import 'app_navigation.dart';

/// Debug builds only (T-193 AC5 device run): a marker line with no data in it
/// (a target type name, a boolean). `kDebugMode` is a compile-time constant,
/// so release builds drop it.
void _probe(String line) {
  if (kDebugMode) debugPrint('NOTIF_PROBE $line');
}

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
      _probe('launch route=${route != null}');
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
    _probe('open ${target.runtimeType}');
    openNotificationTarget(
      target,
      router: ref.read(appRouterProvider).go,
      context: rootNavigatorKey.currentContext,
      markPaid: (id, due) => payAfterGate(
        waitUnlocked: _waitUnlocked,
        confirm: () => _confirmMarkPaid(id, due),
        pay: () async {
          try {
            final ok = await ref
                .read(billsActionsProvider)
                .markPaid(id, expectedDue: due);
            _probe('paid ok=$ok');
          } catch (_) {
            // Unavailable: the app is open on the bills; nothing else to do.
            // Never echo the error.
          }
        },
      ),
    );
  }

  /// Completes when the app lock is open (at once when it is not engaged).
  Future<bool> _waitUnlocked() {
    if (!ref.read(appLockControllerProvider).locked) return Future.value(true);
    final done = Completer<bool>();
    late final ProviderSubscription<AppLockState> sub;
    sub = ref.listenManual<AppLockState>(appLockControllerProvider, (_, next) {
      if (!next.locked && !done.isCompleted) done.complete(true);
    });
    return done.future.whenComplete(sub.close);
  }

  Future<bool> _confirmMarkPaid(String id, String dueDate) async {
    // The bill's name, so the user knows what they are paying. Unknown id:
    // the dialog still asks, without a name.
    String? name;
    try {
      name = (await ref.read(billItemProvider(id).future))?.name;
    } catch (_) {
      name = null;
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.read(digitsModeProvider(lang));
    final due = CivilDate.tryParse(dueDate);
    final dueText = due == null
        ? null
        : ZDateFormat.date(
            DateTime.utc(due.year, due.month, due.day, 12),
            lang,
            digits,
          );
    _probe('confirm shown');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => MarkPaidConfirmDialog(billName: name, dueText: dueText),
    );
    _probe('confirm answer=${ok ?? false}');
    return ok ?? false;
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
    case HomeTarget():
      router(AppRoutes.home);
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

/// L-1 (defence in depth): a notification route is an intent from outside
/// Dart, so it never writes by itself. [pay] runs only after the app lock is
/// open ([waitUnlocked]) and the user confirms in the app ([confirm]).
Future<void> payAfterGate({
  required Future<bool> Function() waitUnlocked,
  required Future<bool> Function() confirm,
  required Future<void> Function() pay,
}) async {
  if (!await waitUnlocked()) return;
  if (!await confirm()) return;
  await pay();
}

/// L-1: the confirmation before a notification action pays a bill. It names
/// the bill and its due date when they are known.
class MarkPaidConfirmDialog extends StatelessWidget {
  const MarkPaidConfirmDialog({super.key, this.billName, this.dueText});

  final String? billName;
  final String? dueText;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final name = billName;
    final due = dueText;
    return AlertDialog(
      title: Text(l.notificationMarkPaidConfirmTitle),
      content: name == null || due == null
          ? null
          : Text(l.notificationMarkPaidConfirmBody(name, due)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.commonActionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.recurringBillsMarkPaid),
        ),
      ],
    );
  }
}
