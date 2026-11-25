import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  test('names, phones, IBANs and merchants never survive', () {
    const bodies = [
      'Dear Mohamed Hassan, EGP 1,250.00 debited at Carrefour Maadi '
          'card 4321 to 01001234567',
      'تم خصم 500 جنيه من حسابك لصالح احمد محمود السيد رقم 01012345678',
      'Transfer to EG380019000500000000263180002 Sherif Zaki completed',
      'صرفت ٣٠٠ جنيه عند سبينيس التجمع',
    ];
    const secrets = [
      'mohamed',
      'hassan',
      'carrefour',
      'maadi',
      'sherif',
      'zaki',
      'احمد',
      'محمود',
      'السيد',
      'سبينيس',
      'التجمع',
      'EG38',
      '0100',
      '4321',
      '1250',
      '500',
      '300',
      '٣٠٠',
      '0101',
    ];
    for (final b in bodies) {
      final s = shapeSignature(b).toLowerCase();
      expect(RegExp(r'[0-9٠-٩]').hasMatch(s.replaceAll('9', '')), isFalse);
      for (final x in secrets) {
        expect(s.contains(x.toLowerCase()), isFalse, reason: x);
      }
    }
  });

  test('keeps cue words, collapses runs, caps length', () {
    final s = shapeSignature('EGP 100 debited at Foo Bar Baz');
    expect(s, contains('debited'));
    expect(s, isNot(contains('foo')));
    expect(s, contains('A'));
    expect(shapeSignature('Foo Bar Baz'), 'A');
    expect(shapeSignature('1 22 333'), '9');
    expect(shapeSignature('x ' * 500).length, lessThanOrEqualTo(80));
    expect(shapeSignature(''), '');
  });

  test(
    'T-248: a Title Case or ALL CAPS name equal to a cue word is masked',
    () {
      // Cue words survive in lower case; the same words as names do not.
      final lower = shapeSignature('payment received');
      expect(lower, contains('payment'));
      for (final b in ['Payment received', 'PAYMENT received']) {
        final sig = shapeSignature(b);
        expect(sig, isNot(contains('payment')), reason: b);
        expect(sig, contains('received'));
      }
    },
  );
}
