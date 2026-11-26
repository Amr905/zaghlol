import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG-016: the launcher icons shipped as Flutter's template logo. These are
/// the MD5 hashes of the template files; the brand icon must replace them.
const _flutterTemplateMd5 = {
  'afe1b655b9f32da22f9a4301bb8e6ba8', // android mipmap-xxhdpi/ic_launcher.png
  'c785f8932297af4acd5f5ccb7630f01c', // ios Icon-App-1024x1024@1x.png
};

void main() {
  test('BUG-016: launcher icons are not the Flutter template icons', () {
    for (final path in [
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png',
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    ]) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      final hash = md5.convert(file.readAsBytesSync()).toString();
      expect(_flutterTemplateMd5, isNot(contains(hash)), reason: path);
    }
  });
}
