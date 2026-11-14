import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_ar.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_en.dart';
import 'package:zaghlol/core/platform/notifications_api.g.dart';
import 'package:zaghlol/features/notifications/data/pigeon_notification_gateway.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';

class _FakeHost implements NotificationsHostApi {
  final calls = <String>[];
  List<NotifChannelMsg> channels = [];
  final shown = <NotifMsg>[];
  final scheduled = <(NotifMsg, int)>[];
  NotifPermissionMsg status = NotifPermissionMsg.undetermined;
  bool grant = true;
  bool throwOnRequest = false;
  String? launch;

  @override
  Future<void> ensureChannels(List<NotifChannelMsg> c) async {
    calls.add('ensureChannels');
    channels = c;
  }

  @override
  Future<void> show(NotifMsg n) async {
    calls.add('show');
    shown.add(n);
  }

  @override
  Future<void> schedule(NotifMsg n, int atEpochMs) async {
    calls.add('schedule');
    scheduled.add((n, atEpochMs));
  }

  @override
  Future<void> cancelAll() async => calls.add('cancelAll');

  @override
  Future<void> openSystemSettings() async => calls.add('openSystemSettings');

  @override
  Future<NotifPermissionMsg> permissionStatus() async => status;

  @override
  Future<bool> requestPermission() async {
    if (throwOnRequest) throw StateError('boom');
    calls.add('requestPermission');
    return grant;
  }

  @override
  Future<String?> takeLaunchRoute() async {
    final r = launch;
    launch = null;
    return r;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('channel ids are stable, one per alert type (released contract)', () {
    expect(
      {for (final t in NotificationType.values) t: notificationChannelId(t)},
      {
        NotificationType.budgetThreshold: 'zaghlol_alert_budget',
        NotificationType.spendingSpike: 'zaghlol_alert_spike',
        NotificationType.upcomingDue: 'zaghlol_alert_due',
        NotificationType.duplicateCharge: 'zaghlol_alert_duplicate',
        NotificationType.subscriptionRenewal: 'zaghlol_alert_renewal',
        NotificationType.backupFailure: 'zaghlol_alert_backup_failure',
        NotificationType.weeklySummary: 'zaghlol_alert_weekly',
      },
    );
  });

  test('channels are created once per language with localized names', () async {
    final host = _FakeHost();
    AppLocalizations l = AppLocalizationsEn();
    final g = PigeonNotificationGateway(api: host, l10n: () => l);
    await g.show(
      const PlatformNotification(
        id: 1,
        title: 't',
        body: 'b',
        type: NotificationType.weeklySummary,
      ),
    );
    await g.show(const PlatformNotification(id: 2, title: 't', body: 'b'));
    expect(host.calls.where((c) => c == 'ensureChannels'), hasLength(1));
    expect(host.channels, hasLength(NotificationType.values.length));
    expect(host.channels.map((c) => c.name), contains('Budget alerts'));

    l = AppLocalizationsAr();
    await g.show(const PlatformNotification(id: 3, title: 't', body: 'b'));
    expect(host.calls.where((c) => c == 'ensureChannels'), hasLength(2));
    expect(
      host.channels.map((c) => c.name),
      contains(l.notificationsSettingsBudget),
    );
  });

  test('show carries a route id and a public label without amounts', () async {
    final host = _FakeHost();
    final g = PigeonNotificationGateway(
      api: host,
      l10n: () => AppLocalizationsEn(),
    );
    await g.show(
      const PlatformNotification(
        id: 7,
        title: 'Budget',
        body: 'You spent EGP 1,250.00',
        payload: '/budget',
        type: NotificationType.budgetThreshold,
      ),
    );
    final n = host.shown.single;
    expect(n.id, 7);
    expect(n.channelId, 'zaghlol_alert_budget');
    expect(n.route, '/budget');
    expect(n.publicTitle, 'Budget alerts');
    expect(RegExp(r'[0-9٠-٩]').hasMatch(n.publicTitle), isFalse);
    expect(RegExp(r'[0-9٠-٩]').hasMatch(n.route!), isFalse);
  });

  test('schedule sends the UTC instant; no instant shows now', () async {
    final host = _FakeHost();
    final g = PigeonNotificationGateway(
      api: host,
      l10n: () => AppLocalizationsEn(),
    );
    final at = DateTime.utc(2026, 11, 15, 7);
    await g.schedule(
      PlatformNotification(id: 1, title: 't', body: 'b', at: at),
    );
    expect(host.scheduled.single.$2, at.millisecondsSinceEpoch);
    await g.schedule(const PlatformNotification(id: 2, title: 't', body: 'b'));
    expect(host.shown, hasLength(1));
  });

  test('cancelAll goes to the platform', () async {
    final host = _FakeHost();
    await PigeonNotificationGateway(
      api: host,
      l10n: () => AppLocalizationsEn(),
    ).cancelAll();
    expect(host.calls, contains('cancelAll'));
  });

  group('permission', () {
    test('request prompts and creates channels on a grant', () async {
      final host = _FakeHost();
      var created = 0;
      final p = PigeonNotificationPermission(
        api: host,
        onGranted: () async => created++,
      );
      expect(await p.isAllowed(), isFalse);
      expect(await p.request(), isTrue);
      expect(created, 1);
      host.status = NotifPermissionMsg.granted;
      expect(await p.isAllowed(), isTrue);
    });

    test(
      'denied stays false; a platform error is false, not a throw',
      () async {
        final host = _FakeHost()..grant = false;
        final p = PigeonNotificationPermission(api: host);
        expect(await p.request(), isFalse);
        host.throwOnRequest = true;
        expect(await p.request(), isFalse);
      },
    );
  });

  test('launch route is read through the host', () async {
    final host = _FakeHost()..launch = '/insights';
    // The tap source registers the events handler on the default messenger;
    // the binding is needed for that.
    TestWidgetsFlutterBinding.ensureInitialized();
    final taps = PigeonNotificationTaps(api: host);
    expect(await taps.takeLaunchRoute(), '/insights');
    expect(await taps.takeLaunchRoute(), isNull);
    final got = <String>[];
    final sub = taps.taps.listen(got.add);
    taps.onTap('/budget');
    await Future<void>.delayed(Duration.zero);
    expect(got, ['/budget']);
    await sub.cancel();
  });
}
