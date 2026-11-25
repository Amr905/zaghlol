// T-266: orderLinkTargets, the pure ranking of the accounts a debit card can
// be linked to. Synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/card_link.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final _t = DateTime.utc(2026, 11, 1);

Account a(
  String id,
  AccountKind kind, {
  String? inst = 'nbe',
  bool hidden = false,
  String? merged,
}) => Account(
  id: id,
  kind: kind,
  label: id,
  defaultCurrency: egp,
  isHidden: hidden,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
  institutionCode: inst,
  mergedIntoId: merged,
);

ReportedFigure fig(int minor) => (amount: Money(egp, minor), asOf: _t);

void main() {
  final card = a('card', AccountKind.debit);

  test('only a debit card has targets', () {
    final accounts = [a('acc', AccountKind.account)];
    for (final k in AccountKind.values) {
      final got = orderLinkTargets(card: a('x', k), accounts: accounts);
      expect(got.isNotEmpty, k == AccountKind.debit, reason: k.code);
    }
  });

  test('targets: account, wallet, multi-currency; never cards, cash, bnpl, '
      'hidden, merged or the card itself', () {
    final got = orderLinkTargets(
      card: card,
      accounts: [
        card,
        a('acc', AccountKind.account),
        a('wal', AccountKind.wallet),
        a('mc', AccountKind.multiCurrency),
        a('deb', AccountKind.debit),
        a('cc', AccountKind.credit),
        a('cash', AccountKind.cash),
        a('bnpl', AccountKind.bnpl),
        a('hid', AccountKind.account, hidden: true),
        a('gone', AccountKind.account, merged: 'acc'),
      ],
    );
    expect([for (final t in got) t.account.id], ['acc', 'wal', 'mc']);
  });

  test('same bank + same balance, then same bank, then others; a balance '
      'match at another bank does not rank', () {
    final got = orderLinkTargets(
      card: card,
      accounts: [
        a('other', AccountKind.account, inst: 'cib'),
        a('same', AccountKind.account),
        a('match', AccountKind.account),
      ],
      reported: {
        'card': {'EGP': fig(5000)},
        'other': {'EGP': fig(5000)},
        'same': {'EGP': fig(4000)},
        'match': {'EGP': fig(5000)},
      },
    );
    expect([for (final t in got) t.account.id], ['match', 'same', 'other']);
    expect(got[0].sameBalance, isTrue);
    expect(got[2].sameBalance, isFalse);
    expect(got[2].isSuggestion, isFalse);
  });

  test('a card without an institution is never a suggestion', () {
    final got = orderLinkTargets(
      card: a('card', AccountKind.debit, inst: null),
      accounts: [a('acc', AccountKind.account, inst: null)],
    );
    expect(got.single.isSuggestion, isFalse);
  });
}
