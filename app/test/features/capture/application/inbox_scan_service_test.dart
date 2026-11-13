// T-048: the triggers: first run, catch-up (open, missed SMS, key
// invalidated), re-scan of one institution. Fakes; synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/capture/application/inbox_scan_service.dart';
import 'package:zaghlol/features/capture/application/scan.dart';
import 'package:zaghlol/features/capture/domain/alert_absorb.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';

import '../support/capture_fakes.dart';
import '../support/scan_fakes.dart';

const int now = 1800000000000;
const int overlap = 10 * 60 * 1000;

void main() {
  late FakeHost host;
  late FakeIngestStore store;
  late MemoryAlertStore alerts;
  late FakeWatermark wm;
  late ScanSettings settings;
  late int clock;
  late InboxScanService service;

  const zbank = ScanSender(
    'ZBANK',
    ScanSenderKind.registry,
    institutionCode: 'zbank',
  );
  const ybank = ScanSender(
    'YBANK',
    ScanSenderKind.registry,
    institutionCode: 'ybank',
  );
  const phone = ScanSender('01000000000', ScanSenderKind.userPhone);

  setUp(() {
    host = FakeHost();
    store = FakeIngestStore();
    alerts = MemoryAlertStore();
    wm = FakeWatermark(null);
    settings = const ScanSettings();
    clock = now;
    host.onQueryInbox = inboxOf([row(1, 'ZBANK', dateMs: now - 3600000)]);
    service = InboxScanService(
      scanner: InboxScanner(
        host: host,
        senders: FakeSenders([zbank, ybank, phone]),
        store: store,
        nowMs: () => clock,
      ),
      host: host,
      alerts: alerts,
      watermark: wm,
      settings: () async => settings,
      nowMs: () => clock,
    );
  });

  Future<void> catchUp() async {
    await service.requestIfPending();
    await service.idle;
  }

  group('first run (FR-ONB-06)', () {
    test(
      'starts depth months back (default 6), without personal senders',
      () async {
        final p = await service.startFirstRun();
        expect(p.phase, ScanPhase.done);
        final q = host.inboxQueries.single;
        expect(q.sinceEpochMs, monthsAgoMs(now, 6));
        expect(q.senderAddresses, ['YBANK', 'ZBANK']);
      },
    );

    test(
      'scan depth setting and the personal opt-in are honoured; the personal '
      'part is capped at 3 months even with 24 months of depth',
      () async {
        settings = const ScanSettings(depthMonths: 24, includePersonal: true);
        await service.startFirstRun();
        final byFirst = {
          for (final q in host.inboxQueries) q.senderAddresses.first: q,
        };
        expect(byFirst['YBANK']!.sinceEpochMs, monthsAgoMs(now, 24));
        expect(byFirst['01000000000']!.sinceEpochMs, monthsAgoMs(now, 3));
      },
    );

    test('a second call during the scan joins it', () async {
      final a = service.startFirstRun();
      final b = service.startFirstRun();
      await Future.wait([a, b]);
      expect(host.inboxQueries.length, 1);
    });
  });

  group('re-scan one institution (FR-CAP-07)', () {
    test('asks only for that institution', () async {
      await service.rescanInstitution('ybank');
      expect(host.inboxQueries.single.senderAddresses, ['YBANK']);
    });
  });

  group('catch-up', () {
    test('open with no watermark and no request: no scan (FU-085)', () async {
      await catchUp();
      expect(host.inboxQueries, isEmpty);
      expect(store.all, isEmpty);
    });

    test('open: since = watermark - 10 min, once per start', () async {
      wm.value = now - 7200000;
      await catchUp();
      expect(host.inboxQueries.single.sinceEpochMs, now - 7200000 - overlap);
      await catchUp(); // the next drain: nothing more to do
      expect(host.inboxQueries.length, 1);
    });

    test(
      'a missed SMS (first missed time from the spool status) lowers since',
      () async {
        wm.value = now - 1000;
        host.status = spoolStatus(firstMissedSmsAtMs: now - 9000000);
        await catchUp();
        expect(host.inboxQueries.single.sinceEpochMs, now - 9000000 - overlap);
      },
    );

    test(
      'a stored request is served and cleared only when the scan completed',
      () async {
        alerts.value = const PersistedAlerts(
          catchUpFromMs: now - 5000000,
          catchUpReason: CatchUpReason.keyInvalidated,
        );
        await catchUp();
        expect(host.inboxQueries.single.sinceEpochMs, now - 5000000 - overlap);
        expect(alerts.value.catchUpFromMs, isNull);
        expect(alerts.value.catchUpReason, isNull);
      },
    );

    test(
      'a failed scan keeps the request and is not retried within the cooldown',
      () async {
        alerts.value = const PersistedAlerts(
          catchUpFromMs: now - 5000000,
          catchUpReason: CatchUpReason.missedSms,
        );
        host.onQueryInbox = (q) async => throw hostError('IO_ERROR');
        await catchUp();
        expect(alerts.value.catchUpFromMs, now - 5000000);
        final calls = host.inboxQueries.length;
        clock += kCatchUpRetryCooldown.inMilliseconds - 1000;
        await catchUp();
        expect(host.inboxQueries.length, calls);
        host.onQueryInbox = inboxOf([row(1, 'ZBANK', dateMs: now - 3600000)]);
        clock += 2000;
        await catchUp();
        expect(
          alerts.value.catchUpFromMs,
          isNull,
          reason: 'served after the cooldown',
        );
      },
    );

    test('a request lowered during the scan is not cleared', () async {
      alerts.value = const PersistedAlerts(
        catchUpFromMs: now - 5000000,
        catchUpReason: CatchUpReason.missedSms,
      );
      final inner = inboxOf([row(1, 'ZBANK', dateMs: now - 3600000)]);
      host.onQueryInbox = (q) async {
        alerts.value = const PersistedAlerts(
          catchUpFromMs: now - 8000000,
          catchUpReason: CatchUpReason.missedSms,
        );
        return inner(q);
      };
      await catchUp();
      expect(alerts.value.catchUpFromMs, now - 8000000);
    });

    test('not in the SMS flavour, or without READ_SMS: nothing runs', () async {
      wm.value = now - 1000;
      host.caps = CaptureCapabilities(
        smsGranted: false,
        smsFlavor: true,
        notificationAccess: true,
        postNotifications: true,
        sdkInt: 34,
      );
      await catchUp();
      host.caps = CaptureCapabilities(
        smsGranted: true,
        smsFlavor: false,
        notificationAccess: true,
        postNotifications: true,
        sdkInt: 34,
      );
      await catchUp();
      expect(host.inboxQueries, isEmpty);
    });

    test(
      'the per-open catch-up can be off; a stored request is still served',
      () async {
        service = InboxScanService(
          scanner: InboxScanner(
            host: host,
            senders: FakeSenders([zbank]),
            store: store,
            nowMs: () => clock,
          ),
          host: host,
          alerts: alerts,
          watermark: wm,
          settings: () async => settings,
          enabled: false,
          nowMs: () => clock,
        );
        wm.value = now - 1000;
        await catchUp();
        expect(host.inboxQueries, isEmpty);
        alerts.value = const PersistedAlerts(
          catchUpFromMs: now - 5000000,
          catchUpReason: CatchUpReason.missedSms,
        );
        await catchUp();
        expect(host.inboxQueries, isNotEmpty);
      },
    );

    test('a watermark read failure neither scans nor throws', () async {
      wm.fails = StateError('x');
      await catchUp();
      expect(host.inboxQueries, isEmpty);
    });

    test('called many times at once (after every drain): one scan', () async {
      wm.value = now - 7200000;
      await Future.wait([
        for (var i = 0; i < 5; i++) service.requestIfPending(),
      ]);
      await service.idle;
      expect(host.inboxQueries.length, 1);
    });

    test(
      'the personal opt-in applies to catch-up with the 3-month cap',
      () async {
        settings = const ScanSettings(includePersonal: true);
        wm.value = now - 86400000 * 200;
        await catchUp();
        final p = host.inboxQueries.firstWhere(
          (q) => q.senderAddresses.contains('01000000000'),
        );
        expect(p.sinceEpochMs, monthsAgoMs(now, 3));
      },
    );
  });
}
