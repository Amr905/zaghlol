// T-096: due reminders go through the notifications service once per
// (item, due date). Synthetic text only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol/features/recurring/application/send_due_reminders.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../core/db/financial_fixtures.dart';

class _Gateway implements NotificationGateway {
  final shown = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1'));
  });
  tearDown(() => edb.close());

  test('one alert per due date; a second run shows nothing', () async {
    var n = 0;
    final repo = RecurringRepository(
      db,
      clock: () => DateTime.utc(2026, 11, 17, 12),
      newId: () => 'id${++n}',
    );
    await repo.addManual(
      kind: RecurringKind.bill,
      name: 'Rent',
      amount: Money(Currency.of('EGP'), 100),
      dueDay: 20,
      merchantNorm: 'landlord',
      nextDue: CivilDate(2026, 11, 20),
    );
    final fired = <String>{};
    final gw = _Gateway();
    final service = NotificationService(
      gateway: gw,
      loadPrefs: () async => NotificationPrefs(
        typeEnabled: (_) => true,
        quietHours: const QuietHours(enabled: false, startMin: 0, endMin: 0),
        hideAmounts: true,
      ),
      markFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
        required at,
      }) async => fired.add('$kind|$subjectId|$periodKey|$threshold'),
      unmarkFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
      }) async {},
      now: () => DateTime.utc(2026, 11, 17, 12),
    );
    AlertRequest text(DueReminder r, AlertRequest b) => AlertRequest(
      type: b.type,
      subjectId: b.subjectId,
      periodKey: b.periodKey,
      title: 'Rent due soon',
      body: 'Due ${r.dueDate}',
      redactedTitle: 'A payment is due',
      redactedBody: 'Open Zaghlol',
      payload: b.payload,
    );
    Future<int> run() => sendDueReminders(
      repository: repo,
      notifications: service,
      buildText: text,
    );
    // FU-255: a restore asked for the gate: nothing is sent, nothing is lost.
    expect(
      await sendDueReminders(
        repository: repo,
        notifications: service,
        buildText: text,
        shouldStop: () => true,
      ),
      0,
    );
    expect(gw.shown, isEmpty);
    expect(await run(), 1);
    expect(await run(), 0);
    expect(gw.shown, hasLength(1));
    expect(gw.shown.single.payload, 'recurring/id1');
    expect(gw.shown.single.title, 'A payment is due'); // redacted
    expect(NotificationType.upcomingDue.kind, 'due');
  });

  group('PO OVERDUE-REMINDERS', () {
    Future<
      ({
        RecurringRepository repo,
        NotificationService service,
        _Gateway gw,
        void Function(DateTime) setNow,
      })
    >
    setup({bool hide = false}) async {
      var clock = DateTime.utc(2026, 11, 17, 12);
      var n = 0;
      final repo = RecurringRepository(
        db,
        clock: () => clock,
        newId: () => 'id${++n}',
      );
      await repo.addManual(
        kind: RecurringKind.bill,
        name: 'Rent',
        amount: Money(Currency.of('EGP'), 100),
        dueDay: 20,
        merchantNorm: 'landlord',
        nextDue: CivilDate(2026, 11, 20),
      );
      final fired = <String>{};
      final gw = _Gateway();
      final service = NotificationService(
        gateway: gw,
        loadPrefs: () async => NotificationPrefs(
          typeEnabled: (_) => true,
          quietHours: const QuietHours(enabled: false, startMin: 0, endMin: 0),
          hideAmounts: hide,
        ),
        markFired: ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
          required at,
        }) async => fired.add('$kind|$subjectId|$periodKey|$threshold'),
        unmarkFired: ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
        }) async {},
        now: () => clock,
      );
      return (
        repo: repo,
        service: service,
        gw: gw,
        setNow: (DateTime d) => clock = d,
      );
    }

    AlertRequest text(DueReminder r, AlertRequest b) => AlertRequest(
      type: b.type,
      subjectId: b.subjectId,
      periodKey: b.periodKey,
      threshold: b.threshold,
      title: r.overdueDays > 0 ? 'overdue ${r.overdueDays}' : 'soon',
      body: 'amount 100',
      redactedTitle: r.overdueDays > 0 ? 'overdue ${r.overdueDays}' : 'soon',
      redactedBody: 'no amount',
      payload: b.payload,
    );

    test(
      'day+1 and day+3 once each; nothing on day+2, day+4 or day+5',
      () async {
        final s = await setup();
        Future<int> run(int day) {
          s.setNow(DateTime.utc(2026, 11, day, 12));
          return sendDueReminders(
            repository: s.repo,
            notifications: s.service,
            buildText: text,
          );
        }

        expect(await run(20), 1); // due today: the upcoming one
        expect(await run(21), 1); // day+1
        expect(await run(21), 0); // same day again
        expect(await run(22), 0);
        expect(await run(23), 1); // day+3
        expect(await run(23), 0);
        expect(await run(24), 0);
        expect(await run(25), 0); // day+5
        expect(s.gw.shown.map((n) => n.title), [
          'soon',
          'overdue 1',
          'overdue 3',
        ]);
      },
    );

    test('nothing once the item is paid', () async {
      final s = await setup();
      s.setNow(DateTime.utc(2026, 11, 21, 12));
      expect(await s.repo.markPaidManual('id1'), isTrue);
      expect(
        await sendDueReminders(
          repository: s.repo,
          notifications: s.service,
          buildText: text,
        ),
        0,
      );
      expect(s.gw.shown, isEmpty);
    });

    test('nothing once the item is deleted', () async {
      final s = await setup();
      s.setNow(DateTime.utc(2026, 11, 23, 12));
      await s.repo.deleteItem('id1');
      expect(await s.repo.overdueReminders(), isEmpty);
    });

    test('not before 10:00 local on the day', () async {
      final s = await setup();
      s.setNow(DateTime.utc(2026, 11, 21, 3));
      expect(await s.repo.overdueReminders(), isEmpty);
    });

    test('hide amounts: the redacted text is shown', () async {
      final s = await setup(hide: true);
      s.setNow(DateTime.utc(2026, 11, 21, 12));
      await sendDueReminders(
        repository: s.repo,
        notifications: s.service,
        buildText: text,
      );
      expect(s.gw.shown.single.body, 'no amount');
    });
  });
}
