import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/domain/notification_routes.dart';

void main() {
  test('known route ids map to their targets', () {
    expect(notificationTargetFor('/budget'), isA<InsightsTarget>());
    expect(notificationTargetFor('/insights'), isA<InsightsTarget>());
    expect(notificationTargetFor('/settings/backup'), isA<BackupTarget>());
    final t = notificationTargetFor('/transactions/ab-12_Z');
    expect(t, isA<TransactionTarget>());
    expect((t! as TransactionTarget).id, 'ab-12_Z');
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
