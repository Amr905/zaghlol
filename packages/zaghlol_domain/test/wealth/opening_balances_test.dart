import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');
final _usd = Currency.of('USD');
final _t = DateTime.utc(2026, 11, 1);

void main() {
  test('set, read, per currency, replace; never mixes currencies', () {
    var b = OpeningBalances.empty.withEntry('a', Money(_egp, 100), _t);
    b = b.withEntry('a', Money(_usd, 5), _t);
    expect(b.of('a', 'EGP')!.amount.minor, 100);
    expect(b.of('a', 'USD')!.amount.minor, 5);
    b = b.withEntry('a', Money(_egp, 250), _t.add(const Duration(days: 1)));
    expect(b.of('a', 'EGP')!.amount.minor, 250);
    expect(b.length, 2);
    expect(b.without('a', 'EGP').of('a', 'EGP'), isNull);
    expect(b.without('a', 'EGP').of('a', 'USD'), isNotNull);
  });

  test('json round trip is canonical', () {
    final b = OpeningBalances.empty
        .withEntry('z', Money(_egp, -5), _t)
        .withEntry('a', Money(_usd, 5), _t);
    final text = b.toJson();
    expect(text, startsWith('{"a":'));
    final back = OpeningBalances.fromJson(text)!;
    expect(back.toJson(), text);
    expect(back.of('z', 'EGP'), b.of('z', 'EGP'));
    expect(OpeningBalances.empty.toJson(), '{}');
  });

  test('garbage reads as null, never throws', () {
    for (final s in [
      '',
      'x',
      '[]',
      '{"a":1}',
      '{"a":{}}',
      '{"a":{"EGP":[1]}}',
      '{"a":{"EGP":["1",2]}}',
      '{"a":{"egp":[1,2]}}',
      '{"":{"EGP":[1,2]}}',
    ]) {
      expect(OpeningBalances.fromJson(s), isNull, reason: s);
    }
  });

  test('moveAccount: newer instant wins per currency, source removed', () {
    final b = OpeningBalances.empty
        .withEntry('s', Money(_egp, 1), _t.add(const Duration(days: 2)))
        .withEntry('s', Money(_usd, 2), _t)
        .withEntry('t', Money(_egp, 9), _t)
        .withEntry('t', Money(_usd, 8), _t.add(const Duration(days: 1)));
    final m = b.moveAccount('s', 't');
    expect(m.of('s', 'EGP'), isNull);
    expect(m.of('t', 'EGP')!.amount.minor, 1);
    expect(m.of('t', 'USD')!.amount.minor, 8);
  });

  test('cap on entries', () {
    var b = OpeningBalances.empty;
    for (var i = 0; i < maxOpeningBalanceEntries; i++) {
      b = b.withEntry('a$i', Money(_egp, 1), _t);
    }
    expect(() => b.withEntry('extra', Money(_egp, 1), _t), throwsArgumentError);
  });
}
