// Debug-only helpers for the T-193 AC5 device run (no data in the lines).

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../features/notifications/application/notification_providers.dart';
import '../features/notifications/domain/notification_types.dart';

/// Debug builds only (T-193 AC5 device run): a marker line with no data in it
/// (a target type name, a boolean). `kDebugMode` is a compile-time constant,
/// so release builds drop it.
void notifProbe(String line) {
  if (kDebugMode) debugPrint('NOTIF_PROBE $line');
}

/// Debug builds only (T-193 AC5 device run): reinstalling the APK clears the
/// posted notifications, so the device script drops `sig/post_cold`
/// (a bill id and a due date, synthetic) and the real app posts the two cold-run
/// notifications itself, once. Dead code in release (`kDebugMode`).
Future<void> debugPostColdFixtures(WidgetRef ref) async {
  if (!kDebugMode) return;
  try {
    final docs = (await getApplicationDocumentsDirectory()).path;
    final f = File('$docs/sig/post_cold');
    if (!f.existsSync()) return;
    final parts = f.readAsStringSync().trim().split(' ');
    f.deleteSync();
    final gateway = ref.read(notificationGatewayProvider);
    await gateway.show(
      const PlatformNotification(
        id: 9102,
        title: 'ZPROBE tap cold',
        body: 'synthetic',
        payload: '/settings/backup',
        type: NotificationType.upcomingDue,
      ),
    );
    await gateway.show(
      PlatformNotification(
        id: 9104,
        title: 'ZPROBE paid cold',
        body: 'synthetic',
        payload: '/insights',
        type: NotificationType.upcomingDue,
        actionTitle: 'ZPROBE PAY COLD',
        actionRoute: '/recurring/${parts[0]}/paid/${parts[1]}',
      ),
    );
    notifProbe('cold fixtures posted');
  } catch (_) {
    notifProbe('cold fixtures failed');
  }
}
