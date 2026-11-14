// T-110: the roast fact picker (FR-CHAT-04): deterministic, prefers a kind
// the user has not just seen, and `calm` only when nothing else exists.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ask/domain/ask_models.dart';
import 'package:zaghlol/features/ask/domain/roast_picker.dart';

void main() {
  const a = RoastFact(RoastKind.topCategory);
  const b = RoastFact(RoastKind.biggestExpense);
  const calm = RoastFact(RoastKind.calm);

  test('same seed, same pick; the seed moves the pick', () {
    expect(pickRoastFact([b, a, calm], 0).kind, RoastKind.topCategory);
    expect(pickRoastFact([calm, b, a], 0).kind, RoastKind.topCategory);
    expect(pickRoastFact([a, b, calm], 1).kind, RoastKind.biggestExpense);
    expect(pickRoastFact([a, b, calm], 2).kind, RoastKind.topCategory);
    expect(pickRoastFact([a, b, calm], -1).kind, RoastKind.biggestExpense);
  });

  test('a kind seen lately is skipped while another exists', () {
    expect(
      pickRoastFact([a, b, calm], 0, recent: {RoastKind.topCategory}).kind,
      RoastKind.biggestExpense,
    );
    // Everything real was just seen: repeat rather than go calm.
    expect(
      pickRoastFact(
        [a, b, calm],
        0,
        recent: {RoastKind.topCategory, RoastKind.biggestExpense},
      ).kind,
      RoastKind.topCategory,
    );
  });

  test('calm only when it is all there is; empty list is calm', () {
    expect(pickRoastFact([calm], 5).kind, RoastKind.calm);
    expect(pickRoastFact(const [], 5).kind, RoastKind.calm);
  });
}
