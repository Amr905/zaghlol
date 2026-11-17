// CAT-cash / CAT-INSTAPAY: the event's own category. Synthetic data only.

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'fake_ports.dart';

void main() {
  CategorizeInput input(String raw, {String? event, PartyKind? kind}) {
    final i = inp(raw, kind: kind, value: kind == null ? null : 'x@instapay');
    return CategorizeInput(
      merchantNorm: i.merchantNorm,
      merchantText: i.merchantText,
      counterpartyKind: i.counterpartyKind,
      counterpartyValue: i.counterpartyValue,
      eventCategoryId: event,
    );
  }

  test('an ATM event is Cash even with a merchant-like text', () async {
    final w = buildWorld();
    final d = await categorize(
      input('CARREFOUR ATM', event: 'sys:cash'),
      w.ports,
    );
    expect(d.categoryId, 'sys:cash');
    expect(d.tier, CategorizeTier.event);
  });

  test('InstaPay to a person is InstaPay, not the p2p stop', () async {
    final w = buildWorld();
    final d = await categorize(
      input('AHMED', event: 'sys:instapay', kind: PartyKind.ipa),
      w.ports,
    );
    expect(d.categoryId, 'sys:instapay');
  });

  test('a user rule beats the event category', () async {
    final w = buildWorld();
    w.rules.add('merchant_norm', inp('TALABAT').merchantNorm, 'sys:dining');
    final d = await categorize(
      input('TALABAT', event: 'sys:instapay'),
      w.ports,
    );
    expect(d.categoryId, 'sys:dining');
    expect(d.source, CategorySource.userRule);
  });

  test('an archived or missing event category is ignored', () async {
    final w = buildWorld(archived: {'cash'});
    final d = await categorize(input('TALABAT', event: 'sys:cash'), w.ports);
    expect(d.categoryId, 'sys:dining');
  });

  test('an own-account transfer stays uncategorized', () async {
    final w = buildWorld();
    final d = await categorize(
      input('MY CARD', event: 'sys:instapay', kind: PartyKind.ownAccount),
      w.ports,
    );
    expect(d.categoryId, isNull);
  });

  test('no event: nothing changes', () async {
    final w = buildWorld();
    final d = await categorize(input('TALABAT'), w.ports);
    expect(d.categoryId, 'sys:dining');
  });
}
