// T-156b: Android uses the T-159 OCR host like iOS.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ocr/unavailable_ocr_engine.dart';
import 'package:zaghlol/core/platform/pigeon_ocr.dart';
import 'package:zaghlol/features/capture/application/scan_providers.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$p gets the platform OCR host', () {
      debugDefaultTargetPlatformOverride = p;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(ocrEngineProvider), isA<PigeonOcrEngine>());
    });
  }

  test('other platforms answer not available', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(ocrEngineProvider), isA<UnavailableOcrEngine>());
  });
}
