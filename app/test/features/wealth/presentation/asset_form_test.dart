// T-121: Add asset validation. Exact parsing, Arabic-Indic digits.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/assets_dao.dart';
import 'package:zaghlol/features/wealth/presentation/asset_form.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');
final _today = CivilDate(2026, 11, 13);

void main() {
  test('type is required', () {
    final r = validateAssetForm(const AssetFormInput(), today: _today);
    expect(r.errors[AssetField.type], AssetFieldError.type);
  });

  test('gold grams: Arabic-Indic digits and ٫ parse exactly to milli', () {
    final r = validateAssetForm(
      const AssetFormInput(type: AssetFormType.gold, quantity: '٢٤٫٥'),
      today: _today,
    );
    expect(r.draft!.quantityMilli, 24500);
    expect(r.draft!.type, AssetType.gold);
    expect(r.draft!.karat, 21);
  });

  test('gold grams: zero, junk and 4 decimals are refused, never rounded', () {
    AssetFieldError? e(String q) => validateAssetForm(
      AssetFormInput(type: AssetFormType.gold, quantity: q),
      today: _today,
    ).errors[AssetField.quantity];
    expect(e('0'), AssetFieldError.grams);
    expect(e('abc'), AssetFieldError.grams);
    expect(e(''), AssetFieldError.grams);
    expect(e('1.2345'), AssetFieldError.gramsDecimals);
    expect(e('1.2340'), isNull); // trailing zero is not a 4th decimal
  });

  test('gold coin counts whole coins x 1000', () {
    final r = validateAssetForm(
      const AssetFormInput(
        type: AssetFormType.gold,
        goldKind: GoldKind.coin,
        quantity: '٣',
      ),
      today: _today,
    );
    expect(r.draft!.type, AssetType.goldCoin);
    expect(r.draft!.quantityMilli, 3000);
    expect(
      validateAssetForm(
        const AssetFormInput(
          type: AssetFormType.gold,
          goldKind: GoldKind.coin,
          quantity: '1.5',
        ),
        today: _today,
      ).errors[AssetField.quantity],
      AssetFieldError.count,
    );
  });

  test('certificate: rate 0..100, maturity after purchase', () {
    AssetFormInput cert({
      String rate = '27',
      CivilDate? bought,
      CivilDate? m,
    }) => AssetFormInput(
      type: AssetFormType.certificate,
      name: 'NBE',
      amount: '163000',
      currency: _egp,
      rate: rate,
      boughtOn: bought,
      maturity: m ?? CivilDate(2027, 11, 13),
    );
    final ok = validateAssetForm(cert(rate: '٢٧٫٥'), today: _today).draft!;
    expect(ok.rateBp, 2750);
    expect(ok.principal, Money(_egp, 16300000));
    expect(ok.maturityDate, '2027-11-13');
    expect(
      validateAssetForm(
        cert(rate: '100.01'),
        today: _today,
      ).errors[AssetField.rate],
      AssetFieldError.rate,
    );
    expect(validateAssetForm(cert(rate: '0'), today: _today).isValid, isTrue);
    expect(
      validateAssetForm(
        cert(bought: CivilDate(2026, 11, 1), m: CivilDate(2026, 11, 1)),
        today: _today,
      ).errors[AssetField.maturity],
      AssetFieldError.maturityOrder,
    );
  });

  test('amounts follow the currency exponent (KWD 3, JPY 0)', () {
    AssetFormResult cash(String amount, String code) => validateAssetForm(
      AssetFormInput(
        type: AssetFormType.cash,
        amount: amount,
        currency: Currency.of(code),
      ),
      today: _today,
    );
    expect(cash('1.234', 'KWD').draft!.manualValue!.minor, 1234);
    expect(
      cash('12.5', 'JPY').errors[AssetField.amount],
      AssetFieldError.amountDecimals,
    );
    expect(cash('0', 'USD').errors[AssetField.amount], AssetFieldError.amount);
  });

  test('stocks need a name; property and car map to their types', () {
    AssetFormResult v(AssetFormType t, String name) => validateAssetForm(
      AssetFormInput(type: t, name: name, amount: '500000', currency: _egp),
      today: _today,
    );
    expect(
      v(AssetFormType.stocks, ' ').errors[AssetField.name],
      AssetFieldError.name,
    );
    expect(v(AssetFormType.property, 'Flat').draft!.type, AssetType.realEstate);
    expect(v(AssetFormType.car, 'Car').draft!.type, AssetType.car);
  });
}
