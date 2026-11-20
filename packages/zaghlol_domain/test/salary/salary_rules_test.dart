// T-195: domain rules for a salary entered by hand and/or received by SMS.
// Synthetic data only.

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

Money m(int minor, [Currency? c]) => Money(c ?? egp, minor);
CivilDate d(int y, int mo, int day) => CivilDate(y, mo, day);

SalaryCandidate credit(
  int minor,
  CivilDate date, {
  Currency? currency,
  bool keyword = false,
}) =>
    SalaryCandidate(amount: m(minor, currency), localDate: date, keyword: keyword);

SalaryPlan plan({int minor = 1000000, int day = 25, Currency? c}) =>
    SalaryPlan.tryCreate(amount: m(minor, c), day: day)!;

SalaryDecision decide(
  SalaryCandidate c, {
  SalaryPlan? p,
  SalaryState state = SalaryState.empty,
  List<SalaryEntry> manual = const [],
  List<LiveSalaryTxn> manualTxns = const [],
  bool Function(CivilDate)? closed,
  String id = 'sms1',
}) => decideSalaryCandidate(
  creditTxnId: id,
  credit: c,
  plan: p,
  state: state,
  liveManual: manual,
  liveManualTxns: manualTxns,
  paydayClosed: closed ?? (_) => false,
);

