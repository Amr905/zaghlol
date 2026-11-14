// T-100: duplicate-charge and weekly-summary alerts, backup sink binding.
// Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/backup/application/schedule.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/notifications/application/backup_alert_sink.dart';
import 'package:zaghlol/features/notifications/application/duplicate_charge_alerts.dart';
import 'package:zaghlol/features/notifications/application/weekly_summary_alert.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/duplicate_charge.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

class _Gw implements NotificationGateway {
  final shown = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

DupTxn tx(
  String id,
  int min, {
  int amount = 15000,
  String merchant = 'shop',
  String account = 'a1',
  String cur = 'EGP',
}) => DupTxn(
  id: id,
  accountId: account,
  merchantNorm: merchant,
  amountMinor: amount,
  currency: cur,
  occurredAtMs:
      DateTime.utc(2026, 11, 14, 10, 0).millisecondsSinceEpoch + min * 60000,
);

(NotificationService, _Gw) service({bool hide = false}) {
  final gw = _Gw();
  final fired = <String>{};
  return (
    NotificationService(
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
      now: () => DateTime.utc(2026, 11, 14, 12),
    ),
    gw,
  );
}

({String title, String body, String redactedTitle, String redactedBody})
dupText(DuplicateCluster c, Money m) => (
  title: 'Maybe twice',
  body: 'shop ${m.minor}',
  redactedTitle: 'Maybe twice',
  redactedBody: 'Open Zaghlol',
);

void main() {
  group('findDuplicateCharges', () {
    test('two identical within 10 min cluster; 10:01 apart do not', () {
      expect(findDuplicateCharges([tx('a', 0), tx('b', 10)]), hasLength(1));
      expect(findDuplicateCharges([tx('a', 0), tx('b', 11)]), isEmpty);
    });
    test('different amount, merchant, account or currency never match', () {
      for (final other in [
        tx('b', 1, amount: 15001),
        tx('b', 1, merchant: 'other'),
        tx('b', 1, account: 'a2'),
        tx('b', 1, cur: 'USD'),
      ]) {
        expect(findDuplicateCharges([tx('a', 0), other]), isEmpty);
      }
    });
    test('a third charge joins the same cluster', () {
      final c = findDuplicateCharges([tx('c', 8), tx('a', 0), tx('b', 4)]);
      expect(c, hasLength(1));
      expect(c.single.first.id, 'a');
      expect(c.single.members, hasLength(3));
    });
    test('zero, negative and blank merchant are ignored', () {
      expect(
        findDuplicateCharges([tx('a', 0, amount: 0), tx('b', 1, amount: 0)]),
        isEmpty,
      );
      expect(
        findDuplicateCharges([tx('a', 0, amount: -5), tx('b', 1, amount: -5)]),
        isEmpty,
      );
      expect(
        findDuplicateCharges([
          tx('a', 0, merchant: ' '),
          tx('b', 1, merchant: ' '),
        ]),
        isEmpty,
      );
    });
  });

  group('DuplicateChargeAlerts', () {
    test(
      'two identical debits in 10 min give one alert, even run twice',
      () async {
        final (svc, gw) = service();
        final a = DuplicateChargeAlerts(
          notifications: svc,
          text: dupText,
          recent: (_) async => [tx('a', 0), tx('b', 5)],
        );
        final now = DateTime.utc(2026, 11, 14, 10, 6).millisecondsSinceEpoch;
        expect(await a.run(now), [AlertOutcome.shown]);
        expect(await a.run(now), [AlertOutcome.duplicate]);
        expect(gw.shown, hasLength(1));
      },
    );
    test('hidden amounts: no amount on the lock screen', () async {
      final (svc, gw) = service(hide: true);
      await DuplicateChargeAlerts(
        notifications: svc,
        text: dupText,
        recent: (_) async => [tx('a', 0), tx('b', 5)],
      ).run(0);
      expect(gw.shown.single.body, 'Open Zaghlol');
      expect(gw.shown.single.body.contains('15000'), isFalse);
    });
  });

  group('WeeklySummaryAlert', () {
    final egp = Currency.of('EGP');
    final usd = Currency.of('USD');
    ChartResult<CategoryDonut> donut(Currency c, int minor) => ChartReady(
      CategoryDonut(
        total: Money(c, minor),
        slices: [
          CategorySlice(
            categoryId: 'food',
            amount: Money(c, minor ~/ 2),
            shareBp: 5000,
            count: 1,
          ),
          CategorySlice(
            categoryId: 'fun',
            amount: Money(c, minor - minor ~/ 2 + 10),
            shareBp: 5000,
            count: 1,
          ),
        ],
      ),
    );

    test('period is the seven days before today', () {
      final p = weeklySummaryPeriod(CivilDate(2026, 11, 1));
      expect(p.from, CivilDate(2026, 10, 25));
      expect(p.to, CivilDate(2026, 10, 31));
    });

    test('one alert per currency, never summed; top category passed', () async {
      final (svc, gw) = service();
      final seen = <String>[];
      final w = WeeklySummaryAlert(
        notifications: svc,
        currencies: (_) async => [egp, usd],
        donut: (p, f) async =>
            donut(f.currency, f.currency == egp ? 100000 : 5000),
        text: (m, top) {
          seen.add('${m.currency.code}:${m.minor}:$top');
          return (
            title: 'Weekly',
            body: '${m.minor}',
            redactedTitle: 'Weekly',
            redactedBody: 'Open Zaghlol',
          );
        },
      );
      await w.run(CivilDate(2026, 11, 13));
      expect(seen, ['EGP:100000:fun', 'USD:5000:fun']);
      expect(gw.shown, hasLength(2));
      expect(await w.run(CivilDate(2026, 11, 13)), [
        AlertOutcome.duplicate,
        AlertOutcome.duplicate,
      ]);
    });

    test('no spend sends nothing; hidden amounts redact', () async {
      final (svc, gw) = service(hide: true);
      final w = WeeklySummaryAlert(
        notifications: svc,
        currencies: (_) async => [egp, usd],
        donut: (p, f) async => f.currency == egp
            ? donut(egp, 4000)
            : const ChartNotEnoughData(
                NotEnoughReason.noData,
                have: 0,
                need: 1,
              ),
        text: (m, top) => (
          title: 'Weekly',
          body: 'spent ${m.minor}',
          redactedTitle: 'Weekly',
          redactedBody: 'Open Zaghlol',
        ),
      );
      await w.run(CivilDate(2026, 11, 13));
      expect(gw.shown, hasLength(1));
      expect(gw.shown.single.body, 'Open Zaghlol');
    });
  });

  group('backupAlertSinkOver', () {
    for (final lang in ['en', 'ar']) {
      test('failure and reminder use l10n text ($lang)', () async {
        final (svc, gw) = service();
        final l = lookupAppLocalizations(Locale(lang));
        final sink = backupAlertSinkOver(svc, () => l);
        await sink(BackupAlertKind.failure, periodKey: 'k1');
        await sink(BackupAlertKind.reminder, periodKey: 'k1');
        await sink(BackupAlertKind.reminder, periodKey: 'k1');
        expect(gw.shown.map((n) => n.title), [
          l.notificationsAlertBackupTitle,
          l.notificationsAlertBackupReminderTitle,
        ]);
        expect(gw.shown[1].body, l.notificationsAlertBackupReminderBody);
      });
    }
  });
}
