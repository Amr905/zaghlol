// OVERDUE-REMINDERS: the "Mark as paid" action opens the bills and pays the
// occurrence it was about, once.

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
}
