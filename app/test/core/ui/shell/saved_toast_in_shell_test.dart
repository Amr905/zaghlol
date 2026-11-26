import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/ui/shell/app_shell.dart';
import 'package:zaghlol/core/ui/z_saved_toast.dart';

import 'shell_harness.dart';

void main() {
  // Batch 83 major: the toast must sit above the bar and the raised Add circle.
  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    testWidgets(
      'Saved toast clears the bar and Add button (${locale.languageCode})',
      (tester) async {
        await pumpShell(tester, locale: locale);
        final ctx = tester.element(find.byType(ZBottomBar));
        showSavedToast(ScaffoldMessenger.of(ctx), AppLocalizations.of(ctx));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final toast = tester.getRect(
          find
              .descendant(
                of: find.byKey(const ValueKey('savedToast')),
                matching: find.byType(Material),
              )
              .first,
        );
        final add = tester.getRect(find.byType(ZAddButton));
        final bar = tester.getRect(find.byType(ZBottomBar));
        expect(toast.overlaps(add), isFalse);
        expect(toast.overlaps(bar), isFalse);
        expect(toast.bottom, lessThanOrEqualTo(add.top));
      },
    );
  }
}
