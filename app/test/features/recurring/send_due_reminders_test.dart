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
    expect(await run(), 1);
    expect(await run(), 0);
    expect(gw.shown, hasLength(1));
    expect(gw.shown.single.payload, 'recurring/id1');
    expect(gw.shown.single.title, 'A payment is due'); // redacted
    expect(NotificationType.upcomingDue.kind, 'due');
  });
}
