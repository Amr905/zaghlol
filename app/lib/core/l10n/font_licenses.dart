import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Package name shown on the licences screen for the bundled font.
const String kFontLicensePackage = 'IBM Plex Sans Arabic';

/// Asset holding the SIL OFL 1.1 text and the IBM copyright line.
const String kFontLicenseAsset = 'assets/fonts/OFL.txt';

bool _registered = false;

/// Adds the bundled font's licence to Flutter's [LicenseRegistry], so the
/// licences screen lists it. Idempotent; the text is read lazily.
void registerFontLicenses({AssetBundle? bundle}) {
  if (_registered && bundle == null) return;
  _registered = bundle == null;
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(kFontLicenseAsset);
    yield LicenseEntryWithLineBreaks(<String>[kFontLicensePackage], text);
  });
}
