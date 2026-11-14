// T-147 (D-54): the "sign in on this phone" suggestion appears after a
// verified purchase on this phone and nowhere else.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/account/application/protect_suggestion.dart';
import 'package:zaghlol/features/gold/domain/purchase_outcome.dart';

import '../../../core/backend/backend_test_support.dart';

void main() {
  late FakeBackendStore store;
  var signedIn = false;
  var id = 'install-a';
  ProtectGoldSuggestion make() => ProtectGoldSuggestion(
    store: store,
    installId: () async => id,
    signedIn: () async => signedIn,
  );

  setUp(() {
    store = FakeBackendStore([]);
    signedIn = false;
    id = 'install-a';
  });

  test('a verified purchase raises it; clear removes it', () async {
    final s = make();
    expect(await s.pending(), isFalse);
    await s.onPurchaseOutcome(const PurchaseGold());
    expect(await s.pending(), isTrue);
    await s.clear();
    expect(await s.pending(), isFalse);
  });

  test('every other outcome leaves it off', () async {
    final s = make();
    for (final o in <PurchaseOutcome>[
      const PurchasePending(),
      const PurchaseQueued(),
      const PurchaseInvalid(),
      const PurchaseNotOwned(),
      const PurchaseCancelled(),
      const PurchaseSeatHeldElsewhere(accountRequired: true),
    ]) {
      await s.onPurchaseOutcome(o);
    }
    expect(await s.pending(), isFalse);
  });

  test('not when already signed in', () async {
    signedIn = true;
    final s = make();
    await s.onPurchaseOutcome(const PurchaseGold());
    expect(await s.pending(), isFalse);
  });

  test('a flag from another install does not show on this one', () async {
    final s = make();
    await s.onPurchaseOutcome(const PurchaseGold());
    id = 'install-b';
    expect(await s.pending(), isFalse);
  });
}
