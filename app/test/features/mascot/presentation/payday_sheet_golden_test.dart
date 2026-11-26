@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol/features/mascot/presentation/payday_sheet.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/golden_matrix.dart';
import 'payday_sheet_test.dart' show host;

void main() {
  for (final v in goldenVariants) {
    testWidgets('payday_sheet ${v.name}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          // No Rive in widget tests: the still pose stands in for the artboard.
          overrides: [
            zaghlolArtboardProvider.overrideWithValue(
              (context, moment, talk, size) => Image.asset(
                ZaghlolAvatar.stillAsset,
                width: size,
                height: size,
                fit: BoxFit.contain,
              ),
            ),
          ],
          child: host(
            v.locale,
            dark: v.dark,
            scale: 1.0,
            perDay: Money(Currency.of('EGP'), 99000),
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PaydaySheet(
                salary: PaydayCelebration(
                  's1',
                  Money(Currency.of('EGP'), 2970000),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.pump();
        await precacheImage(
          const AssetImage(ZaghlolAvatar.stillAsset),
          tester.element(find.byType(PaydaySheet)),
        );
      });
      // End of the coin fall so the frame is the same every run.
      await tester.pump(kPaydayCoinsDuration + const Duration(seconds: 1));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../../goldens/payday_sheet_${v.name}.png'),
      );
    });
  }
}
