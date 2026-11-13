import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  group('budgetShocked', () {
    MascotCandidate? s(int spent, {int day = 10, String cat = 'dining'}) =>
        budgetShocked(
          categoryId: cat,
          spentMinor: spent,
          limitMinor: 10000,
          dayOfCycle: day,
          cycleId: 'c1',
        );
    test('dining > 85% before day 20 fires', () {
      expect(s(8501)?.pose, MascotPose.shocked);
    });
    test('exactly 85%, day 20, zero limit do not', () {
      expect(s(8500), isNull);
      expect(s(9000, day: 20), isNull);
      expect(s(9000, day: 19), isNotNull);
      expect(
        budgetShocked(
          categoryId: 'dining',
          spentMinor: 5,
          limitMinor: 0,
          dayOfCycle: 1,
          cycleId: 'c',
        ),
        isNull,
      );
    });
    test('essential categories are never roasted (Q-25)', () {
      for (final c in defaultEssentialCategoryIds) {
        expect(s(99999, cat: c), isNull);
      }
    });
  });

  group('diningSpike', () {
    test('> 30% above 3-cycle average', () {
      expect(
        diningSpike(
          categoryId: 'dining',
          spentMinor: 13001,
          previousCyclesMinor: [10000, 10000, 10000],
          cycleId: 'c',
        )?.pose,
        MascotPose.shocked,
      );
      expect(
        diningSpike(
          categoryId: 'dining',
          spentMinor: 13000,
          previousCyclesMinor: [10000, 10000, 10000],
          cycleId: 'c',
        ),
        isNull,
      );
    });
    test('needs 3 cycles; essential skipped', () {
      expect(
        diningSpike(
          categoryId: 'dining',
          spentMinor: 99999,
          previousCyclesMinor: [1, 1],
          cycleId: 'c',
        ),
        isNull,
      );
      expect(
        diningSpike(
          categoryId: 'groceries',
          spentMinor: 99999,
          previousCyclesMinor: [1, 1, 1],
          cycleId: 'c',
        ),
        isNull,
      );
    });
  });

  group('duplicatePos', () {
    PosDebit d(int at, {int amt = 5000, String cur = 'EGP', String m = 'm'}) =>
        PosDebit(
          merchantId: m,
          cardId: 'k',
          currency: cur,
          amountMinor: amt,
          atUtcMs: at,
        );
    test('within 10 minutes fires, after does not', () {
      expect(duplicatePos(d(600000), [d(0)])?.pose, MascotPose.detective);
      expect(duplicatePos(d(600001), [d(0)]), isNull);
    });
    test('different amount, currency or merchant does not', () {
      expect(duplicatePos(d(1000), [d(0, amt: 1)]), isNull);
      expect(duplicatePos(d(1000), [d(0, cur: 'USD')]), isNull);
      expect(duplicatePos(d(1000), [d(0, m: 'x')]), isNull);
    });
  });

  group('proud', () {
    test('goal, under burn line, over burn line', () {
      expect(
        proud(
          cycleId: 'c',
          spentMinor: 9,
          idealBurnMinor: 5,
          metGoalId: 'g',
        )?.id,
        'proud:goal:g:c',
      );
      expect(proud(cycleId: 'c', spentMinor: 4, idealBurnMinor: 5), isNotNull);
      expect(proud(cycleId: 'c', spentMinor: 5, idealBurnMinor: 5), isNull);
    });
  });

  group('decideMascot', () {
    final shocked = budgetShocked(
      categoryId: 'dining',
      spentMinor: 9000,
      limitMinor: 10000,
      dayOfCycle: 5,
      cycleId: 'c',
    )!;
    final det = selfTransferPaired('p1');
    final pr = proud(cycleId: 'c', spentMinor: 1, idealBurnMinor: 5)!;
    MascotDecision? run(
      List<MascotCandidate> c, {
      MascotMemory m = const MascotMemory(),
      bool rm = false,
      int now = 1000000,
    }) =>
        decideMascot(candidates: c, memory: m, nowUtcMs: now, reduceMotion: rm);

    test('priority shocked > detective > proud > tourGuide, one only', () {
      expect(run([tourGuideHello, pr, det, shocked])!.candidate, shocked);
      expect(run([tourGuideHello, pr, det])!.candidate, det);
      expect(run([tourGuideHello, pr])!.candidate, pr);
      expect(run([tourGuideHello])!.candidate, tourGuideHello);
      expect(run([]), isNull);
    });
    test('once per cycle and dismissal memory', () {
      expect(run([shocked], m: MascotMemory(shownIds: {shocked.id})), isNull);
      expect(
        run([shocked], m: MascotMemory(dismissedIds: {shocked.id})),
        isNull,
      );
      expect(
        run([shocked, det], m: MascotMemory(shownIds: {shocked.id}))!.candidate,
        det,
      );
      // New cycle gives a new id.
      expect(shocked.id, isNot(contains('c2')));
    });
    test('rate limit', () {
      final m = MascotMemory(lastShownUtcMs: 1000000 - 59999);
      expect(run([shocked], m: m), isNull);
      expect(
        run([shocked], m: MascotMemory(lastShownUtcMs: 1000000 - 60000)),
        isNotNull,
      );
    });
    test('reduce motion yields still-only', () {
      expect(run([shocked], rm: true)!.stillOnly, isTrue);
      expect(run([shocked])!.stillOnly, isFalse);
    });
  });
}
