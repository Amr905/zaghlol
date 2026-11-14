@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_matrix.dart';
import '../../../support/ios_setup_host.dart';

void main() {
  for (final v in goldenVariants) {
    for (final step in ['add', 'check', 'check_fix', 'first']) {
      testWidgets('ios setup $step golden ${v.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          iosSetupHost(
            v.locale.languageCode,
            dark: v.dark,
            scale: v.textScale,
            rootKey: const ValueKey('golden-root'),
            reportFn: () => step == 'check_fix'
                ? report(
                    message: kNow - 10 * kDayMs,
                    wallet: kNow - 3600000,
                    baseline: kNow - 30 * kDayMs,
                  )
                : healthy(),
          ),
        );
        await t.pumpAndSettle();
        if (step != 'add') {
          await t.tap(find.byKey(const ValueKey('ios-setup-to-check')));
          await t.pumpAndSettle();
        }
        if (step == 'first') {
          await t.tap(find.byKey(const ValueKey('ios-setup-to-first')));
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('goldens/ios_setup_${step}_${v.name}.png'),
        );
      });
    }
  }
}
