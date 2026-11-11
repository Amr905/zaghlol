// T-047 (design note §1, "Senders"): what may become a user-chosen capture
// sender. A notification user sender is a package name, and then the whole
// notification stream of that app is captured, so the shape is strict, a
// deny list refuses messaging/mail/social/browser/dialer/SMS apps and the
// count is capped. Everything else is refused before any DB write. The UI
// that asks (picker, confirm step naming the app) belongs to T-056/S-61.

/// PO Q3 (provisional, PO to confirm): at most this many notification user
/// senders.
const int kMaxNotificationUserSenders = 10;

/// PO Q3 (provisional): notification user senders are allowed at all.
const bool kNotificationUserSendersAllowed = true;

enum UserSenderChannel { sms, notification }

/// Why a sender was refused (a code, never the value).
enum SenderRefusal { notAllowed, badShape, denyListed, tooMany, tooLong }

/// Longest accepted sender (the Guard value limit is 128).
const int kMaxUserSenderLength = 128;

final RegExp _packageShape = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');

/// Bundled deny list (provisional; T-036/T-061 may extend): messaging, mail,
/// social, browser, dialer and SMS apps. Exact package names and prefixes.
const Set<String> kDeniedPackages = {
  'com.whatsapp',
  'com.whatsapp.w4b',
  'org.telegram.messenger',
  'org.thoughtcrime.securesms',
  'com.facebook.orca',
  'com.facebook.katana',
  'com.instagram.android',
  'com.snapchat.android',
  'com.twitter.android',
  'com.zhiliaoapp.musically',
  'com.google.android.gm',
  'com.google.android.apps.messaging',
  'com.google.android.dialer',
  'com.google.android.contacts',
  'com.android.chrome',
  'com.android.mms',
  'com.android.dialer',
  'com.android.contacts',
  'com.android.vending',
  'com.microsoft.office.outlook',
  'com.yahoo.mobile.client.android.mail',
  'com.samsung.android.messaging',
  'com.samsung.android.dialer',
  'org.mozilla.firefox',
  'com.brave.browser',
  'com.opera.browser',
};

const List<String> kDeniedPackagePrefixes = [
  'com.google.android.gm.',
  'com.android.providers.',
  'com.android.server.',
];

/// Returns null when [value] may be stored as a user sender on [channel], or
/// the refusal. [existingNotificationSenders] counts the stored notification
/// user senders (the same sender being re-saved is the caller's concern).
SenderRefusal? validateUserSender(
  UserSenderChannel channel,
  String value, {
  int existingNotificationSenders = 0,
}) {
  if (value.isEmpty || value.length > kMaxUserSenderLength) {
    return value.isEmpty ? SenderRefusal.badShape : SenderRefusal.tooLong;
  }
  switch (channel) {
    case UserSenderChannel.sms:
      // An SMS sender id: printable, no control or bidi characters.
      for (final r in value.runes) {
        final control = r < 0x20 || (r >= 0x7f && r <= 0x9f);
        final bidi =
            (r >= 0x200b && r <= 0x200f) ||
            (r >= 0x202a && r <= 0x202e) ||
            (r >= 0x2066 && r <= 0x2069);
        if (control || bidi) return SenderRefusal.badShape;
      }
      return null;
    case UserSenderChannel.notification:
      if (!kNotificationUserSendersAllowed) return SenderRefusal.notAllowed;
      if (!_packageShape.hasMatch(value)) return SenderRefusal.badShape;
      if (kDeniedPackages.contains(value) ||
          kDeniedPackagePrefixes.any(value.startsWith)) {
        return SenderRefusal.denyListed;
      }
      if (existingNotificationSenders >= kMaxNotificationUserSenders) {
        return SenderRefusal.tooMany;
      }
      return null;
  }
}
