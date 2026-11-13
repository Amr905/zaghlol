// T-090: refund matching rules, synthetic data only.
import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final kwd = Currency.of('KWD');
const int day = 86400000;
final t0 = DateTime.utc(2026, 11, 20, 10).millisecondsSinceEpoch;

RefundFact refund(
  int minor, {
  Currency? cur,
  String? merchant = 'acme',
  String acc = 'a1',
  int at = 0,
  int off = 120,
}) => RefundFact(
  id: 'r',
  accountId: acc,
  merchantNorm: merchant,
  amount: Money(cur ?? egp, minor),
  occurredAtMs: t0 + at,
  offsetMin: off,
);

OffsetCandidate exp(
  String id,
  int remaining, {
  Currency? cur,
  String? merchant = 'acme',
  String acc = 'a1',
  int at = -day,
  int off = 120,
}) => OffsetCandidate(
  id: id,
  accountId: acc,
  merchantNorm: merchant,
  remaining: Money(cur ?? egp, remaining),
  occurredAtMs: t0 + at,
  offsetMin: off,
);

void main() {
  test('partial refund links only the refund amount', () {
    final d = decideRefund(refund(3000), [exp('e', 10000)]);
    expect(d, isA<LinkRefund>());
    d as LinkRefund;
    expect(d.expenseId, 'e');
    expect(d.linked.minor, 3000);
    expect(d.incomeRemainder.minor, 0);
  });

  test('refund larger than the expense: remainder is income (EC-17)', () {
    final d = decideRefund(refund(12000), [exp('e', 10000)]) as LinkRefund;
    expect(d.linked.minor, 10000);
    expect(d.incomeRemainder.minor, 2000);
  });

  test('exact refund fully offsets, no remainder', () {
    final d = decideRefund(refund(10000), [exp('e', 10000)]) as LinkRefund;
    expect(d.linked.minor, 10000);
    expect(d.incomeRemainder.minor, 0);
  });

  test('most recent expense that can absorb the refund wins', () {
    final d = decideRefund(refund(5000), [
      exp('old', 9000, at: -5 * day),
      exp('new', 9000, at: -day),
      exp('small', 1000, at: -day ~/ 2),
    ]) as LinkRefund;
    expect(d.expenseId, 'new');
  });

  test('a newer expense too small is skipped when an older one fits', () {
    final d = decideRefund(refund(5000), [
      exp('old', 9000, at: -5 * day),
      exp('small', 1000, at: -day),
    ]) as LinkRefund;
    expect(d.expenseId, 'old');
    expect(d.incomeRemainder.minor, 0);
  });

  test('oversized for all: most recent takes what it can', () {
    final d = decideRefund(refund(9000), [
      exp('old', 2000, at: -5 * day),
      exp('new', 3000, at: -day),
    ]) as LinkRefund;
    expect(d.expenseId, 'new');
    expect(d.linked.minor, 3000);
    expect(d.incomeRemainder.minor, 6000);
  });

  test('same instant: ambiguous, never linked', () {
    final d = decideRefund(refund(1000), [exp('b', 5000), exp('a', 5000)]);
    expect(d, isA<AmbiguousRefund>());
    expect((d as AmbiguousRefund).candidateIds, ['a', 'b']);
  });

  test('60-day window: day 60 matches, day 61 does not (local date)', () {
    expect(
      decideRefund(refund(1000), [exp('e', 5000, at: -60 * day)]),
      isA<LinkRefund>(),
    );
    expect(
      decideRefund(refund(1000), [exp('e', 5000, at: -61 * day)]),
      isA<NoRefundMatch>(),
    );
  });

  test('window uses local dates across midnight', () {
    // Refund 00:30 local (UTC+2) = 22:30Z the day before.
    final r = refund(1000, at: -day + 12 * 3600000 + 30 * 60000);
    // Expense later the same local day is still in the window.
    final e = exp('e', 5000, at: r.occurredAtMs - t0 - 60000);
    expect(decideRefund(r, [e]), isA<LinkRefund>());
  });

  test('expense dated after the refund day never matches', () {
    expect(
      decideRefund(refund(1000), [exp('e', 5000, at: 2 * day)]),
      isA<NoRefundMatch>(),
    );
  });

  test('other merchant, other account, other currency: no match', () {
    expect(
      decideRefund(refund(1000), [exp('e', 5000, merchant: 'zed')]),
      isA<NoRefundMatch>(),
    );
    expect(
      decideRefund(refund(1000), [exp('e', 5000, acc: 'a2')]),
      isA<NoRefundMatch>(),
    );
    expect(
      decideRefund(refund(1000), [exp('e', 5000, cur: usd)]),
      isA<NoRefundMatch>(),
    );
  });

  test('null or empty merchant never matches', () {
    expect(
      decideRefund(refund(1000, merchant: null), [exp('e', 5000)]),
      isA<NoRefundMatch>(),
    );
    expect(
      decideRefund(refund(1000, merchant: ''), [exp('e', 5000, merchant: '')]),
      isA<NoRefundMatch>(),
    );
  });

  test('fully offset (remaining zero) is skipped; zero refund no match', () {
    expect(decideRefund(refund(1000), [exp('e', 0)]), isA<NoRefundMatch>());
    expect(decideRefund(refund(0), [exp('e', 5000)]), isA<NoRefundMatch>());
  });

  test('three-decimal currency keeps exact minor units', () {
    final d = decideRefund(refund(1250, cur: kwd), [
      exp('e', 1000, cur: kwd),
    ]) as LinkRefund;
    expect(d.linked.minor, 1000);
    expect(d.incomeRemainder, Money(kwd, 250));
  });
}
