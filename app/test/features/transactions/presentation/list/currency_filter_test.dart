// T-279: the list's currency filter reaches the repository filter.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/transactions/presentation/list/txn_list_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  const noRange = (from: null, to: null);

  test('a currency narrows the repository filter to that currency only', () {
    final f = txnToRepoFilter(
      const TxnListFilter().copyWith(currency: Currency.of('USD')),
      cardIds: const {},
      range: noRange,
    );
    expect(f.currencies, {Currency.of('USD')});
  });

  test('no currency means no narrowing; clearing it restores that', () {
    final set = const TxnListFilter().copyWith(currency: Currency.of('USD'));
    expect(set.hasNarrowing, isTrue);
    final cleared = set.copyWith(clearCurrency: true);
    expect(
      txnToRepoFilter(cleared, cardIds: const {}, range: noRange).currencies,
      isEmpty,
    );
  });
}
