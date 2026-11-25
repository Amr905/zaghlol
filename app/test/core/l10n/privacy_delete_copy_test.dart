import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_ar.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations_en.dart';

void main() {
  test('FU-039: delete body makes no security-keys claim (ar + en)', () {
    final en = AppLocalizationsEn().privacyDeleteBody.toLowerCase();
    expect(en, isNot(contains('key')));
    expect(AppLocalizationsAr().privacyDeleteBody, isNot(contains('مفاتيح')));
  });

  test('FU-040: backups, purchase and account stay (ar + en)', () {
    final en = AppLocalizationsEn();
    final ar = AppLocalizationsAr();
    expect(
      en.privacyDeleteBackupsKept,
      'Your backups on Google Drive or iCloud stay there. '
      'Delete them from there if you want.',
    );
    expect(
      en.privacyDeleteStoreAccountKept,
      "Your store purchase and your account aren't touched.",
    );
    expect(
      ar.privacyDeleteBackupsKept,
      'النسخ الاحتياطية اللي على Google Drive أو iCloud هتفضل زي ما هي. '
      'لو عايز تمسحها، امسحها من هناك.',
    );
    expect(
      ar.privacyDeleteStoreAccountKept,
      'شراءك من المتجر وحسابك مش هيتأثروا.',
    );
  });
}
