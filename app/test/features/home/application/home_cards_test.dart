import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/home/application/home_cards.dart';
import 'package:zaghlol/features/onboarding/application/contextual.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

SetupContext _ctx() => SetupContext(
  today: CivilDate(2026, 11, 20),
  installedOn: CivilDate(2026, 11, 19),
  paydayConfigured: true,
  hasBudgets: true,
  backupExists: true,
);

Future<HomeCards> _read(ProviderContainer c, bool tx) {
  final p = homeCardsProvider(tx);
  c.listen(p, (_, _) {});
  return c.read(p.future);
}

ProviderContainer _c({
  bool lockOn = false,
  Set<String> handled = const {},
  Set<String> progress = const {},
}) {
  final c = ProviderContainer(
    overrides: [
      setupContextProvider.overrideWith((ref) async => _ctx()),
      setupHandledProvider.overrideWith((ref) => Stream.value(handled)),
      appLockEnabledProvider.overrideWith((ref) => Stream.value(lockOn)),
      setupProgressProvider.overrideWith((ref) => Stream.value(progress)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('app lock offer needs transactions', () async {
    final c = _c();
    expect((await _read(c, false)).offerAppLock, false);
    expect((await _read(c, true)).offerAppLock, true);
  });

  test('app lock offer is once and only while the lock is off', () async {
    expect((await _read(_c(lockOn: true), true)).offerAppLock, false);
    expect(
      (await _read(_c(handled: {appLockOfferSlug}), true)).offerAppLock,
      false,
    );
  });

  test('finish setup counts skipped steps not yet done', () async {
    final c = _c(progress: {'skip_sms', 'skip_cards', 'done_cards'});
    expect((await _read(c, true)).stepsLeft, 1);
  });
}
