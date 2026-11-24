import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scenario_expected.dart';

void main() {
  final s = Scenario.parse(
    File('test/fixtures/sms/scenarios/month_story.json').readAsStringSync(),
  );
  final now = DateTime(2026, 11, 24, 10);
  final m1 = monthOf(now, 1);

  test('the scenario is well formed', () {
    expect(s.entries.length, inInclusiveRange(40, 60));
    expect(s.entries.map((e) => e.id).toSet().length, s.entries.length);
    final senders = {
      for (final e in s.entries)
        if (e.sender != null) e.sender,
    };
    expect(senders.length, greaterThanOrEqualTo(4));
    for (final e in s.entries) {
      if (e.ignored || e.isManual) continue;
      expect(e.sender, isNotNull, reason: e.id);
      expect(e.rawBody, isNotEmpty, reason: e.id);
      if (!e.isLive) expect(e.day, inInclusiveRange(2, 26), reason: e.id);
    }
  });

  test('last month in EGP: hand-added numbers', () {
    final n = expectedFor(s, 'EGP', now, from: m1.from, to: m1.to);
    // purchases + bills + ATM + InstaPay out (own transfer excluded);
    // the declined Netflix and the cash-covered corner shop (300.00) add 0.
    const spend =
        125050 +
        89900 +
        14000 +
        8500 +
        31000 +
        100000 +
        42000 +
        85000 +
        30000 +
        125000 +
        11500 +
        18000 +
        27500 +
        60000 +
        35000 +
        22000 +
        26000 +
        17500 +
        48000;
    expect(n.spend, spend);
    // salary + InstaPay in + refund; the own-transfer leg is excluded.
    expect(n.income, 1500000 + 350000 + 80000);
    expect(n.saved, n.income - n.spend);
    expect(n.byCategory['cash'], 100000 - 30000);
    expect(n.byCategory['groceries'], 125050 + 31000 + 11500 + 48000 + 30000);
    expect(n.byCategory['instapay'], 125000);
    expect(n.byCategory[null], 27500);
    expect(n.sharesBp().values.fold<int>(0, (a, b) => a + b), 10000);
  });

  test('USD stays apart from EGP', () {
    final usd = expectedFor(s, 'USD', now, from: m1.from, to: m1.to);
    expect(usd.spend, 2000);
    expect(usd.income, 0);
    expect(currenciesOf(s), {'EGP', 'USD'});
  });

  test('ignored and declined entries never count', () {
    expect(s.byId('m1-20').counts, isFalse);
    expect(s.byId('m1-09').counts, isFalse);
    expect(s.byId('m1-16').counts, isFalse);
    expect(s.byId('m1-17').counts, isFalse);
  });

  test('cash cover: the payment is covered by the earlier withdrawal', () {
    expect(cashCovers(s.entries, now), {'m1-08': 30000});
  });

  test('daily totals and merchant ranking', () {
    final n = expectedFor(s, 'EGP', now, from: m1.from, to: m1.to);
    expect(
      n.daily['${m1.from.year}-${m1.from.month.toString().padLeft(2, '0')}-05'],
      14000 + 8500,
    );
    final t = n.topMerchants(3);
    expect(t.top.first.key, 'carrefour');
    expect(t.top.length, 3);
    expect(t.other, greaterThan(0));
  });

  test('placeholders are filled for the entry date', () {
    final e = s.byId('m1-16');
    final at = e.localAt(now);
    expect(at, DateTime(2026, 10, 15, 22, 32));
    expect(e.bodyAt(at), contains('15-10-2026 22:32'));
  });

  test('live entries are dated now', () {
    expect(s.byId('lv-01').localAt(now), now);
  });
}
