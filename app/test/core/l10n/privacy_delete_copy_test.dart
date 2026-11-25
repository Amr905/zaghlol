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
    expect(en.privacyDeleteBackupsKept, contains('stay'));
    expect(en.privacyDeleteStoreAccountKept, contains("aren't touched"));
    expect(AppLocalizationsAr().privacyDeleteBackupsKept, contains('هتفضل'));
    expect(
      AppLocalizationsAr().privacyDeleteStoreAccountKept,
      contains('مش هيتأثروا'),
    );
  });
}
