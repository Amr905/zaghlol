import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// FU (batch-29 T-070 minor): the wallet card name for Contact must carry a
// finance cue; a bare "contact" matched unrelated cards ("Contactless Visa").
void main() {
  final guard = CaptureGuard(
    parseGuardConfig(
      File('../../app/assets/guard/guard_base.json').readAsBytesSync(),
    ).config!,
  );
  GuardDecision wallet(String card) =>
      guard.decide(channel: 'apple_pay', source: card, body: 'EGP 10.00');

  test('an unrelated card name containing "contact" is not Contact', () {
    for (final n in ['Contactless Visa', 'My Contacts Card']) {
      final d = wallet(n);
      expect(d is GuardKeep && d.inst == 'contact', isFalse, reason: n);
    }
  });
  test('a Contact Financial/Credit card still resolves', () {
    for (final n in ['Contact Financial Card', 'Contact Credit']) {
      final d = wallet(n);
      expect(d, isA<GuardKeep>(), reason: n);
      expect((d as GuardKeep).inst, 'contact');
    }
  });
}
