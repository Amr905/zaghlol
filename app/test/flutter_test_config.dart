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
/// Loads the real IBM Plex Sans Arabic faces from `assets/fonts/` only when
/// `REAL_FONTS` or `DESIGN_SHOTS` is set in the environment (design shots,
/// goldens regenerated with real glyphs). Normal runs use the built-in Ahem
/// test font: it is host independent, and the pixel-sampling a11y contrast
/// checks are measured against solid glyph boxes, not anti-aliased text.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader(kZFontFamily);
  var found = 0;
  final real =
      Platform.environment.containsKey('REAL_FONTS') ||
      Platform.environment.containsKey('DESIGN_SHOTS');
  for (final name in _plexFaces) {
    final file = File('assets/fonts/$name');
    if (real && file.existsSync()) {
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
