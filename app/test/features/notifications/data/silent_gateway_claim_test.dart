// T-237 (found by E2E-05 on the emulator): the headless ingestion engine has a
// silent gateway. An alert raised there used to be claimed in fired_alerts and
// then dropped, so the app never showed it. Now nothing is claimed.
// Synthetic text only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';

class _Shown implements NotificationGateway {
  int shown = 0;
  @override
  Future<void> show(PlatformNotification n) async => shown++;
  @override
  Future<void> schedule(PlatformNotification n) async {}
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<void> cancel(int id) async {}
}

AlertRequest _req() => const AlertRequest(
  type: NotificationType.budgetThreshold,
  subjectId: 'b1',
  periodKey: '2026-11-01',
  threshold: 80,
  title: 't',
  body: 'b',
  redactedTitle: 't',
  redactedBody: 'b',
  payload: '/budget',
);

NotificationService _svc(NotificationGateway gw, List<int> claims) =>
    NotificationService(
      gateway: gw,
      now: () => DateTime(2026, 11, 18, 12),
      loadPrefs: () async => NotificationPrefs(
        typeEnabled: (_) => true,
        quietHours: const QuietHours(enabled: false, startMin: 0, endMin: 0),
        hideAmounts: false,
      ),
      markFired:
          ({
            required kind,
            required subjectId,
            required periodKey,
            required threshold,
            required at,
          }) async {
            claims.add(threshold);
            return true;
          },
      unmarkFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
      }) async {},
    );

void main() {
  test('a silent gateway claims nothing and reports unavailable', () async {
    final claims = <int>[];
    final out = await _svc(
      const SilentNotificationGateway(),
      claims,
    ).notify(_req());
    expect(out, AlertOutcome.unavailable);
    expect(claims, isEmpty);
  });

  test('a real gateway still claims once and shows', () async {
    final claims = <int>[];
    final gw = _Shown();
    final out = await _svc(gw, claims).notify(_req());
    expect(out, AlertOutcome.shown);
    expect(claims, [80]);
    expect(gw.shown, 1);
  });
}
