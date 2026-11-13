// T-095: AC1 "EGP budget ignores GBP spend", AC2 "Crossing 80% twice in a
// cycle alerts once". Synthetic data only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/budget/application/budget_alert_service.dart';
import 'package:zaghlol/features/budget/domain/budget_progress.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final gbp = Currency.of('GBP');

CycleTotals totals(Currency c, int spend, {Map<String, int> cats = const {}}) =>
    CycleTotals(
      currency: c,
      income: Money(c, 0),
      spend: Money(c, spend),
      pendingSpend: Money(c, 0),
      byCategoryMinor: cats,
    );

BudgetSpec spec({
  String? cat = 'food',
  int limit = 10000,
  Currency? cur,
  bool rollover = false,
}) => BudgetSpec(
  id: 'b1',
  categoryId: cat,
  limit: Money(cur ?? egp, limit),
  thresholds: const [80, 100],
  rollover: rollover,
);

class _Gw implements NotificationGateway {
  final shown = <PlatformNotification>[];
  bool fail = false;
  @override
  Future<void> show(PlatformNotification n) async {
    if (fail) throw StateError('x');
    shown.add(n);
  }

  @override
  Future<void> schedule(PlatformNotification n) async => shown.add(n);
}

void main() {
  group('evaluateBudget', () {
    test('EGP budget ignores GBP spend', () {
      final p = evaluateBudget(spec(), {
        gbp: totals(gbp, 999999, cats: {'food': 999999}),
        egp: totals(egp, 1000, cats: {'food': 1000}),
      });
      expect(p.spent, Money(egp, 1000));
      expect(p.percent, 10);
      expect(p.crossed, isEmpty);
      final only = evaluateBudget(spec(), {
        gbp: totals(gbp, 999999, cats: {'food': 999999}),
      });
      expect(only.spent, Money(egp, 0));
    });
    test('category vs overall', () {
      final t = {
        egp: totals(egp, 9000, cats: {'food': 2000, 'fun': 7000}),
      };
      expect(evaluateBudget(spec(), t).spent.minor, 2000);
      expect(evaluateBudget(spec(cat: null), t).spent.minor, 9000);
    });
    test('boundaries: 79.99 no, 80 yes, 100 yes', () {
      List<int> c(int s) => evaluateBudget(spec(), {
        egp: totals(egp, s, cats: {'food': s}),
      }).crossed;
      expect(c(7999), isEmpty);
      expect(c(8000), [80]);
      expect(c(10000), [80, 100]);
      expect(c(25000), [80, 100]);
    });
    test('zero budget: no percent, no crossing (EC-24)', () {
      final p = evaluateBudget(spec(limit: 0), {
        egp: totals(egp, 500, cats: {'food': 500}),
      });
      expect(p.percent, isNull);
      expect(p.crossed, isEmpty);
    });
    test('rollover adds unused, never negative; mixed currency refused', () {
      final prev = {
        egp: totals(egp, 4000, cats: {'food': 4000}),
      };
      final carry = rolloverCarry(spec(rollover: true), prev);
      expect(carry, Money(egp, 6000));
      final p = evaluateBudget(spec(rollover: true), {
        egp: totals(egp, 8000, cats: {'food': 8000}),
      }, carry: carry);
      expect(p.effectiveLimit.minor, 16000);
      expect(p.crossed, isEmpty);
      final over = {
        egp: totals(egp, 15000, cats: {'food': 15000}),
      };
      expect(rolloverCarry(spec(), over).minor, 0);
      expect(
        () => evaluateBudget(spec(rollover: true), prev, carry: Money(gbp, 1)),
        throwsA(anything),
      );
    });
    test('3-decimal currency uses minor units', () {
      final kwd = Currency.of('KWD');
      final p = evaluateBudget(spec(cur: kwd, limit: 5000, cat: null), {
        kwd: totals(kwd, 4000),
      });
      expect(p.percent, 80);
    });
  });

  group('BudgetAlertService', () {
    late _Gw gw;
    late Set<String> fired;
    late BudgetAlertService svc;
    late Cycle cycle;
    setUpAll(
      () => cycle = Cycle(
        start: CivilDate(2026, 10, 25),
        end: CivilDate(2026, 11, 24),
      ),
    );

    setUp(() {
      gw = _Gw();
      fired = {};
      Future<bool> mark({
        required String kind,
        required String subjectId,
        required String periodKey,
        required int threshold,
        required int at,
      }) async => fired.add('$kind|$subjectId|$periodKey|$threshold');
      final ns = NotificationService(
        gateway: gw,
        now: () => DateTime(2026, 11, 13, 12),
        loadPrefs: () async => const NotificationPrefs(
          typeEnabled: _on,
          quietHours: QuietHours(enabled: false, startMin: 0, endMin: 0),
          hideAmounts: true,
        ),
        markFired: mark,
        unmarkFired:
            ({
              required kind,
              required subjectId,
              required periodKey,
              required threshold,
            }) async {
              fired.remove('$kind|$subjectId|$periodKey|$threshold');
            },
      );
      svc = BudgetAlertService(
        notifications: ns,
        markFired: mark,
        nowMs: () => 0,
        text: (p, t) => (
          title: 'Food $t%: ${p.spent.minor}',
          body: 'amount ${p.spent.minor}',
          redactedTitle: 'Food budget alert',
          redactedBody: 'Open Zaghlol',
        ),
      );
    });

    Map<Currency, CycleTotals> at(int s) => {
      egp: totals(egp, s, cats: {'food': s}),
    };

    test('crossing 80% twice in a cycle alerts once', () async {
      await svc.run(cycle, [spec()], at(8100));
      await svc.run(cycle, [spec()], at(7000)); // refund dips below
      final again = await svc.run(cycle, [spec()], at(8500));
      expect(again.single, AlertOutcome.duplicate);
      expect(gw.shown, hasLength(1));
      // Q-33: redacted keeps the category, no amounts.
      expect(gw.shown.single.title, 'Food budget alert');
    });
    test('next cycle alerts again', () async {
      await svc.run(cycle, [spec()], at(8100));
      final next = Cycle(
        start: cycle.end.plusDays(1),
        end: cycle.end.plusDays(31),
      );
      await svc.run(next, [spec()], at(8100));
      expect(gw.shown, hasLength(2));
    });
    test(
      'jump past both thresholds alerts for 100 only, 80 stays silent',
      () async {
        await svc.run(cycle, [spec()], at(12000));
        expect(gw.shown, hasLength(1));
        expect(gw.shown.single.id, isNot(0));
        expect(fired, contains('budget|b1|2026-10-25|80'));
        await svc.run(cycle, [spec()], at(8100));
        expect(gw.shown, hasLength(1));
      },
    );
    test('gateway failure leaves the alert retryable (FU-133)', () async {
      gw.fail = true;
      await expectLater(svc.run(cycle, [spec()], at(9000)), throwsStateError);
      gw.fail = false;
      await svc.run(cycle, [spec()], at(9000));
      expect(gw.shown, hasLength(1));
    });
    test('zero budget raises nothing', () async {
      expect(await svc.run(cycle, [spec(limit: 0)], at(9000)), isEmpty);
    });
  });
}

bool _on(NotificationType _) => true;
