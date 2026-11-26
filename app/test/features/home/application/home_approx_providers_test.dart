// T-280: Q2 (turns on once, never again after the user turns it off) and the
// Home figure provider. Synthetic data only.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/setting_key.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/home/application/home_approx_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');

/// In-memory settings with a working `watch`.
class FakeSettingsRepo implements SettingsRepository {
  final values = <String, String>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Future<T> get<T>(SettingKey<T> key) async => key.parse(values[key.name]);

  @override
  Stream<T> watch<T>(SettingKey<T> key) async* {
    yield key.parse(values[key.name]);
    await for (final _ in _changes.stream) {
      yield key.parse(values[key.name]);
    }
  }

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    values[key.name] = key.format(value);
    _changes.add(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CycleTotals totals(Currency c, {int income = 0, int spend = 0}) => CycleTotals(
  currency: c,
  income: Money(c, income),
  spend: Money(c, spend),
  pendingSpend: Money.zero(c),
  byCategoryMinor: const {},
);

ProviderContainer container(
  FakeSettingsRepo repo,
  Map<Currency, CycleTotals> t,
) {
  final overrides = <Override>[
    settingsRepositoryProvider.overrideWith((ref) async => repo),
    homeApproxCycleTotalsProvider.overrideWith((ref) async => t),
  ];
  final c = ProviderContainer(overrides: overrides);
  // Riverpod 3 pauses a stream provider nobody listens to; the app's UI
  // listens to these, so the test does too.
  for (final p in [
    approxViewEnabledProvider,
    approxViewTargetProvider,
    approxAutoOnDoneProvider,
    approxFirstForeignNoticeProvider,
  ]) {
    c.listen(p, (_, _) {});
  }
  addTearDown(c.dispose);
  return c;
}

Future<void> settle(ProviderContainer c) async {
  await c.read(homeApproxAutoOnProvider.future);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('EGP only: nothing is switched on, no notice', () async {
    final repo = FakeSettingsRepo();
    final c = container(repo, {egp: totals(egp, income: 100)});
    await settle(c);
    expect(await repo.get(Settings.approxViewEnabled), isFalse);
    expect(await repo.get(Settings.approxFirstForeignNotice), isFalse);
    expect(await repo.get(Settings.approxAutoOnDone), isFalse);
  });

  test('a second currency turns it on once, with the notice', () async {
    final repo = FakeSettingsRepo();
    final c = container(repo, {
      egp: totals(egp, income: 100),
      usd: totals(usd, income: 100),
    });
    await settle(c);
    expect(await repo.get(Settings.approxViewEnabled), isTrue);
    expect(await repo.get(Settings.approxFirstForeignNotice), isTrue);
    expect(await repo.get(Settings.approxAutoOnDone), isTrue);
  });

  test('user turns it off: a new currency does not turn it on again', () async {
    final repo = FakeSettingsRepo();
    final first = container(repo, {
      egp: totals(egp, income: 100),
      usd: totals(usd, income: 100),
    });
    await settle(first);
    // The user closes it ("اقفلها").
    await repo.set(Settings.approxViewEnabled, false);
    await repo.set(Settings.approxFirstForeignNotice, false);
    // Later (new session) another currency appears.
    final eur = Currency.of('EUR');
    final later = container(repo, {
      egp: totals(egp, income: 100),
      usd: totals(usd, income: 100),
      eur: totals(eur, spend: 50),
    });
    await settle(later);
    expect(await repo.get(Settings.approxViewEnabled), isFalse);
    expect(await repo.get(Settings.approxFirstForeignNotice), isFalse);
  });

  test('already on by hand: no notice is raised', () async {
    final repo = FakeSettingsRepo();
    await repo.set(Settings.approxViewEnabled, true);
    final c = container(repo, {
      egp: totals(egp, income: 100),
      usd: totals(usd, income: 100),
    });
    await settle(c);
    expect(await repo.get(Settings.approxFirstForeignNotice), isFalse);
    expect(await repo.get(Settings.approxAutoOnDone), isTrue);
  });

  test('setting off: no figure at all', () async {
    final repo = FakeSettingsRepo();
    final c = container(repo, {
      egp: totals(egp, income: 100),
      usd: totals(usd, income: 100),
    });
    expect(await c.read(homeApproxProvider.future), isNull);
  });

  group('bankRatesE9 (FU-381)', () {
    final eur = Currency.of('EUR');
    test('only target-side pairs make the rate: 600 USD -> 29,700 EGP', () {
      final rates = bankRatesE9([
        (given: Money(usd, 60000), received: Money(egp, 2970000)),
        (given: Money(usd, 10000), received: Money(eur, 9200)),
      ], egp);
      // 49.50 EGP per USD, not (29,700 / 700).
      expect(rates, {usd: 49500000000});
    });

    test('nothing into the target: no rate', () {
      expect(
        bankRatesE9([
          (given: Money(usd, 10000), received: Money(eur, 9200)),
        ], egp),
        isEmpty,
      );
    });
  });
}
