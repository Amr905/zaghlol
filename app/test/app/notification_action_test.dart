// OVERDUE-REMINDERS: the "Mark as paid" action opens the bills and pays the
// occurrence it was about, once.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/notification_taps.dart';
import 'package:zaghlol/features/notifications/domain/notification_routes.dart';

void main() {
  test('the action opens Insights then pays that item and date', () {
    final went = <String>[];
    final paid = <(String, String)>[];
    openNotificationTarget(
      notificationTargetFor('/recurring/a1/paid/2026-11-10')!,
      router: went.add,
      context: null,
      markPaid: (id, due) async => paid.add((id, due)),
    );
    expect(went, hasLength(1));
    expect(paid, [('a1', '2026-11-10')]);
  });

  test('a plain item tap only opens Insights, pays nothing', () {
    final went = <String>[];
    final paid = <(String, String)>[];
    openNotificationTarget(
      notificationTargetFor('/recurring/a1')!,
      router: went.add,
      context: null,
      markPaid: (id, due) async => paid.add((id, due)),
    );
    expect(went, hasLength(1));
    expect(paid, isEmpty);
  });

  group('payAfterGate (L-1)', () {
    test('nothing is paid while the lock stays shut', () async {
      var paid = false;
      var asked = false;
      await payAfterGate(
        waitUnlocked: () async => false,
        confirm: () async {
          asked = true;
          return true;
        },
        pay: () async => paid = true,
      );
      expect(paid, isFalse);
      expect(asked, isFalse, reason: 'no dialog over a locked app');
    });

    test('the lock must open before the confirmation is shown', () async {
      final order = <String>[];
      final unlock = Completer<bool>();
      final run = payAfterGate(
        waitUnlocked: () => unlock.future,
        confirm: () async {
          order.add('confirm');
          return true;
        },
        pay: () async => order.add('pay'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      unlock.complete(true);
      await run;
      expect(order, ['confirm', 'pay']);
    });

    test('declining the confirmation pays nothing', () async {
      var paid = false;
      await payAfterGate(
        waitUnlocked: () async => true,
        confirm: () async => false,
        pay: () async => paid = true,
      );
      expect(paid, isFalse);
    });
  });
}
