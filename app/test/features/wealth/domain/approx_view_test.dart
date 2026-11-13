// T-115: the ≈ combined view. Synthetic data only.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/wealth/data/approx_view_providers.dart';
import 'package:zaghlol/features/wealth/data/prices_providers.dart';
import 'package:zaghlol/features/wealth/domain/approx_view.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final sar = Currency.of('SAR');
final jpy = Currency.of('JPY');

const int now = 1793527200000;
const int h = 3600000;

FxQuote q(Currency b, Currency c, int rateE9, int asOf) =>
    FxQuote(base: b, quote: c, rateE9: rateE9, asOfMs: asOf);

MultiCurrencyTotal totals(List<Money> m) => MultiCurrencyTotal.of(m);

ApproxViewOn on(ApproxView v) => v as ApproxViewOn;

ApproxView build(
  List<Money> m,
  List<FxQuote> rates, {
  bool enabled = true,
  Currency? target,
}) => buildApproxView(
  enabled: enabled,
  totals: totals(m),
  target: target ?? egp,
  rates: FxTable(rates, reportedStale: false),
  nowMs: now,
);

void main() {
  final usdEgp = q(usd, egp, 48950000000, now - h);

  group('off switch (AC: turning off removes every combined figure)', () {
    test('disabled returns ApproxViewOff with no figure', () {
      final v = build(
        [Money(egp, 100), Money(usd, 500)],
        [usdEgp],
        enabled: false,
      );
      expect(v, isA<ApproxViewOff>());
    });

    test('provider: off by setting never reads rates', () async {
      final c = ProviderContainer(
        overrides: [
          approxViewEnabledProvider.overrideWith((ref) => Stream.value(false)),
          pricesRepositoryProvider.overrideWith(
            (ref) async => throw StateError('rates must not be read'),
          ),
        ],
      );
      addTearDown(c.dispose);
      final provider = approxViewProvider(totals([Money(usd, 500)]));
      c.listen(provider, (_, _) {});
      final v = await c.read(provider.future);
      expect(v, isA<ApproxViewOff>());
    });
  });

  group('exclusions (AC: currency without rate listed as not included)', () {
    test('no rate: excluded, nothing guessed, rest still combined', () {
      final v = on(
        build([Money(egp, 1000), Money(usd, 100), Money(jpy, 5000)], [usdEgp]),
      );
      expect(v.excluded, [jpy]);
      // 1000 + 100 cents * 48.95 = 1000 + 4895
      expect(v.figure!.amount, Money(egp, 5895));
      expect(v.approximate, isTrue);
    });

    test('nothing convertible: figure is null, all listed', () {
      final v = on(build([Money(jpy, 5000), Money(sar, 10)], []));
      expect(v.figure, isNull);
      expect(v.excluded, [jpy, sar]);
    });

    test('target-only figure with an excluded currency is labelled ≈', () {
      final v = on(build([Money(egp, 1000), Money(jpy, 5000)], []));
      expect(v.excluded, [jpy]);
      expect(v.figure!.amount, Money(egp, 1000));
      expect(v.approximate, isTrue);
    });

    test('a zero total needs no rate and is not listed', () {
      final v = on(build([Money(egp, 700), Money.zero(jpy)], []));
      expect(v.excluded, isEmpty);
      expect(v.figure!.amount, Money(egp, 700));
    });

    test('empty totals: zero figure, exact', () {
      final v = on(build([], []));
      expect(v.figure!.amount, Money.zero(egp));
      expect(v.approximate, isFalse);
    });
  });

  group('conversion and rounding', () {
    test('target currency only is exact (not approximate)', () {
      final v = on(build([Money(egp, 12345)], [usdEgp]));
      expect(v.approximate, isFalse);
      expect(v.rateAsOfMs, isNull);
      expect(v.figure!.amount, Money(egp, 12345));
    });

    test('half-even on exact ties: 2.5 -> 2, 7.5 -> 8', () {
      final r = q(usd, egp, 2500000000, now);
      expect(on(build([Money(usd, 1)], [r])).figure!.amount, Money(egp, 2));
      expect(on(build([Money(usd, 3)], [r])).figure!.amount, Money(egp, 8));
    });

    test('negative totals round symmetrically (-2.5 -> -2, -7.5 -> -8)', () {
      final r = q(usd, egp, 2500000000, now);
      expect(on(build([Money(usd, -1)], [r])).figure!.amount, Money(egp, -2));
      expect(on(build([Money(usd, -3)], [r])).figure!.amount, Money(egp, -8));
    });

    test('exponent differences: JPY (0) to EGP (2) and EGP to JPY', () {
      final r = q(jpy, egp, 330000000, now); // 1 JPY = 0.33 EGP
      expect(
        on(build([Money(jpy, 100)], [r])).figure!.amount,
        Money(egp, 3300),
      );
      expect(
        on(build([Money(egp, 3300)], [r], target: jpy)).figure!.amount,
        Money(jpy, 100),
      );
    });

    test('each converted currency is rounded once, then summed', () {
      // 1 cent USD = 48.95 piasters -> 49; 1 halala SAR at 13.05 -> 13.05
      final r = [usdEgp, q(sar, egp, 13050000000, now)];
      final v = on(build([Money(usd, 1), Money(sar, 1)], r));
      expect(v.figure!.amount, Money(egp, 49 + 13));
    });

    test('overflow is a typed error, not a wrong figure', () {
      final r = q(usd, egp, 9007199254740991, now);
      expect(
        () => build([Money(usd, 9007199254740991)], [r]),
        throwsA(isA<MoneyOverflow>()),
      );
    });

    test('property: result does not depend on currency order', () {
      final rnd = Random(115);
      final rates = [
        usdEgp,
        q(sar, egp, 13050000000, now),
        q(jpy, egp, 330000000, now),
      ];
      final cur = [egp, usd, sar, jpy];
      for (var i = 0; i < 200; i++) {
        final items = [
          for (final c in cur) Money(c, rnd.nextInt(2000000) - 1000000),
        ];
        final a = on(build(items, rates)).figure!.amount;
        final b = on(build(items.reversed.toList(), rates)).figure!.amount;
        expect(a, b);
      }
    });
  });

  group('rate date and staleness', () {
    test('reports the oldest rate used, ignoring unused rates', () {
      final r = [
        q(usd, egp, 48950000000, now - 2 * h),
        q(sar, egp, 13050000000, now - 5 * h),
        q(jpy, egp, 330000000, now - 90 * h),
      ];
      final v = on(build([Money(usd, 1), Money(sar, 1)], r));
      expect(v.rateAsOfMs, now - 5 * h);
      expect(v.stale, isFalse);
    });

    test('a stale rate marks the view stale (older than 24 h)', () {
      final r = [q(usd, egp, 48950000000, now - 25 * h)];
      final v = on(build([Money(usd, 1)], r));
      expect(v.stale, isTrue);
      expect(v.rateAsOfMs, now - 25 * h);
    });

    test('inverse and cross rates work (EGP->USD, SAR->EGP via USD)', () {
      final r = [usdEgp, q(usd, sar, 3750000000, now)];
      final inv = on(build([Money(egp, 4895)], r, target: usd));
      expect(inv.figure!.amount, Money(usd, 100));
      final cross = on(build([Money(sar, 375)], r));
      expect(cross.figure!.amount, Money(egp, 4895));
    });
  });
}
