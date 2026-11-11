// T-047 test plan 5: the health table.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/capture_health.dart';

CaptureHealth derive({
  bool smsFlavor = true,
  bool smsGranted = true,
  bool notif = true,
  bool smsOn = true,
  bool notifOn = true,
  AbsorbedAlerts absorbed = AbsorbedAlerts.none,
  GuardWriteStatus write = GuardWriteStatus.written,
  LastCycle cycle = LastCycle.none,
  GuardFileState guard = GuardFileState.full,
}) => deriveCaptureHealth(
  caps: CaptureCaps(
    smsFlavor: smsFlavor,
    smsGranted: smsGranted,
    notificationAccess: notif,
  ),
  toggles: CaptureToggles(sms: smsOn, notifications: notifOn),
  absorbed: absorbed,
  guardWrite: write,
  lastCycle: cycle,
  guardState: guard,
);

void main() {
  test('everything on: full, four active channels, no issues', () {
    final h = derive();
    expect(h.mode, CaptureMode.full);
    expect(h.activeChannels, CaptureChannel.values.toSet());
    expect(h.issues, isEmpty);
  });

  test('Play flavour without the SMS exception lists share/paste and manual '
      '(+ notifications when granted); degraded', () {
    final h = derive(smsFlavor: false, smsGranted: false);
    expect(h.mode, CaptureMode.degraded);
    expect(h.channels[CaptureChannel.smsLive], ChannelState.unavailable);
    expect(h.activeChannels, {
      CaptureChannel.notifications,
      CaptureChannel.sharePaste,
      CaptureChannel.manual,
    });
    // No banner issue for it (PO Q1 provisional): mode only.
    expect(h.issues, isNot(contains(CaptureIssue.smsOff)));
    final noNotif = derive(smsFlavor: false, smsGranted: false, notif: false);
    expect(noNotif.activeChannels, {
      CaptureChannel.sharePaste,
      CaptureChannel.manual,
    });
  });

  test('SMS flavour but permission missing: degraded, off(permission), '
      'smsOff issue', () {
    final h = derive(smsGranted: false);
    expect(h.mode, CaptureMode.degraded);
    expect(h.channels[CaptureChannel.smsLive], ChannelState.offPermission);
    expect(h.issues, {CaptureIssue.smsOff});
  });

  test('a deliberate toggle-off is not degraded and raises no issue', () {
    final h = derive(smsOn: false, notifOn: false);
    expect(h.mode, CaptureMode.full);
    expect(h.channels[CaptureChannel.smsLive], ChannelState.offUser);
    expect(h.channels[CaptureChannel.notifications], ChannelState.offUser);
    expect(h.issues, isEmpty);
    // The user's choice wins over a missing permission.
    final both = derive(smsOn: false, smsGranted: false);
    expect(both.mode, CaptureMode.full);
    expect(both.issues, isEmpty);
  });

  test('notification access missing raises notificationsOff only', () {
    final h = derive(notif: false);
    expect(h.mode, CaptureMode.full);
    expect(h.issues, {CaptureIssue.notificationsOff});
  });

  test('each Guard state: baseInvalid is a fault; unknown shows nothing', () {
    for (final g in GuardFileState.values) {
      final h = derive(guard: g);
      expect(
        h.mode,
        g == GuardFileState.baseInvalid ? CaptureMode.fault : CaptureMode.full,
        reason: g.name,
      );
      expect(h.issues, isEmpty, reason: g.name);
    }
  });

  test('guard state x capabilities x toggles never invents an issue from the '
      'guard state', () {
    for (final g in GuardFileState.values) {
      for (final granted in [true, false]) {
        for (final on in [true, false]) {
          final h = derive(guard: g, smsGranted: granted, smsOn: on);
          expect(
            h.issues.contains(CaptureIssue.smsOff),
            granted == false && on,
            reason: '${g.name} $granted $on',
          );
        }
      }
    }
  });

  test('absorbed unreadable and missed notifications become issues; a '
      'key invalidation alone does not (T-039 code 5)', () {
    expect(
      derive(
        absorbed: const AbsorbedAlerts(
          missedNotifications: 3,
          unreadableAtMs: 5,
        ),
      ).issues,
      {CaptureIssue.unreadable, CaptureIssue.missedNotifications},
    );
    expect(derive(absorbed: AbsorbedAlerts.none).issues, isEmpty);
  });

  test('Guard write problems and stuck entries', () {
    for (final s in [
      GuardWriteState.buildFailed,
      GuardWriteState.rejected,
      GuardWriteState.notEffective,
      GuardWriteState.parked,
    ]) {
      expect(derive(write: GuardWriteStatus(s)).issues, {
        CaptureIssue.guardWriteFailed,
      }, reason: s.name);
    }
    for (final s in [
      GuardWriteState.notWritten,
      GuardWriteState.written,
      GuardWriteState.transient,
      GuardWriteState.unavailable,
    ]) {
      expect(derive(write: GuardWriteStatus(s)).issues, isEmpty);
    }
    expect(derive(cycle: const LastCycle(stuck: 2)).issues, {
      CaptureIssue.stuckEntries,
    });
  });

  test('GuardWriteStatus.toString carries the code only', () {
    const s = GuardWriteStatus(
      GuardWriteState.buildFailed,
      code: 'badValue',
      path: r'$.ignore[0].inst',
    );
    expect(s.toString(), 'GuardWriteStatus(buildFailed, badValue)');
  });
}
