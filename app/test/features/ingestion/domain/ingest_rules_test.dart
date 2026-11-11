// T-046: the pure ingest decisions (design note §3–§6, §10). Integer
// arithmetic only; boundaries are exact.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_policy.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_rules.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show TemplateDirection, TemplateEvent;

final Currency egp = Currency.of('EGP');
final Currency kwd = Currency.of('KWD');

TxnCandidate cand(
  String id, {
  int amount = 10000,
  int occurred = 0,
  int? rx,
  String source = 'sms',
  TxnStatus status = TxnStatus.posted,
  String? last4 = '4321',
}) => TxnCandidate(
  id: id,
  accountId: 'a',
  accountLast4: last4,
  source: source,
  status: status,
  direction: TxnDirection.expense,
  amount: Money(egp, amount),
  occurredAtMs: occurred,
  tzOffsetMin: 120,
  rawReceivedAtMs: rx,
  isUserVerified: false,
  isDeleted: false,
  categorySource: CategorySource.none,
);

void main() {
  group('dispositionOf (parsing-engine §6 table)', () {
    CreateTxn create(TemplateEvent e, [TemplateDirection? d]) =>
        dispositionOf(e, d ?? TemplateDirection.expense) as CreateTxn;

    test('every event has a disposition', () {
      for (final e in TemplateEvent.values) {
        for (final d in TemplateDirection.values) {
          expect(dispositionOf(e, d), isNotNull);
        }
      }
    });

    test('expense events', () {
      for (final e in [
        TemplateEvent.cardPurchase,
        TemplateEvent.cardPurchaseFx,
        TemplateEvent.atmWithdrawal,
        TemplateEvent.bnplInstallment,
        TemplateEvent.settled,
      ]) {
        final c = create(e);
        expect(
          (c.direction, c.status),
          (TxnDirection.expense, TxnStatus.posted),
        );
      }
      expect(create(TemplateEvent.pendingAuth).status, TxnStatus.pending);
      final declined = create(
        TemplateEvent.declined,
        TemplateDirection.neutral,
      );
      expect(
        (declined.direction, declined.status),
        (TxnDirection.expense, TxnStatus.declined),
      );
    });

    test('transfer-like events follow the template direction', () {
      for (final e in [
        TemplateEvent.transferOut,
        TemplateEvent.transferIn,
        TemplateEvent.instapayOut,
        TemplateEvent.instapayIn,
        TemplateEvent.ccPayment,
        TemplateEvent.walletTopup,
      ]) {
        expect(create(e).direction, TxnDirection.transferOut);
        expect(
          create(e, TemplateDirection.income).direction,
          TxnDirection.transferIn,
        );
        expect(
          dispositionOf(e, TemplateDirection.neutral),
          isA<UndirectedEvent>(),
        );
      }
    });

    test('income, refund, fee, balance, deferred', () {
      expect(create(TemplateEvent.salary).direction, TxnDirection.income);
      expect(create(TemplateEvent.refund).direction, TxnDirection.refund);
      expect(create(TemplateEvent.reversal).direction, TxnDirection.refund);
      expect(create(TemplateEvent.fee).direction, TxnDirection.fee);
      expect(
        dispositionOf(TemplateEvent.balanceOnly, TemplateDirection.neutral),
        isA<BalanceOnlyEvent>(),
      );
      expect(
        dispositionOf(TemplateEvent.fxConversion, TemplateDirection.neutral),
        isA<DeferredEvent>(),
      );
    });
  });

  group('dedupeKeyOf (T-012 F5: from Money, never text)', () {
    test('shape and exponent', () {
      expect(
        dedupeKeyOf('nbe', TxnDirection.expense, Money(egp, 12050)),
        'd1|nbe|expense|EGP|12050',
      );
      expect(
        dedupeKeyOf('nbe', TxnDirection.transferIn, Money.parse('1.5', kwd)),
        'd1|nbe|transfer_in|KWD|1500',
      );
    });

    test('equal amounts written differently give one key', () {
      expect(
        dedupeKeyOf('x', TxnDirection.expense, Money.parse('01.50', egp)),
        dedupeKeyOf('x', TxnDirection.expense, Money.parse('1.5', egp)),
      );
    });
  });

  group('last4Compatible (PO Q1, provisional)', () {
    test('equal, missing on one side, or both missing', () {
      expect(last4Compatible('1234', '1234'), isTrue);
      expect(last4Compatible('1234', '9999'), isFalse);
      expect(last4Compatible(null, '1234'), kMergeWhenLast4MissingOnOneSide);
      expect(last4Compatible('1234', null), kMergeWhenLast4MissingOnOneSide);
      expect(last4Compatible(null, null), isTrue);
    });
  });

  group('withinCrossChannelWindow', () {
    const m = 60000;
    test('minute buckets: 2 apart yes, 3 apart no', () {
      expect(
        withinCrossChannelWindow(occurredA: 0, occurredB: 2 * m + 59999),
        isTrue,
      );
      expect(withinCrossChannelWindow(occurredA: 0, occurredB: 3 * m), isFalse);
    });

    test('negative epochs bucket by floor (minute -1, not 0)', () {
      expect(
        withinCrossChannelWindow(occurredA: -1, occurredB: 2 * m - 1),
        isTrue,
      );
      expect(
        withinCrossChannelWindow(occurredA: -1, occurredB: 2 * m),
        isFalse,
      );
    });

    test('receive times rescue a wrong occurred_at (EC-10)', () {
      expect(
        withinCrossChannelWindow(
          occurredA: 0,
          occurredB: 3 * 3600000,
          receivedA: 1000,
          receivedB: 1000 + 2 * m,
        ),
        isTrue,
      );
      expect(
        withinCrossChannelWindow(
          occurredA: 0,
          occurredB: 3 * 3600000,
          receivedA: 1000,
          receivedB: 1001 + 2 * m,
        ),
        isFalse,
      );
      expect(
        withinCrossChannelWindow(
          occurredA: 0,
          occurredB: 3 * 3600000,
          receivedA: 1000,
        ),
        isFalse,
      );
    });
  });

  group('crossChannelMatches', () {
    final keys = NewTxnKeys(
      source: 'notification',
      status: TxnStatus.posted,
      occurredAtMs: 0,
      receivedAtMs: 0,
    );

    test('different source, same status class, window, last-4', () {
      final got = crossChannelMatches(keys, [
        cand('ok'),
        cand('same-source', source: 'notification'),
        cand('declined', status: TxnStatus.declined),
        cand('pending', status: TxnStatus.pending),
        cand('late', occurred: 10 * 60000),
      ]);
      expect([for (final c in got) c.id], ['ok', 'pending']);
    });

    test('declined only with declined', () {
      final got = crossChannelMatches(
        NewTxnKeys(
          source: 'notification',
          status: TxnStatus.declined,
          occurredAtMs: 0,
          receivedAtMs: 0,
        ),
        [cand('p'), cand('d', status: TxnStatus.declined)],
      );
      expect([for (final c in got) c.id], ['d']);
    });
  });

  group('pending tolerance (A-63)', () {
    test('5 % merges, 5.01 % does not (integers)', () {
      expect(withinPendingTolerance(10500, 10000), isTrue);
      expect(withinPendingTolerance(10501, 10000), isFalse);
      expect(withinPendingTolerance(9500, 10000), isTrue);
      expect(withinPendingTolerance(9499, 10000), isFalse);
    });

    test('zero or negative pending never matches', () {
      expect(withinPendingTolerance(0, 0), isFalse);
      expect(withinPendingTolerance(5, -100), isFalse);
    });

    test('no overflow at the money bound', () {
      const max = Money.maxMinor;
      expect(withinPendingTolerance(max, max), isTrue);
    });

    test('pickPendingMatch: closest, then oldest, then id', () {
      final pick = pickPendingMatch(
        newAmountMinor: 10200,
        newIsPending: false,
        candidates: [
          cand('far', amount: 10000),
          cand('b', amount: 10100, occurred: 5),
          cand('a', amount: 10300, occurred: 5),
          cand('c', amount: 10100, occurred: 1),
        ],
      );
      expect(pick!.id, 'c');
      expect(
        pickPendingMatch(
          newAmountMinor: 20000,
          newIsPending: false,
          candidates: [cand('x')],
        ),
        isNull,
      );
    });

    test('symmetric: the new pending is p', () {
      // settled 10500 stored, new pending 10000: 5 % of p → match.
      expect(
        pickPendingMatch(
          newAmountMinor: 10000,
          newIsPending: true,
          candidates: [cand('s', amount: 10500)],
        ),
        isNotNull,
      );
      // settled 10000 stored, new pending 10600: |Δ| 600 > 5 % of 10600? 530
      expect(
        pickPendingMatch(
          newAmountMinor: 10600,
          newIsPending: true,
          candidates: [cand('s', amount: 10000)],
        ),
        isNull,
      );
    });
  });

  group('cycleKeyFor (domain-algorithms §2, A-43, T-051)', () {
    int utc(int y, int mo, int d, [int h = 0, int mi = 0]) =>
        DateTime.utc(y, mo, d, h, mi).millisecondsSinceEpoch;
    String key(int ms, int off, int payday) => cycleKeyFor(
      occurredAtMs: ms,
      tzOffsetMin: off,
      schedule: PaydaySchedule.single(payday),
    );

    test('the key is the ISO start date, in local time', () {
      expect(key(utc(2026, 10, 31, 22, 30), 120, 1), '2026-11-01');
      expect(key(utc(2026, 10, 31, 21, 59), 120, 1), '2026-10-01');
    });

    test('before payday belongs to the previous month; January wraps', () {
      expect(key(utc(2027, 1, 24), 0, 25), '2026-12-25');
      expect(key(utc(2027, 1, 25), 0, 25), '2027-01-25');
    });

    test('payday 28 at month ends and February', () {
      expect(key(utc(2026, 2, 27), 0, 28), '2026-01-28');
      expect(key(utc(2026, 3, 31), 0, 28), '2026-03-28');
    });

    test('keys do not collide after a payday change (EC-21)', () {
      final s = PaydaySchedule.single(25)
          .withChange(CivilDate(2026, 11, 10), 1);
      String k(int d) => cycleKeyFor(
        occurredAtMs: utc(2026, 11, d),
        tzOffsetMin: 0,
        schedule: s,
      );
      expect(k(9), '2026-10-25');
      expect(k(30), '2026-10-25');
      expect(
        cycleKeyFor(
          occurredAtMs: utc(2026, 12, 1),
          tzOffsetMin: 0,
          schedule: s,
        ),
        '2026-12-01',
      );
    });

    test('paydayDayOf: out-of-range or unreadable payday is 1', () {
      expect(paydayDayOf(null), 1);
      expect(paydayDayOf('25'), 25);
      expect(paydayDayOf('31'), 1);
      expect(paydayDayOf('0'), 1);
      expect(paydayDayOf('abc'), 1);
    });
  });

  test('clampTzOffset keeps the schema range', () {
    expect(clampTzOffset(2000), 1080);
    expect(clampTzOffset(-2000), -1080);
    expect(clampTzOffset(180), 180);
  });

  test('txnSourceOf maps every raw channel the schema accepts', () {
    for (final c in [
      'sms',
      'notification',
      'shortcut_message',
      'apple_pay',
      'share',
      'paste',
      'ocr',
      'pdf',
      'csv',
    ]) {
      expect(txnSourceOf(c), isNotNull, reason: c);
    }
    expect(txnSourceOf('carrier_pigeon'), isNull);
  });
}
