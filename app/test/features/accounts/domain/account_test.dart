// T-045: kind inference and digit normalisation (pure Dart). Synthetic data.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';

void main() {
  group('inferAccountKind', () {
    test('an explicit kind wins over every hint', () {
      expect(
        inferAccountKind(
          event: 'cc_payment',
          balanceIsAvailableLimit: true,
          explicit: AccountKind.wallet,
        ),
        AccountKind.wallet,
      );
    });

    test('available-limit balance or cc_payment means credit', () {
      expect(
        inferAccountKind(event: 'card_purchase', balanceIsAvailableLimit: true),
        AccountKind.credit,
      );
      expect(inferAccountKind(event: 'cc_payment'), AccountKind.credit);
    });

    test('bnpl, wallet and fx events', () {
      expect(inferAccountKind(event: 'bnpl_installment'), AccountKind.bnpl);
      expect(inferAccountKind(event: 'wallet_topup'), AccountKind.wallet);
      expect(
        inferAccountKind(event: 'fx_conversion'),
        AccountKind.multiCurrency,
      );
    });

    test('card events with a last-4 are debit, without it an account', () {
      for (final e in [
        'card_purchase',
        'card_purchase_fx',
        'atm_withdrawal',
        'pending_auth',
        'settled',
      ]) {
        expect(inferAccountKind(event: e, hasLast4: true), AccountKind.debit);
        expect(inferAccountKind(event: e), AccountKind.account);
      }
    });

    test('transfers, salary, balance-only, unknown and no event', () {
      for (final e in [
        'instapay_in',
        'transfer_out',
        'salary',
        'balance_only',
        'nonsense',
        null,
      ]) {
        expect(inferAccountKind(event: e, hasLast4: true), AccountKind.account);
      }
    });
  });

  group('AccountKind', () {
    test('codes round-trip and an unknown code is a corrupt row', () {
      for (final k in AccountKind.values) {
        expect(AccountKind.fromCode(k.code), k);
      }
      expect(
        () => AccountKind.fromCode('nope'),
        throwsA(
          isA<AccountsException>().having(
            (e) => e.code,
            'code',
            AccountsException.corruptRow,
          ),
        ),
      );
    });

    test('credit and bnpl are not asset kinds', () {
      expect(AccountKind.values.where((k) => !k.isAsset), [
        AccountKind.credit,
        AccountKind.bnpl,
      ]);
    });
  });

  group('normalizeDigits', () {
    test('Arabic-Indic and Extended Arabic-Indic digits become ASCII', () {
      expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
      expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
      expect(normalizeDigits('١٢a٣'), '12a3');
      expect(normalizeDigits(''), '');
    });
  });
}
