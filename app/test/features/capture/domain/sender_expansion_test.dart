// SMS-device: regex registry senders (HSBC) become concrete inbox addresses.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/sender_expansion.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  const hsbc = r'^hsbc(?:[ ._-]?(?:eg|egy|egypt|bank))?$';

  test('HSBC regex lists every address it matches (and Title Case)', () {
    final out = expandSenderRegex(hsbc)!;
    expect(
      out,
      containsAll([
        'hsbc',
        'Hsbc',
        'hsbc eg',
        'Hsbc Eg',
        'hsbc-egypt',
        'hsbc.bank',
        'hsbc_egy',
        'hsbceg',
      ]),
    );
    final re = RegExp(hsbc);
    for (final a in out) {
      expect(re.hasMatch(foldKey(a)), isTrue, reason: 'address $a');
    }
  });

  test('literals, groups and optional parts', () {
    expect(
      expandSenderRegex(r'^ab(?:c|d)?$'),
      containsAll(['ab', 'abc', 'abd']),
    );
    expect(expandSenderRegex(r'^a\.b$'), contains('a.b'));
  });

  test('anything outside the grammar is not expanded', () {
    expect(expandSenderRegex(r'^bank.*$'), isNull);
    expect(expandSenderRegex(r'^[a-z]+$'), isNull);
    expect(expandSenderRegex(r'^(a|b)$'), isNull);
    expect(expandSenderRegex(r'^x{2}$'), isNull);
    expect(expandSenderRegex(''), isNull);
  });

  test('too many addresses is not expanded', () {
    expect(expandSenderRegex(r'^[abcdefgh][abcdefgh][abcdefgh]$'), isNull);
  });
}
