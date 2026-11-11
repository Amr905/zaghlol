// T-046 §3: body_hash v1 golden vectors (cross-checked with Python's
// hashlib) and the frozen hashNorm. Changing any expectation here means a
// migration that re-hashes raw_messages. Synthetic text only.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';

void main() {
  group('golden vectors (FROZEN)', () {
    const vectors = [
      (
        'sms',
        'NBE',
        'Synthetic purchase EGP 120.50 card *4321',
        '504c5fa8aa1d4a460906bdb940d3714b40d3f993aeb5286ebee132d5ac986b76',
      ),
      (
        'sms',
        ' nbe ',
        'Synthetic purchase EGP 120.50 card *4321',
        '504c5fa8aa1d4a460906bdb940d3714b40d3f993aeb5286ebee132d5ac986b76',
      ),
      (
        'notification',
        'com.example.bank',
        'تم خصم ١٢٠٫٥٠ جم',
        '5ba327e5ffe69c1313a5f7de347d734a30cb27a57701a64016344f7718f48c5c',
      ),
      (
        'sms',
        'BANK-X',
        '',
        '7d71e646c3e692feed0537a0e0b7e1e90ae9358d07d5a79578117f096cec6bc0',
      ),
    ];
    for (final (channel, source, body, hash) in vectors) {
      test('$channel / ${source.trim()}', () {
        expect(
          bodyHashV1(senderKey: senderKeyOf(channel, source), body: body),
          hash,
        );
      });
    }
  });

  group('hashNorm', () {
    test('Arabic-Indic and Extended digits, decimal and thousands marks', () {
      expect(hashNorm('١٬٢٥٠٫٠٠ ۱۲۳'), '1,250.00 123');
    });

    test('invisible marks removed', () {
      expect(
        hashNorm('a\u200bb\u200fc\u202ad\u2066e\u061cf\u2060g\u00adh\ufeffi'),
        'abcdefghi',
      );
    });

    test('whitespace runs (incl. NBSP, narrow NBSP, line breaks) → one '
        'space, trimmed', () {
      expect(
        hashNorm('  a \t\n\r b\u00a0\u202fc\u2028\u2029d\u0085e  '),
        'a b c d e',
      );
    });

    test('no case or letter folding (frozen: independent of the parser)', () {
      expect(hashNorm('ZBANK أإآ ى ة ـ'), 'ZBANK أإآ ى ة ـ');
    });

    test('a mark between spaces does not split the run', () {
      expect(hashNorm('a \u200b b'), 'a b');
    });
  });

  group('senderKeyOf', () {
    test('notification packages are only trimmed (case kept)', () {
      expect(senderKeyOf('notification', ' Com.Bank.App '), 'Com.Bank.App');
    });

    test('SMS ids are folded like the Guard', () {
      expect(senderKeyOf('sms', ' NBE '), 'nbe');
      expect(senderKeyOf('sms', 'بنك١'), 'بنك1');
    });

    test('channels the Guard does not know fold like SMS', () {
      expect(senderKeyOf('paste', 'Clip'), 'clip');
    });
  });

  test('the receive time is not part of the hash; sender is', () {
    final a = bodyHashV1(senderKey: 'nbe', body: 'x');
    expect(bodyHashV1(senderKey: 'nbe', body: ' x '), a);
    expect(bodyHashV1(senderKey: 'cib', body: 'x'), isNot(a));
    expect(bodyHashV1(senderKey: 'nb', body: 'ex'), isNot(a));
  });
}
