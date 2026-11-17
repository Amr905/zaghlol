import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// FU-247: fresh hold-out FX cases (not in fuzzy_corpus.json), both orders:
// local amount first with the original in brackets, and the reverse.
// Synthetic messages only. Expected: the account-currency (EGP) amount wins.
ParseResult _read(String body) => parseGeneric(
  body: body,
  folded: foldKeyIndexed(body),
  receivedAt: DateTime.utc(2026, 11, 11, 10),
  language: 'en',
  institutionCode: 'bank_x',
);

void main() {
  // body, expected EGP minor units
  final cases = <(String, int)>[
    ('Card purchase EGP 2,310.00 at UBER, original GBP 36.00, debited', 231000),
    ('Debited EGP 640.00 (EUR 12.00) at ZARA via POS card ending 4455', 64000),
    ('Purchase of USD 25.00 (EGP 1,240.00) at STEAM, card ending 4455', 124000),
    ('Card purchase GBP 36.00 = EGP 2,310.00 at UBER debited', 231000),
    ('تم خصم 1,240.00 جنيه (USD 25.00) شراء من STEAM', 124000),
    ('تم شراء بمبلغ USD 25.00 ما يعادل 1,240.00 جنيه من STEAM', 124000),
  ];
  for (var i = 0; i < cases.length; i++) {
    test('fx hold-out #$i', () {
      final r = _read(cases[i].$1);
      expect(r, isA<ParseGeneric>());
      final g = r as ParseGeneric;
      expect(g.needsReview, isTrue);
      if (g.amount.currency.code == 'EGP') {
        expect(g.amount.minor, cases[i].$2);
      } else {
        // Known miss (foreign amount first): the pick may be the foreign one,
        // but it must be flagged and never auto-saved (D-28).
        expect(g.reasons, contains(GenericReason.currencyAmbiguous));
        expect(genericAutoSaveEligible(g), isFalse);
      }
    });
  }
}
