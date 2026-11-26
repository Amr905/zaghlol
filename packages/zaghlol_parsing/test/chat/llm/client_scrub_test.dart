// T-278: ClientScrub (FR-LLM-03). Synthetic numbers and addresses only.

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  group('ClientScrub', () {
    test('FR-LLM-03 example: phone and IPA gone, question kept', () {
      final r = ClientScrub.apply(
        'حولت لـ 01000000000 و ahmed@instapay، صرفت كام بكارت 1234؟',
      );
      expect(r.text, 'حولت لـ ⟦PHONE⟧ و ⟦IPA⟧، صرفت كام بكارت 1234؟');
      expect(r.text, contains('صرفت كام'));
      expect(
        [for (final t in r.tokens) t.kind],
        [ScrubKind.phone, ScrubKind.ipa],
      );
    });

    final cases = <String, String>{
      // phones, Arabic-Indic digits, separators, +20
      'ابعت على ٠١٠٠١٢٣٤٥٦٧ دلوقتي': 'ابعت على ⟦PHONE⟧ دلوقتي',
      'call +20 100 123 4567 now': 'call ⟦PHONE⟧ now',
      'call 0100-123-4567 now': 'call ⟦PHONE⟧ now',
      'call 0020 1001234567': 'call ⟦PHONE⟧',
      'landline 02 2345 6789': 'landline ⟦PHONE⟧',
      // e-mail and addresses
      'mail Test.User+x@Example.co.uk please': 'mail ⟦EMAIL⟧ please',
      'احمد@instapay ابعتله': '⟦IPA⟧ ابعتله',
      'to someone@bank.': 'to ⟦IPA⟧.',
      // card / account numbers
      'card 4111 1111 1111 1111 spent': 'card ⟦NUMBER⟧ spent',
      'card 4111-1111-1111-1111 spent': 'card ⟦NUMBER⟧ spent',
      'حساب ١٢٣٤٥٦٧٨٩٠١٢ كام': 'حساب ⟦NUMBER⟧ كام',
      'acct 12345678': 'acct ⟦NUMBER⟧',
      // kept: amounts, short runs, dates, percentages
      'صرفت 4321 جنيه': 'صرفت 4321 جنيه',
      'spent 1,500,000 EGP': 'spent 1,500,000 EGP',
      'since 2025-07-01 about 25%': 'since 2025-07-01 about 25%',
      'عن 1234567 جنيه': 'عن 1234567 جنيه',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(ClientScrub.apply(input).text, expected));
    });

    test('typed brackets cannot forge a token', () {
      expect(ClientScrub.apply('⟦CARD_1⟧ x ⟦PHONE⟧').text, 'CARD_1 x PHONE');
    });

    test('repeated and mixed items keep their kinds in order', () {
      final r = ClientScrub.apply('a@b.com 01000000000 a@b.com 99999999');
      expect(
        [for (final t in r.tokens) t.kind],
        [ScrubKind.email, ScrubKind.phone, ScrubKind.email, ScrubKind.number],
      );
    });

    test('toString is redacted', () {
      final r = ClientScrub.apply('call 01000000000');
      expect(r.toString(), isNot(contains('0100')));
    });
  });
}
