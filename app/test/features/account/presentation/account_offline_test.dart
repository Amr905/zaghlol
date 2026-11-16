// Explorer finding: S-69 while the backend is unreachable. status() throws
// BackendFailure(offline); the screen must still show the sign-in buttons.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';

import 'account_screen_test.dart';

Future<void> main() async {
  await initDateFormatting();
  for (final lang in ['en', 'ar']) {
    final t = tr(lang);
    testWidgets('S-69 $lang: backend offline still shows the sign-in buttons', (
      tester,
    ) async {
      await pumpAccount(tester, FakeAccountActions()..offline = true, lang);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(t.goldAccountGoogle), findsOneWidget);
      expect(find.text(t.goldAccountApple), findsOneWidget);
    });
  }
}
