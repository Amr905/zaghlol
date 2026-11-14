import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the IBM Plex Sans Arabic OFL is in the LicenseRegistry', () async {
    registerFontLicenses();
    final found = <LicenseEntry>[];
    await for (final e in LicenseRegistry.licenses) {
      if (e.packages.contains(kFontLicensePackage)) found.add(e);
    }
    expect(found, isNotEmpty);
    final text = found
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE'));
    expect(text, contains('IBM'));
  });

  test('the licence asset is bundled', () async {
    final text = await rootBundle.loadString(kFontLicenseAsset);
    expect(text, isNotEmpty);
  });
}