void main() {
  group('plan', () {
    test('validation and json round trip', () {
      expect(SalaryPlan.tryCreate(amount: m(0), day: 25), isNull);
      expect(SalaryPlan.tryCreate(amount: m(5), day: 0), isNull);
      expect(SalaryPlan.tryCreate(amount: m(5), day: 29), isNull);
      expect(
        SalaryPlan.tryCreate(amount: m(5), day: 5, accountId: 'a b'),
        isNull,
      );
      final p = SalaryPlan.tryCreate(
        amount: Money(Currency.of('KWD'), 1234567),
        day: 28,
        accountId: 'acc-1',
      )!;
      expect(SalaryPlan.tryFromJson(p.toJson()), p);
      expect(SalaryPlan.tryFromJson('nope'), isNull);
      expect(SalaryPlan.tryFromJson('{"v":2}'), isNull);
      expect(SalaryPlan.tryFromJson('{"v":1,"m":-5,"c":"EGP","d":5}'), isNull);
      expect(SalaryPlan.tryFromJson('{"v":1,"m":5,"c":"egp","d":5}'), isNull);
    });
  });

  group('window', () {
    test('payday -3 .. +5 inclusive, month and year boundaries', () {
      final p = d(2026, 11, 25);
      expect(salaryInWindow(p, d(2026, 11, 22)), isTrue);
      expect(salaryInWindow(p, d(2026, 11, 21)), isFalse);
      expect(salaryInWindow(p, d(2026, 11, 30)), isTrue);
      expect(salaryInWindow(p, d(2026, 12, 1)), isFalse);
      // Payday 1 with an arrival on the last days of the month before.
      expect(salaryPaydayFor(d(2026, 11, 29), 1), d(2026, 12, 1));
      expect(salaryPaydayFor(d(2026, 11, 28), 1), d(2026, 12, 1));
      expect(salaryPaydayFor(d(2026, 11, 27), 1), isNull);
      expect(salaryPaydayFor(d(2027, 1, 4), 1), d(2027, 1, 1));
      expect(salaryPaydayFor(d(2026, 12, 31), 1), d(2027, 1, 1));
      expect(salaryPaydayFor(d(2026, 1, 3), 28), isNull);
      expect(salaryPaydayFor(d(2025, 12, 31), 28), d(2025, 12, 28));
    });

    test('latest and next payday', () {
      expect(salaryLatestPayday(d(2026, 11, 25), 25), d(2026, 11, 25));
      expect(salaryLatestPayday(d(2026, 11, 24), 25), d(2026, 10, 25));
      expect(salaryLatestPayday(d(2026, 1, 3), 5), d(2025, 12, 5));
      expect(salaryNextPayday(d(2026, 12, 25), 25), d(2027, 1, 25));
    });
  });

  group('amount and keyword', () {
    test('within 15 percent, integers, same currency only', () {
      expect(salaryAmountClose(m(1000), m(1150)), isTrue);
      expect(salaryAmountClose(m(1000), m(850)), isTrue);
      expect(salaryAmountClose(m(1000), m(1151)), isFalse);
      expect(salaryAmountClose(m(1000), m(849)), isFalse);
      expect(salaryAmountClose(m(1000), m(1000, usd)), isFalse);
      expect(salaryAmountClose(m(0), m(0)), isFalse);
      expect(salaryAmountClose(m(Money.maxMinor), m(Money.maxMinor)), isTrue);
    });

    test('keywords in English and Arabic', () {
      expect(salaryLooksLikeSalary(['Salary Nov']), isTrue);
      expect(salaryLooksLikeSalary([null, 'PAYROLL CO']), isTrue);
      expect(salaryLooksLikeSalary(['مرتب شهر 11']), isTrue);
      expect(salaryLooksLikeSalary(['راتب']), isTrue);
      expect(salaryLooksLikeSalary(['كاش باك', 'refund']), isFalse);
      expect(salaryLooksLikeSalary(const []), isFalse);
    });
  });

  group('state', () {
    test('json round trip, pruning and tolerant reading', () {
      var s = SalaryState.empty;
      for (var i = 0; i < 12; i++) {
        s = s.withEntry(
          SalaryEntry(
            txnId: 't$i',
            captured: i.isEven,
            anchor: d(2026, 1, 1).plusDays(i),
          ),
        );
      }
      expect(s.entries.length, salaryMaxEntries);
      expect(s.entries.first.txnId, 't4');
      s = s.withSkipped(d(2026, 3, 1)).withSkipped(d(2026, 3, 1));
      expect(s.skipped, [d(2026, 3, 1)]);
      s = s.withDeclined('x');
      final back = SalaryState.fromJson(s.toJson());
      expect(back.entries.length, salaryMaxEntries);
      expect(back.skipped, s.skipped);
      expect(back.declined, ['x']);
      for (final bad in ['', 'nope', '{"v":9}', '[]', null]) {
        expect(SalaryState.fromJson(bad).entries, isEmpty);
      }
      final withMerge = SalaryState.empty.withEntry(
        SalaryEntry(
          txnId: 'a',
          captured: true,
          anchor: d(2026, 11, 25),
        ).withMerged('b', m(5)),
      );
      final e = SalaryState.fromJson(withMerge.toJson()).entries.single;
      expect(e.mergedTxnId, 'b');
      expect(e.mergedAmount, m(5));
      expect(e.withoutMerged().mergedTxnId, isNull);
    });
  });

  group('decision: SMS against the expected item', () {
    final p = plan();
    test('tags the credit and names the payday', () {
      final r = decide(credit(1000000, d(2026, 11, 25)), p: p);
      expect(r, isA<SalaryTagExpected>());
      expect((r as SalaryTagExpected).payday, d(2026, 11, 25));
    });

    test('amount drift: inside 15 percent matches, outside does not', () {
      expect(
        decide(credit(1100000, d(2026, 11, 25)), p: p),
        isA<SalaryTagExpected>(),
      );
      expect(decide(credit(1200000, d(2026, 11, 25)), p: p), isA<SalaryNone>());
      // A raise the description names still matches.
      expect(
        decide(credit(1200000, d(2026, 11, 25), keyword: true), p: p),
        isA<SalaryTagExpected>(),
      );
    });

    test('early and late payday: edges in, one day outside is out', () {
      for (final (date, ok) in [
        (d(2026, 11, 21), false),
        (d(2026, 11, 22), true),
        (d(2026, 11, 30), true),
        (d(2026, 12, 1), false),
      ]) {
        expect(
          decide(credit(1000000, date), p: p) is SalaryTagExpected,
          ok,
          reason: '$date',
        );
      }
    });

    test('two currencies: a USD credit never matches an EGP plan', () {
      expect(
        decide(
          credit(1000000, d(2026, 11, 25), currency: usd, keyword: true),
          p: p,
        ),
        isA<SalaryNone>(),
      );
      final usdPlan = plan(c: usd);
      expect(
        decide(credit(1000000, d(2026, 11, 25)), p: usdPlan),
        isA<SalaryNone>(),
      );
      expect(
        decide(credit(1000000, d(2026, 11, 25), currency: usd), p: usdPlan),
        isA<SalaryTagExpected>(),
      );
    });

    test('closed, skipped, declined, already tied, no plan: nothing', () {
      final c = credit(1000000, d(2026, 11, 25));
      expect(decide(c, p: p, closed: (_) => true), isA<SalaryNone>());
      expect(
        decide(c, p: p, state: SalaryState.empty.withSkipped(d(2026, 11, 25))),
        isA<SalaryNone>(),
      );
      expect(
        decide(c, p: p, state: SalaryState.empty.withDeclined('sms1')),
        isA<SalaryNone>(),
      );
      expect(
        decide(
          c,
          p: p,
          state: SalaryState.empty.withEntry(
            SalaryEntry(txnId: 'sms1', captured: true, anchor: d(2026, 11, 25)),
          ),
        ),
        isA<SalaryNone>(),
      );
      expect(decide(c), isA<SalaryNone>());
    });
  });

  group('decision: SMS against a manual entry', () {
    final entry = SalaryEntry(
      txnId: 'man1',
      captured: false,
      anchor: d(2026, 11, 25),
    );
    final txns = [LiveSalaryTxn('man1', m(1000000))];

    test('merges into the manual one, with or without a plan', () {
      for (final p in [null, plan()]) {
        final r = decide(
          credit(1000000, d(2026, 11, 26)),
          p: p,
          manual: [entry],
          manualTxns: txns,
        );
        expect(r, isA<SalaryMergeManual>(), reason: '$p');
        expect((r as SalaryMergeManual).entry.txnId, 'man1');
      }
    });

    test('a one-off manual entry outside any plan window still matches', () {
      final oneOff = SalaryEntry(
        txnId: 'man1',
        captured: false,
        anchor: d(2026, 11, 10),
      );
      expect(
        decide(
          credit(1000000, d(2026, 11, 14)),
          p: plan(),
          manual: [oneOff],
          manualTxns: txns,
        ),
        isA<SalaryMergeManual>(),
      );
    });

    test('other currency, far date, far amount: not merged', () {
      for (final c in [
        credit(1000000, d(2026, 11, 26), currency: usd, keyword: true),
        credit(1000000, d(2026, 12, 2)),
        credit(500000, d(2026, 11, 26)),
      ]) {
        expect(decide(c, manual: [entry], manualTxns: txns), isA<SalaryNone>());
      }
    });

    test('two manual entries in reach: doubt, nothing merges', () {
      final second = SalaryEntry(
        txnId: 'man2',
        captured: false,
        anchor: d(2026, 11, 26),
      );
      expect(
        decide(
          credit(1000000, d(2026, 11, 27)),
          manual: [entry, second],
          manualTxns: [...txns, LiveSalaryTxn('man2', m(1000000))],
        ),
        isA<SalaryNone>(),
      );
    });

    test('an entry whose transaction is not live is ignored', () {
      expect(
        decide(credit(1000000, d(2026, 11, 26)), manual: [entry]),
        isA<SalaryNone>(),
      );
    });
  });

  group('open payday and nudge', () {
    final p = plan();
    test('open from payday to the next window', () {
      bool no(CivilDate _) => false;
      CivilDate? open(CivilDate today, {bool Function(CivilDate)? c}) =>
          salaryOpenPayday(
            plan: p,
            state: SalaryState.empty,
            today: today,
            paydayClosed: c ?? no,
          );
      expect(open(d(2026, 11, 21)), d(2026, 10, 25));
      expect(open(d(2026, 11, 22)), isNull);
      expect(open(d(2026, 11, 25)), d(2026, 11, 25));
      expect(open(d(2026, 12, 21)), d(2026, 11, 25));
      expect(open(d(2026, 12, 22)), isNull);
      expect(open(d(2026, 11, 25), c: (_) => true), isNull);
      expect(
        salaryOpenPayday(
          plan: p,
          state: SalaryState.empty.withSkipped(d(2026, 11, 25)),
          today: d(2026, 11, 26),
          paydayClosed: no,
        ),
        isNull,
      );
    });

    test('nudge once the window is over and not stale', () {
      final pay = d(2026, 11, 25);
      expect(salaryNudgeDue(pay, d(2026, 11, 30)), isFalse);
      expect(salaryNudgeDue(pay, d(2026, 12, 1)), isTrue);
      expect(salaryNudgeDue(pay, d(2026, 12, 15)), isTrue);
      expect(salaryNudgeDue(pay, d(2026, 12, 16)), isFalse);
    });
  });
}
