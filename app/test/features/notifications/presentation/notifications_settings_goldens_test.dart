@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/notifications/application/notification_providers.dart';
import 'package:zaghlol/features/notifications/presentation/notifications_settings_screen.dart';

import '../../../support/golden_matrix.dart';
import '../../settings/settings_harness.dart';
import 'notifications_settings_screen_test.dart' show PermStub;

void main() {
  for (final v in goldenVariants) {
    testWidgets('notifications settings ${v.name}', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      await tester.pumpWidget(
        h.app(
          const NotificationsSettingsScreen(),
          locale: v.locale,
          dark: v.dark,
          overrides: [
            notificationPermissionProvider.overrideWithValue(
              PermStub(allowed: false),
            ),
          ],
        ),
      );
      await settle(tester);
      await expectLater(
        find.byType(NotificationsSettingsScreen),
        matchesGoldenFile('goldens/notifications_settings_${v.name}.png'),
      );
    });
  }
}
