// T-161: providers behind S-32 and the shared-item pickup (FU-211).

import 'dart:io' show File;

import 'package:flutter/foundation.dart' as f show defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';
import '../../../core/ocr/unavailable_ocr_engine.dart';
import '../../../core/platform/pigeon_ocr.dart';
import '../../budget/application/budget_providers.dart' show localZoneProvider;
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import 'capture_providers.dart' show captureRegistryLoaderProvider;
import 'scan_diagnostics.dart';
import 'scan_service.dart';

/// On-device OCR through the platform host: Vision on iOS (T-160), Tesseract
/// `ara` plus ML Kit Latin on Android (T-159). Images are sealed in the
/// host's encrypted spool, deleted after OCR, and nothing is uploaded. Other
/// platforms (tests, desktop) answer NOT_AVAILABLE.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => switch (f.defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => PigeonOcrEngine(),
    _ => const UnavailableOcrEngine(),
  },
  name: 'ocrEngineProvider',
);

/// Lets the user pick an image from the photo library and returns the path of
/// its encrypted copy in the OCR host's spool, or null when the user
/// cancelled. Throws [OcrException] when sealing is not available.
typedef ScanImagePicker = Future<String?> Function();

final scanImagePickerProvider = Provider<ScanImagePicker?>((ref) {
  final engine = ref.watch(ocrEngineProvider);
  return () async {
    // Gallery only: the system Photo Picker (Android 13+) or PHPicker (iOS),
    // so the app never holds a photo-library permission.
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
    } on Object {
      return null;
    }
    if (picked == null) return null;
    try {
      // The host seals it into the encrypted spool and deletes the plain file.
      return await engine.sealImage(picked.path);
    } finally {
      // Also when sealing failed or no host exists: no plain copy stays.
      try {
        final f = File(picked.path);
        if (f.existsSync()) f.deleteSync();
      } on Object {
        // Best effort; the OS clears the cache directory.
      }
    }
  };
}, name: 'scanImagePickerProvider');

/// Outcome counters of this session (dev builds read them; no text inside).
final scanDiagnosticsProvider = Provider<ScanDiagnostics>(
  (ref) => ScanDiagnostics(),
  name: 'scanDiagnosticsProvider',
);

final scanServiceProvider = Provider<ScanService>((ref) {
  final registry = ref.watch(captureRegistryLoaderProvider)();
  final clock = ref.watch(clockProvider);
  final zone = ref.watch(localZoneProvider);
  return ScanService(
    engine: ref.watch(ocrEngineProvider),
    pipeline: ParsingPipeline(registry),
    diagnostics: ref.watch(scanDiagnosticsProvider),
    wallClock: () {
      final utc = clock().toUtc();
      return utc.add(
        Duration(minutes: zone.offsetAtInstant(utc.millisecondsSinceEpoch)),
      );
    },
  );
}, name: 'scanServiceProvider');
