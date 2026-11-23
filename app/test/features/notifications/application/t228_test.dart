// T-228 (FU-258): a paid bill's reminders are cancelled (manual path,
// notification-action path, matching-payment path), and the weekly summary is
// scheduled as a generic, amount-free Friday nudge. Synthetic text only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/application/weekly_nudge.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol/features/recurring/application/send_due_reminders.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/transactions/data/transactions_providers.dart'
    show clockProvider;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/financial_fixtures.dart';

class _Gw implements NotificationGateway {
  final scheduled = <PlatformNotification>[];
  final cancelled = <int>[];
  @override
  Future<void> show(PlatformNotification n) async {}
  @override
  Future<void> schedule(PlatformNotification n) async => scheduled.add(n);
  @override
  Future<void> cancelScheduled() async {}
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

NotificationService _service(
  _Gw gw, {
  bool hide = false,
  bool weeklyOn = true,
  QuietHours quiet = const QuietHours(enabled: false, startMin: 0, endMin: 0),
  DateTime? now,
}) => NotificationService(
  gateway: gw,
  now: () => now ?? DateTime(2026, 11, 18, 12),
  loadPrefs: () async => NotificationPrefs(
    typeEnabled: (t) => t != NotificationType.weeklySummary || weeklyOn,
    quietHours: quiet,
    hideAmounts: hide,
  ),
  markFired: ({
    required kind,
    required subjectId,
    required periodKey,
    required threshold,
    required at,
  }) async => true,
  unmarkFired: ({
    required kind,
    required subjectId,
    required periodKey,
    required threshold,
  }) async {},
);

int _dueId(String item, String date, int threshold) =>
    NotificationService.idFor(
      type: NotificationType.upcomingDue,
      subjectId: item,
      periodKey: date,
      threshold: threshold,
    );

void main() {
  group('cancelPaidReminders', () {
    test('cancels exactly that item and due date, keeps the others', () async {
      final gw = _Gw();
      await cancelPaidReminders(
        _service(gw),
        itemId: 'r1',
        dueIso: '2026-11-20',
      );
      expect(gw.cancelled, [
        _dueId('r1', '2026-11-20', 0),
        _dueId('r1', '2026-11-20', 1),
        _dueId('r1', '2026-11-20', 3),
      ]);
      for (final other in [
        _dueId('r2', '2026-11-20', 0), // another item
        _dueId('r1', '2026-12-20', 0), // the next due date
      ]) {
        expect(gw.cancelled, isNot(contains(other)));
      }
    });

    test('a failing platform never throws', () async {
      final svc = _service(_ThrowingCancel());
      await cancelPaidReminders(svc, itemId: 'r1', dueIso: '2026-11-20');
    });

    test('a payment match (autoMarkPaid marks) cancels each marked date', () {
      final gw = _Gw();
      return cancelRemindersForMarks(_service(gw), [
        PaidMark(
          itemId: 'r1',
          dueDate: CivilDate(2026, 11, 20),
          txnId: 't1',
          completed: false,
        ),
      ]).then((_) {
        expect(gw.cancelled, contains(_dueId('r1', '2026-11-20', 0)));
        expect(gw.cancelled, hasLength(3));
      });
    });
  });

  group('BillsActions.markPaid cancels the reminder', () {
    late EncryptedDb edb;
    late AppDatabase db;
    late RecurringRepository repo;
    late _Gw gw;
    late ProviderContainer c;
    late String id;

    setUp(() async {
      edb = await EncryptedDb.open();
      db = edb.db;
      await db.into(db.accounts).insert(account('acc1'));
      repo = RecurringRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 17, 12),
        newId: () => 'id1',
      );
      id = await repo.addManual(
        kind: RecurringKind.bill,
        name: 'Rent',
        amount: Money(Currency.of('EGP'), 100),
        dueDay: 20,
        merchantNorm: 'landlord',
        nextDue: CivilDate(2026, 11, 20),
      );
      gw = _Gw();
      c = ProviderContainer(
        overrides: [
          recurringRepositoryProvider.overrideWith((ref) async => repo),
          notificationServiceProvider.overrideWith((ref) async => _service(gw)),
        ],
      );
    });
    tearDown(() async {
      c.dispose();
      await edb.close();
    });

    test('from the app (no pinned date)', () async {
      expect(await c.read(billsActionsProvider).markPaid(id), isTrue);
      expect(gw.cancelled, contains(_dueId(id, '2026-11-20', 0)));
      expect(gw.cancelled, hasLength(3));
    });

    test('from the notification action (pinned date)', () async {
      expect(
        await c
            .read(billsActionsProvider)
            .markPaid(id, expectedDue: '2026-11-20'),
        isTrue,
      );
      expect(gw.cancelled, contains(_dueId(id, '2026-11-20', 1)));
    });

    test('a stale action that pays nothing cancels nothing', () async {
      expect(
        await c
            .read(billsActionsProvider)
            .markPaid(id, expectedDue: '2026-10-20'),
        isFalse,
      );
      expect(gw.cancelled, isEmpty);
    });
  });

  group('weekly nudge', () {
    // 2026-11-18 is a Wednesday; the next Friday is 2026-11-20.
    final wed = CivilDate(2026, 11, 18);

    test('nextFriday is strictly after today', () {
      expect(nextFriday(wed), CivilDate(2026, 11, 20));
      expect(nextFriday(CivilDate(2026, 11, 20)), CivilDate(2026, 11, 27));
      expect(nextFriday(CivilDate(2026, 11, 21)), CivilDate(2026, 11, 27));
    });

    for (final hide in [false, true]) {
      test(
        'scheduled Friday 10:00 with no amount (hide amounts $hide)',
        () async {
          final gw = _Gw();
          final ok = await scheduleWeeklyNudge(
            notifications: _service(gw, hide: hide),
            today: wed,
            title: 'Your weekly summary is ready',
            body: 'Open Zaghlol to see it.',
          );
          expect(ok, isTrue);
          final n = gw.scheduled.single;
          expect(n.at, DateTime(2026, 11, 20, 10).toUtc());
          expect(n.title, 'Your weekly summary is ready');
          expect(n.body, 'Open Zaghlol to see it.');
          expect(n.type, NotificationType.weeklySummary);
          expect(n.payload, '/insights');
        },
      );
    }

    test('refreshing replaces the same alarm (same id)', () async {
      final gw = _Gw();
      final svc = _service(gw);
      for (final d in [wed, wed.plusDays(1)]) {
        await scheduleWeeklyNudge(
          notifications: svc,
          today: d,
          title: 't',
          body: 'b',
        );
      }
      expect(gw.scheduled, hasLength(2));
      expect(gw.scheduled[0].id, gw.scheduled[1].id);
    });

    test('quiet hours move it to their end', () async {
      final gw = _Gw();
      await scheduleWeeklyNudge(
        notifications: _service(
          gw,
          quiet: const QuietHours(enabled: true, startMin: 540, endMin: 660),
        ),
        today: wed,
        title: 't',
        body: 'b',
      );
      expect(gw.scheduled.single.at, DateTime(2026, 11, 20, 11).toUtc());
    });

    test('type off: nothing scheduled, an earlier one is cancelled', () async {
      final gw = _Gw();
      final ok = await scheduleWeeklyNudge(
        notifications: _service(gw, weeklyOn: false),
        today: wed,
        title: 't',
        body: 'b',
      );
      expect(ok, isFalse);
      expect(gw.scheduled, isEmpty);
      expect(gw.cancelled, hasLength(1));
    });

    test('the real summary cancels that Friday\'s nudge only', () async {
      final gw = _Gw();
      final svc = _service(gw);
      await scheduleWeeklyNudge(
        notifications: svc,
        today: wed,
        title: 't',
        body: 'b',
      );
      await cancelWeeklyNudge(svc, CivilDate(2026, 11, 20));
      expect(gw.cancelled, [gw.scheduled.single.id]);
      await cancelWeeklyNudge(svc, CivilDate(2026, 11, 27));
      expect(gw.cancelled, hasLength(2));
      expect(gw.cancelled.last, isNot(gw.scheduled.single.id));
    });
  });

  test(
    'FU-290f: cancelWeeklyNudgeProvider drops the pending Friday nudge',
    () async {
      final gw = _Gw();
      final svc = _service(gw);
      await scheduleWeeklyNudge(
        notifications: svc,
        today: CivilDate(2026, 11, 18),
        title: 't',
        body: 'b',
      );
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 18, 9)),
          notificationServiceProvider.overrideWith((ref) async => svc),
        ],
      );
      addTearDown(c.dispose);
      await c.read(cancelWeeklyNudgeProvider)();
      expect(gw.cancelled, [gw.scheduled.single.id]);
    },
  );
}

class _ThrowingCancel extends _Gw {
  @override
  Future<void> cancel(int id) async => throw StateError('x');
}
