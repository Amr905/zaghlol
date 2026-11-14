// T-080: S-13 validation and exact amount parsing. Synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/transactions/presentation/edit/txn_form.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  group('parseAmount commas (T-080)', () {
    final egp = Currency.of('EGP');
    test('a lone comma is rejected, never 125', () {
      final r = parseAmount('12,5', egp);
      expect(r.money, isNull);
      expect(r.error, isNotNull);
    });
    test('thousands grouping and Arabic digits', () {
      expect(parseAmount('1,250.50', egp).money, Money(egp, 125050));
      expect(parseAmount('١٢٫٥', egp).money, Money(egp, 1250));
    });
  });

  final egp = Currency.of('EGP');
  final kwd = Currency.of('KWD');
  final jpy = Currency.of('JPY');

  test('Arabic-Indic digits and separator parse exactly', () {
    expect(parseAmount('١٢٣٫٥٠', egp).money, Money(egp, 12350));
    expect(parseAmount('0.1', egp).money, Money(egp, 10));
    expect(parseAmount('1.234', kwd).money, Money(kwd, 1234));
    expect(parseAmount('500', jpy).money, Money(jpy, 500));
  });

  test('wrong input maps to the right error', () {
    expect(parseAmount('', egp).error, TxnFormError.amountRequired);
    expect(parseAmount('abc', egp).error, TxnFormError.amountRequired);
    expect(parseAmount('0', egp).error, TxnFormError.amountRequired);
    expect(parseAmount('1.234', egp).error, TxnFormError.amountDecimals);
    expect(parseAmount('5.5', jpy).error, TxnFormError.amountDecimals);
    expect(
      parseAmount('99999999999999999', egp).error,
      anyOf(TxnFormError.amountTooLarge, TxnFormError.amountRequired),
    );
  });

  Map<TxnField, TxnFormError> check({
    TxnEditType type = TxnEditType.expense,
    String amount = '10',
    String? category = 'food',
    String? account = 'a',
    String? to,
    CivilDate? date,
    String note = '',
  }) => validateForm(
    type: type,
    amountText: amount,
    currency: egp,
    categoryId: category,
    accountId: account,
    toAccountId: to,
    date: date ?? CivilDate(2026, 11, 13),
    today: CivilDate(2026, 11, 13),
    note: note,
  );

  test('required fields and date rule', () {
    expect(check(), isEmpty);
    expect(
      check(category: null)[TxnField.category],
      TxnFormError.categoryRequired,
    );
    expect(
      check(account: null)[TxnField.account],
      TxnFormError.accountRequired,
    );
    expect(
      check(date: CivilDate(2026, 11, 14))[TxnField.date],
      TxnFormError.dateFuture,
    );
  });

  test('transfer needs two different accounts and no category', () {
    expect(check(type: TxnEditType.transfer, category: null, to: 'b'), isEmpty);
    expect(
      check(type: TxnEditType.transfer, to: 'a')[TxnField.to],
      TxnFormError.sameAccount,
    );
    expect(
      check(type: TxnEditType.transfer)[TxnField.to],
      TxnFormError.toAccountRequired,
    );
  });
}
