// Real-text rendering for design review: loads the bundled IBM Plex Sans
// Arabic faces (OFL 1.1) so a test paints real Arabic, not Ahem boxes.
// `flutter_test_config.dart` already does this for every test; call
// [loadRealFonts] when a test must not depend on that (it is idempotent).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';

const realFontFiles = <String>[
  'IBMPlexSansArabic-Regular.ttf',
  'IBMPlexSansArabic-Medium.ttf',
  'IBMPlexSansArabic-SemiBold.ttf',
  'IBMPlexSansArabic-Bold.ttf',
];

bool _loaded = false;

/// Registers the faces under [kZFontFamily]. Throws when a file is missing, so
/// a design shot never silently falls back to boxes.
Future<void> loadRealFonts() async {
  if (_loaded) return;
  final loader = FontLoader(kZFontFamily);
  for (final name in realFontFiles) {
    final file = File('assets/fonts/$name');
    if (!file.existsSync()) {
      throw StateError('Missing font file ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  // Icons: the SDK's Material Icons font, so shots show glyphs, not boxes.
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
  }
  _loaded = true;
}
