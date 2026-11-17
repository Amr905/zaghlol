import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// SMS-AUTO: credit-card settlement cues and the auto-save eligibility rule.
// Synthetic messages only.
ParseResult _read(String body, {String? inst = 'bank_x'}) => parseGeneric(
  body: body,
  folded: foldKeyIndexed(body),
  receivedAt: DateTime.utc(2026, 11, 11, 10),
  language: 'en',
  institutionCode: inst,
);

void main() {
  _fixMajors();
  group('settlement', () {
    final received = <String>[
      'Payment of EGP 5,000.00 received on your credit card ending 1234',
      'We have received your payment of EGP 5000.00 on your credit card '
          'ending with * 1234. Thank you',
      'تم استلام سداد بمبلغ 5000.00 جم على بطاقة الائتمان المنتهية بـ 1234',
    ];
    for (final b in received) {
      test('received side is a transfer in: $b'.substring(0, 40), () {
        final r = _read(b) as ParseGeneric;
        expect(r.event, GenericEvent.ccPayment);
        expect(r.direction, TemplateDirection.income);
        expect(r.last4, '1234');
        expect(genericAutoSaveEligible(r), isTrue);
      });
    }

    test('paying side needs a debit word, then it is a transfer out', () {
      final r = _read(
        'EGP 2,000.00 was debited from your account *9876 for '
        'credit card payment ending 1234',
      ) as ParseGeneric;
      expect(r.event, GenericEvent.ccPayment);
      expect(r.direction, TemplateDirection.expense);
    });

    test('a shop receiving a payment is not a card settlement', () {
      final r =
          _read('Payment of EGP 100.00 received. Thank you') as ParseGeneric;
      expect(r.event, isNot(GenericEvent.ccPayment));
    });
  });

  group('genericAutoSaveEligible', () {
    test('clear debit from a known bank with merchant: yes', () {
      final r = _read(
        'EGP 250.00 was debited from your account *4567 at SHOP',
      ) as ParseGeneric;
      expect(genericAutoSaveEligible(r), isTrue);
    });

    test('unknown sender: no', () {
      final r = _read(
        'EGP 250.00 was debited from your account *4567 at SHOP',
        inst: null,
      ) as ParseGeneric;
      expect(genericAutoSaveEligible(r), isFalse);
    });

    test('no direction: no', () {
      final r =
          _read('EGP 250.00 on your account *4567 at SHOP') as ParseGeneric;
      expect(genericAutoSaveEligible(r), isFalse);
    });

    test('two currencies, no cue: no', () {
      final r = _read(
        'Account *4567 debited at SHOP. EGP 250.00 and USD 5.00',
      ) as ParseGeneric;
      expect(genericAutoSaveEligible(r), isFalse);
    });

    test('a USD charge with an EGP limit is not ambiguous', () {
      final r = _read(
        'Your Credit Card ending with * 5075 has been used for USD '
        '114.00 on 09/11/2026 at ANTHROPIC* CLAUDE SUB. Your '
        'available limit is EGP 110095.29',
      ) as ParseGeneric;
      expect(r.reasons, isNot(contains(GenericReason.currencyAmbiguous)));
      expect(r.amount.currency.code, 'USD');
      expect(genericAutoSaveEligible(r), isTrue);
    });
  });
}

void _fixMajors() {
  group('SMS-AUTO review fixes', () {
    // body, expected minor units, merchant key, event, direction, auto-save.
    final cases =
        <(String, int, String, GenericEvent?, TemplateDirection?, bool)>[
          (
            'Your card ending 1234 was used for a payment of EGP 500.00 at VODAFONE. Thank you for banking with NBE',
            50000,
            'vodafone',
            GenericEvent.purchase,
            TemplateDirection.expense,
            true,
          ),
          (
            'Purchase of EGP 750.00 at AMAZON on your card ending 1234. Thank you for your payment',
            75000,
            'amazon',
            null,
            null,
            false,
          ),
          (
            'Payment of EGP 900.00 at CARREFOUR with your card ending 1234 was reversed and credited',
            90000,
            'carrefour',
            null,
            null,
            false,
          ),
        ];
    for (final c in cases) {
      test('reads and gates: ${c.$1.substring(0, 30)}', () {
        final r = _read(c.$1);
        expect(r, isA<ParseGeneric>());
        final g = r as ParseGeneric;
        expect(g.amount.minor, c.$2);
        expect(g.amount.currency.code, 'EGP');
        expect(g.merchant?.key, c.$3);
        expect(g.last4, '1234');
        expect(g.event, c.$4);
        expect(g.direction, c.$5);
        expect(genericAutoSaveEligible(g), c.$6);
      });
    }
    test('cashback promo is not auto-saved', () {
      final r = _read(
        'Get 10% cashback! Pay EGP 500 with your card ending 1234 at NOON before 30/11',
      );
      expect(r is ParseGeneric && genericAutoSaveEligible(r), isFalse);
    });
  });
}
