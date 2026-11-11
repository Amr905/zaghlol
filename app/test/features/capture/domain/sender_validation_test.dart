// T-047 test plan 8 (pure part): user sender validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/domain/sender_validation.dart';

void main() {
  SenderRefusal? note(String v, {int existing = 0}) => validateUserSender(
    UserSenderChannel.notification,
    v,
    existingNotificationSenders: existing,
  );

  test('a package-shaped notification sender is accepted', () {
    expect(note('com.synthetic.bank'), isNull);
  });

  test('bad shapes are refused: no dot, upper case, spaces, Arabic digits, '
      'userinfo-like, empty, too long', () {
    for (final v in [
      'synthetic',
      'Com.Synthetic.Bank',
      'com.synthetic bank',
      'com.synthetic.١',
      'com.synthetic.bank@evil',
      'com..bank',
      '.com.bank',
    ]) {
      expect(note(v), SenderRefusal.badShape, reason: v);
    }
    expect(note(''), SenderRefusal.badShape);
    expect(note('com.${'a' * 200}'), SenderRefusal.tooLong);
  });

  test('deny-listed apps (messaging, mail, social, browser, dialer, SMS) '
      'are refused', () {
    for (final v in [
      'com.whatsapp',
      'org.telegram.messenger',
      'com.google.android.gm',
      'com.google.android.apps.messaging',
      'com.android.chrome',
      'com.android.providers.telephony',
      'com.samsung.android.messaging',
    ]) {
      expect(note(v), SenderRefusal.denyListed, reason: v);
    }
  });

  test('the 11th notification sender is refused (cap 10)', () {
    expect(note('com.synthetic.bank', existing: 9), isNull);
    expect(
      note('com.synthetic.bank', existing: kMaxNotificationUserSenders),
      SenderRefusal.tooMany,
    );
  });

  test('SMS senders: ids and numbers pass; control and bidi characters '
      'do not', () {
    SenderRefusal? sms(String v) =>
        validateUserSender(UserSenderChannel.sms, v);
    expect(sms('MYBANK'), isNull);
    expect(sms('5550100'), isNull);
    expect(sms('البنك'), isNull);
    expect(sms('A‮B'), SenderRefusal.badShape);
    expect(sms('A\u0000B'), SenderRefusal.badShape);
    expect(sms('A​B'), SenderRefusal.badShape);
  });
}
