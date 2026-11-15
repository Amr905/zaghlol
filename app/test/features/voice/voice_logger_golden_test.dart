@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/golden_matrix.dart';
import 'voice_harness.dart';

const phrase = 'دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي';

void main() {
  for (final v in goldenVariants) {
    testWidgets('voice logger parsed golden ${v.name}', (tester) async {
      final r = VoiceRig();
      await r.pump(tester, locale: v.locale, dark: v.dark);
      r.speech.say(phrase);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('voice-done')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/voice_logger_parsed_${v.name}.png'),
      );
    });

    testWidgets('voice logger listening golden ${v.name}', (tester) async {
      final r = VoiceRig();
      await r.pump(tester, locale: v.locale, dark: v.dark);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/voice_logger_listening_${v.name}.png'),
      );
    });
  }
}
