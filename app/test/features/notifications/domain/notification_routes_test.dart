import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/domain/notification_routes.dart';

void main() {
  test('known route ids map to their targets', () {
    expect(notificationTargetFor('/budget'), isA<InsightsTarget>());
    expect(notificationTargetFor('/home'), isA<HomeTarget>());
    expect(notificationTargetFor('/insights'), isA<InsightsTarget>());
    expect(notificationTargetFor('/settings/backup'), isA<BackupTarget>());
    final t = notificationTargetFor('/transactions/ab-12_Z');
    expect(t, isA<TransactionTarget>());
    expect((t! as TransactionTarget).id, 'ab-12_Z');
  });

  test('recurring routes: the item opens Insights, the action pays', () {
    expect(notificationTargetFor('/recurring/a1'), isA<InsightsTarget>());
    final t = notificationTargetFor('/recurring/a1/paid/2026-11-10');
    expect(t, isA<MarkPaidTarget>());
    expect((t! as MarkPaidTarget).id, 'a1');
    expect((t as MarkPaidTarget).dueDate, '2026-11-10');
    for (final r in [
      '/recurring/',
      '/recurring/a1/paid',
      '/recurring/a1/paid/tomorrow',
      '/recurring/a1/delete/2026-11-10',
      '/recurring/a b/paid/2026-11-10',
      '/recurring/a1/paid/2026-11-10/x',
    ]) {
      expect(notificationTargetFor(r), isNull, reason: r);
    }
  });

  test('anything else opens nothing', () {
    for (final r in [
      null,
      '',
      'budget',
      'https://example.com',
      'zaghlol://budget',
      '/transactions/',
      '/transactions/a b',
      '/transactions/../x',
      '/transactions/${'a' * 80}',
      '/unknown',
    ]) {
      expect(notificationTargetFor(r), isNull, reason: '$r');
    }
  });
}
