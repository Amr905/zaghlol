import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/mascot/application/payday_celebration.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

SalaryEntry _e(CivilDate a, {bool captured = true}) =>
    SalaryEntry(txnId: 't${a.epochDay}', captured: captured, anchor: a);

void main() {
  final today = CivilDate(2026, 11, 25);

  test('latest captured payday ignores hand-entered rows', () {
    final s = SalaryState(
      entries: [
        _e(CivilDate(2026, 10, 25)),
        _e(CivilDate(2026, 11, 25), captured: false),
      ],
    );
    expect(latestCapturedPayday(s), CivilDate(2026, 10, 25));
    expect(latestCapturedPayday(SalaryState.empty), isNull);
  });

  test('fresh salary, never celebrated: celebrate', () {
    expect(
      paydayVerdict(latest: today, lastCelebrated: null, today: today),
      PaydayVerdict.celebrate,
    );
  });

  test('same payday twice: only once (survives restart via stored mark)', () {
    expect(
      paydayVerdict(
        latest: today,
        lastCelebrated: today.epochDay,
        today: today,
      ),
      PaydayVerdict.nothing,
    );
  });

  test('next cycle celebrates again', () {
    final next = CivilDate(2026, 12, 25);
    expect(
      paydayVerdict(latest: next, lastCelebrated: today.epochDay, today: next),
      PaydayVerdict.celebrate,
    );
  });

  test('old salary from a first historical import never celebrates', () {
    expect(
      paydayVerdict(
        latest: CivilDate(2026, 8, 25),
        lastCelebrated: null,
        today: today,
      ),
      PaydayVerdict.markSilently,
    );
  });

  test('no salary: nothing', () {
    expect(
      paydayVerdict(latest: null, lastCelebrated: null, today: today),
      PaydayVerdict.nothing,
    );
  });
}
