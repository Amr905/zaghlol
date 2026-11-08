import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';

/// File names of the bundled IBM Plex Sans Arabic faces (400/500/600/700).
const _plexFaces = <String>[
  'IBMPlexSansArabic-Regular.ttf',
  'IBMPlexSansArabic-Medium.ttf',
  'IBMPlexSansArabic-SemiBold.ttf',
  'IBMPlexSansArabic-Bold.ttf',
];

/// Global setup for every test in `app/test`.
///
/// Loads the real IBM Plex Sans Arabic faces from `assets/fonts/` when the
/// files are present, so goldens use the final glyphs. When they are absent
/// (the font files are added as a separate step, see app/README.md) the tests
/// fall back to the built-in Ahem test font, which is host independent.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader(kZFontFamily);
  var found = 0;
  for (final name in _plexFaces) {
    final file = File('assets/fonts/$name');
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      found++;
    }
  }
  if (found > 0) {
    await loader.load();
  }
  await testMain();
}
