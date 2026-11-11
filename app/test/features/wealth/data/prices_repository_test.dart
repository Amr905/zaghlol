// T-112: the prices repository on an in-memory database. Synthetic data.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';
import 'package:zaghlol/features/wealth/domain/price_feed.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
final sar = Currency.of('SAR');

const int h = 3600000;

class FakeRemote implements RemotePricesSource {
  FakeRemote(this.answer);
  Object? answer;
  @override
  Future<RemotePrices> fetch() async {
    final a = answer;
    if (a == null) throw const PricesUnavailable();
    return RemotePrices(a);
  }
}

Map<String, Object?> block({
  required DateTime asOf,
  bool stale = false,
  String egpGold = '4217.50',
  String rateEgp = '48.95',
}) => {
  'asOf': asOf.toIso8601String(),
  'stale': stale,
  'gold': [
    {'symbol': 'XAU21_G', 'currency': 'EGP', 'price': egpGold},
    {'symbol': 'XAU24_G', 'currency': 'USD', 'price': '98.40'},
  ],
  'fx': {
    'base': 'USD',
    'rates': {'EGP': rateEgp, 'SAR': '3.75'},
  },
};

void main() {
  var now = DateTime.utc(2026, 11, 3, 16);
  late AppDatabase db;
  late PricesRepository repo;

  PricesRepository make({RemotePricesSource? remote}) =>
      PricesRepository(db: db, clock: () => now, remote: remote);

  setUp(() {
    now = DateTime.utc(2026, 11, 3, 16);
    db = AppDatabase(NativeDatabase.memory(), validateSchema: false);
    repo = make();
  });
  tearDown(() => db.close());

  final asOf = DateTime.utc(2026, 11, 3, 15);

  test('apply stores gold and FX; reads back exact and fresh', () async {
    expect(await repo.apply(block(asOf: asOf)), PricesApplyResult.applied);
    final p = (await repo.price('XAU21_G', egp))!;
    expect(p.price, Money(egp, 421750));
    expect(p.perUnit, 'g');
    expect(p.origin, PriceOrigin.backend);
    expect(p.stale, isFalse);
    final c = await repo.convertApprox(Money(usd, 1000), egp) as Approx;
    expect(c.amount, Money(egp, 48950));
    expect((await repo.status()).backendAsOfMs, asOf.millisecondsSinceEpoch);
  });

  test(
    'AC: override beats backend price until cleared; survives apply',
    () async {
      await repo.apply(block(asOf: asOf));
      await repo.setManualOverride(
        symbol: 'XAU21_G',
        price: Money(egp, 430000),
        perUnit: 'g',
      );
      var p = (await repo.price('XAU21_G', egp))!;
      expect(p.price, Money(egp, 430000));
      expect(p.isManual, isTrue);
      expect((await repo.status()).hasManualOverride, isTrue);

      // A newer sync does not remove it.
      await repo.apply(
        block(asOf: asOf.add(const Duration(hours: 1)), egpGold: '4300.00'),
      );
      p = (await repo.price('XAU21_G', egp))!;
      expect(p.isManual, isTrue);
      expect(p.price, Money(egp, 430000));

      await repo.clearManualOverride('XAU21_G', egp);
      p = (await repo.price('XAU21_G', egp))!;
      expect(p.price, Money(egp, 430000)); // backend now 4300.00 -> 430000
      expect(p.origin, PriceOrigin.backend);
      expect((await repo.status()).hasManualOverride, isFalse);
    },
  );

  test('AC: stale label after 24 h (and not before)', () async {
    await repo.apply(block(asOf: asOf));
    now = asOf.add(const Duration(hours: 24));
    expect((await repo.price('XAU21_G', egp))!.stale, isFalse);
    expect((await repo.status()).stale, isFalse);
    now = asOf.add(const Duration(hours: 24, milliseconds: 1));
    expect((await repo.price('XAU21_G', egp))!.stale, isTrue);
    expect((await repo.status()).stale, isTrue);
    final c = await repo.convertApprox(Money(usd, 100), egp) as Approx;
    expect(c.stale, isTrue);
  });

  test('a stale override stays marked manual and not stale', () async {
    await repo.apply(block(asOf: asOf));
    await repo.setManualOverride(
      symbol: 'XAU21_G',
      price: Money(egp, 430000),
      perUnit: 'g',
    );
    now = now.add(const Duration(days: 30));
    final p = (await repo.price('XAU21_G', egp))!;
    expect(p.isManual, isTrue);
    expect(p.stale, isFalse);
  });

  test(
    'backend-reported stale persists and is cleared by a fresh block',
    () async {
      await repo.apply(block(asOf: asOf, stale: true));
      expect((await repo.price('XAU21_G', egp))!.stale, isTrue);
      // A new repository over the same database sees the same flag.
      expect((await make().price('XAU21_G', egp))!.stale, isTrue);
      await repo.apply(block(asOf: asOf.add(const Duration(minutes: 10))));
      expect((await repo.price('XAU21_G', egp))!.stale, isFalse);
    },
  );

  test('missing price and missing rate (EC-35)', () async {
    expect(await repo.price('XAU21_G', egp), isNull);
    expect(await repo.convertApprox(Money(egp, 1), usd), isA<MissingRate>());
    await repo.apply(block(asOf: asOf));
    expect(await repo.price('XAU18_G', egp), isNull);
    expect(
      await repo.convertApprox(Money(egp, 1), Currency.of('GBP')),
      isA<MissingRate>(),
    );
    expect((await repo.status()).stale, isFalse);
  });

  test('malformed block changes nothing', () async {
    await repo.apply(block(asOf: asOf));
    final bad = block(asOf: asOf.add(const Duration(hours: 1)));
    (bad['gold']! as List).add({
      'symbol': 'XAU21_G',
      'currency': 'EGP',
      'price': '0',
    });
    expect(await repo.apply(bad), PricesApplyResult.rejected);
    expect(await repo.apply('garbage'), PricesApplyResult.rejected);
    expect(await repo.apply(null), PricesApplyResult.rejected);
    expect((await repo.price('XAU21_G', egp))!.price, Money(egp, 421750));
    expect((await repo.status()).backendAsOfMs, asOf.millisecondsSinceEpoch);
  });

  test(
    'an older block is a replay and is ignored; equal is accepted',
    () async {
      await repo.apply(block(asOf: asOf));
      expect(
        await repo.apply(
          block(asOf: asOf.subtract(const Duration(hours: 1)), egpGold: '1.00'),
        ),
        PricesApplyResult.rejected,
      );
      expect((await repo.price('XAU21_G', egp))!.price, Money(egp, 421750));
      expect(
        await repo.apply(block(asOf: asOf, egpGold: '4218.00')),
        PricesApplyResult.applied,
      );
    },
  );

  test('apply replaces old backend rows and rates wholesale', () async {
    await repo.apply(block(asOf: asOf));
    final next = block(asOf: asOf.add(const Duration(hours: 1)));
    next['gold'] = [
      {'symbol': 'XAU24_G', 'currency': 'EGP', 'price': '4820.00'},
    ];
    next['fx'] = {
      'base': 'USD',
      'rates': {'EGP': '50'},
    };
    await repo.apply(next);
    expect(await repo.price('XAU21_G', egp), isNull);
    expect(await repo.convertApprox(Money(usd, 100), sar), isA<MissingRate>());
    final c = await repo.convertApprox(Money(usd, 100), egp) as Approx;
    expect(c.amount, Money(egp, 5000));
  });

  test('refresh pulls through the port; no port or failure is quiet', () async {
    expect(await repo.refresh(), PricesApplyResult.unavailable);
    final remote = FakeRemote(null);
    final r = make(remote: remote);
    expect(await r.refresh(), PricesApplyResult.unavailable);
    remote.answer = block(asOf: asOf);
    expect(await r.refresh(), PricesApplyResult.applied);
    expect((await r.price('XAU21_G', egp))!.price, Money(egp, 421750));
  });

  test('setManualOverride validates', () async {
    for (final f in [
      () => repo.setManualOverride(
        symbol: 'xau',
        price: Money(egp, 1),
        perUnit: 'g',
      ),
      () => repo.setManualOverride(
        symbol: 'XAU21_G',
        price: Money(egp, 0),
        perUnit: 'g',
      ),
      () => repo.setManualOverride(
        symbol: 'XAU21_G',
        price: Money(egp, -5),
        perUnit: 'g',
      ),
      () => repo.setManualOverride(
        symbol: 'XAU21_G',
        price: Money(egp, 5),
        perUnit: 'Gram!',
      ),
    ]) {
      await expectLater(f(), throwsA(isA<PricesRejected>()));
    }
    expect(await repo.price('XAU21_G', egp), isNull);
  });

  test('a manual override with no backend price is still used', () async {
    await repo.setManualOverride(
      symbol: 'XAU21_G',
      price: Money(egp, 430000),
      perUnit: 'g',
    );
    final p = (await repo.price('XAU21_G', egp))!;
    expect(p.isManual, isTrue);
    expect(p.price, Money(egp, 430000));
    expect((await repo.status()).backendAsOfMs, isNull);
  });
}
