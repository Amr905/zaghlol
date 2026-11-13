// T-094: AC1 "quiet hours delay non-urgent alerts", AC2 "redacted variant
// shows no amounts". Synthetic text only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/data/notification_service.dart';
import 'package:zaghlol/features/notifications/domain/notification_types.dart';
import 'package:zaghlol/features/notifications/domain/quiet_hours.dart';

class FakeGateway implements NotificationGateway {
  final shown = <PlatformNotification>[];
  final scheduled = <PlatformNotification>[];
  @override
  Future<void> show(PlatformNotification n) async => shown.add(n);
  @override
  Future<void> schedule(PlatformNotification n) async => scheduled.add(n);
}

const quiet = QuietHours(enabled: true, startMin: 23 * 60, endMin: 8 * 60);

AlertRequest req({
  NotificationType type = NotificationType.budgetThreshold,
  int threshold = 80,
}) => AlertRequest(
  type: type,
  subjectId: 'b1',
  periodKey: '2026-10-25',
  threshold: threshold,
  title: 'Food at 80%: 4,000 EGP of 5,000',
  body: 'You spent 4,000 EGP',
  redactedTitle: 'Food budget alert',
  redactedBody: 'Open Zaghlol',
);

bool _all(NotificationType _) => true;

class _ThrowingGateway implements NotificationGateway {
  @override
  Future<void> show(PlatformNotification n) async => throw StateError('x');
  @override
  Future<void> schedule(PlatformNotification n) async => throw StateError('x');
}

void main() {
  group('QuietHours', () {
    test('wraps midnight; boundaries', () {
      expect(quiet.isQuiet(DateTime(2026, 1, 1, 23, 0)), isTrue);
      expect(quiet.isQuiet(DateTime(2026, 1, 1, 22, 59)), isFalse);
      expect(quiet.isQuiet(DateTime(2026, 1, 1, 7, 59)), isTrue);
      expect(quiet.isQuiet(DateTime(2026, 1, 1, 8, 0)), isFalse);
    });
    test('nextAllowed: before and after midnight, month end', () {
      expect(
        quiet.nextAllowed(DateTime(2026, 1, 31, 23, 30)),
        DateTime(2026, 2, 1, 8),
      );
      expect(
        quiet.nextAllowed(DateTime(2026, 2, 1, 2, 0)),
        DateTime(2026, 2, 1, 8),
      );
      expect(
        quiet.nextAllowed(DateTime(2026, 2, 1, 12)),
        DateTime(2026, 2, 1, 12),
      );
    });
    test('disabled and empty windows are never quiet', () {
      const off = QuietHours(enabled: false, startMin: 1380, endMin: 480);
      const empty = QuietHours(enabled: true, startMin: 600, endMin: 600);
      expect(off.isQuiet(DateTime(2026, 1, 1, 2)), isFalse);
      expect(empty.isQuiet(DateTime(2026, 1, 1, 10)), isFalse);
    });
    test('same-day window', () {
      const w = QuietHours(enabled: true, startMin: 600, endMin: 720);
      expect(w.nextAllowed(DateTime(2026, 1, 1, 11)), DateTime(2026, 1, 1, 12));
    });
  });

  group('NotificationService', () {
    late FakeGateway gw;
    late Set<String> fired;
    NotificationService make(
      DateTime now, {
      bool hide = false,
      bool Function(NotificationType)? enabled,
    }) => NotificationService(
      gateway: gw,
      now: () => now,
      loadPrefs: () async => NotificationPrefs(
        typeEnabled: enabled ?? (_) => true,
        quietHours: quiet,
        hideAmounts: hide,
      ),
      markFired: ({
        required kind,
        required subjectId,
        required periodKey,
        required threshold,
        required at,
      }) async => fired.add('$kind|$subjectId|$periodKey|$threshold'),
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

    setUp(() {
      gw = FakeGateway();
      fired = {};
    });

    test('FU-133: a failed gateway call releases the dedupe claim', () async {
      final n = make(DateTime(2026, 11, 13, 12));
      final bad = _ThrowingGateway();
      final svc = NotificationService(
        gateway: bad,
        now: () => DateTime(2026, 11, 13, 12),
        loadPrefs: () async => const NotificationPrefs(
          typeEnabled: _all,
          quietHours: QuietHours(enabled: false, startMin: 0, endMin: 0),
          hideAmounts: false,
        ),
        markFired: ({
          required kind,
          required subjectId,
          required periodKey,
          required threshold,
          required at,
        }) async => fired.add('$kind|$subjectId|$periodKey|$threshold'),
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
      await expectLater(svc.notify(req()), throwsStateError);
      expect(fired, isEmpty);
      expect(await n.notify(req()), AlertOutcome.shown);
    });

    test('daytime shows now', () async {
      final o = await make(DateTime(2026, 11, 13, 12)).notify(req());
      expect(o, AlertOutcome.shown);
      expect(gw.shown.single.at, isNull);
    });

    test('quiet hours delay to the end, not drop', () async {
      final o = await make(DateTime(2026, 11, 13, 23, 40)).notify(req());
      expect(o, AlertOutcome.scheduled);
      expect(gw.shown, isEmpty);
      expect(gw.scheduled.single.at, DateTime(2026, 11, 14, 8).toUtc());
    });

    test('redacted variant carries no amounts', () async {
      await make(DateTime(2026, 11, 13, 12), hide: true).notify(req());
      final n = gw.shown.single;
      expect('${n.title} ${n.body}', isNot(matches(RegExp(r'[0-9٠-٩]'))));
      expect(n.title, contains('Food'));
    });

    test('full text when not hidden', () async {
      await make(DateTime(2026, 11, 13, 12)).notify(req());
      expect(gw.shown.single.body, contains('4,000'));
    });

    test('disabled type does nothing and does not mark fired', () async {
      final o = await make(
        DateTime(2026, 11, 13, 12),
        enabled: (t) => t != NotificationType.budgetThreshold,
      ).notify(req());
      expect(o, AlertOutcome.disabled);
      expect(fired, isEmpty);
      expect(gw.shown, isEmpty);
    });

    test('same key fires once; another threshold fires', () async {
      final s = make(DateTime(2026, 11, 13, 12));
      expect(await s.notify(req()), AlertOutcome.shown);
      expect(await s.notify(req()), AlertOutcome.duplicate);
      expect(await s.notify(req(threshold: 100)), AlertOutcome.shown);
      expect(gw.shown, hasLength(2));
      expect(gw.shown[0].id, isNot(gw.shown[1].id));
    });

    test('every type has its own toggle and kind', () {
      expect(
        NotificationType.values.map((t) => t.toggle.name).toSet(),
        hasLength(7),
      );
      expect(NotificationType.values.map((t) => t.kind).toSet(), hasLength(7));
    });
  });
}
