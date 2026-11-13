import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

void main() {
  const free = EntitlementState.free;
  final gold = () {
    final c = ProviderContainer();
    c
        .read(entitlementStateProvider.notifier)
        .applyVerified(verified: true, status: 'active');
    return c.read(entitlementStateProvider);
  }();

  test(
    'every Gold capability is blocked for Free on create, open for Gold',
    () {
      for (final c in GoldCapability.values) {
        expect(GoldGate.check(free, c).allowed, isFalse, reason: '$c');
        expect(GoldGate.check(free, c).paywall, isTrue);
        expect(GoldGate.check(gold, c).allowed, isTrue, reason: '$c');
      }
    },
  );

  test('downgrade keeps data readable but not creatable (BR-GOLD-04)', () {
    for (final c in GoldCapability.values) {
      expect(GoldGate.check(free, c, action: GateAction.read).allowed, isTrue);
      expect(GoldGate.check(free, c).allowed, isFalse);
    }
  });

  test('voice limit 15 per month for Free', () {
    expect(GoldGate.voiceEntry(free, 14).allowed, isTrue);
    expect(GoldGate.voiceEntry(free, 15).allowed, isFalse);
    expect(GoldGate.voiceEntry(gold, 500).allowed, isTrue);
  });

  test('charts: 4 core for Free, all 12 for Gold', () {
    expect(GoldGate.chart(free, 3).allowed, isTrue);
    expect(GoldGate.chart(free, 4).allowed, isFalse);
    expect(GoldGate.chart(free, -1).allowed, isFalse);
    expect(GoldGate.chart(gold, 11).allowed, isTrue);
  });

  test('backup versions and export preview', () {
    expect(GoldGate.backupVersionsKept(free), 1);
    expect(GoldGate.backupVersionsKept(gold), 5);
    expect(GoldGate.exportPreviewOnly(free), isTrue);
    expect(GoldGate.exportPreviewOnly(gold), isFalse);
  });

  test('state is Free by default and fails closed', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(entitlementStateProvider.notifier);
    expect(c.read(entitlementStateProvider), free);
    n.applyVerified(verified: true, status: 'active');
    expect(c.read(entitlementStateProvider).isGold, isTrue);
    for (final (v, s) in [
      (false, 'active'),
      (true, 'expired'),
      (true, 'weird'),
      (true, null),
    ]) {
      n.applyVerified(verified: true, status: 'active');
      n.applyVerified(verified: v, status: s);
      expect(c.read(entitlementStateProvider), free, reason: '$v $s');
    }
  });

  test('debug override works in test (debug) mode; reset returns Free', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(entitlementStateProvider.notifier);
    n.debugOverride(true);
    expect(c.read(entitlementStateProvider).isGold, isTrue);
    n.reset();
    expect(c.read(entitlementStateProvider), free);
  });

  test('paywall hook fires when blocked only', () {
    final seen = <GoldCapability>[];
    final c = ProviderContainer(
      overrides: [paywallTriggerProvider.overrideWithValue(seen.add)],
    );
    addTearDown(c.dispose);
    final p = Provider<bool Function(GoldCapability)>(
      (ref) =>
          (cap) => gateOrPaywall(ref, cap),
    );
    expect(c.read(p)(GoldCapability.csvExport), isFalse);
    expect(seen, [GoldCapability.csvExport]);
    c.read(entitlementStateProvider.notifier).debugOverride(true);
    expect(c.read(p)(GoldCapability.csvExport), isTrue);
    expect(seen.length, 1);
  });

  test('applyVerified: Gold only for active and grace, every status', () {
    for (final st in [
      'active',
      'grace',
      'paused',
      'moved',
      'refunded',
      'expired',
      'none',
      'unknown',
      'ACTIVE',
      '',
      null,
    ]) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(entitlementStateProvider.notifier);
      n.applyVerified(verified: true, status: st);
      expect(
        c.read(entitlementStateProvider).isGold,
        st == 'active' || st == 'grace',
        reason: '$st',
      );
      n.applyVerified(verified: false, status: st);
      expect(c.read(entitlementStateProvider).isGold, isFalse, reason: '$st');
    }
  });
}
