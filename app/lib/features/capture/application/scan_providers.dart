// T-161: providers behind S-32 and the shared-item pickup (FU-211).

import 'package:flutter/foundation.dart' as f show defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';
import '../../../core/ocr/unavailable_ocr_engine.dart';
import '../../../core/platform/pigeon_ocr.dart';
import '../../budget/application/budget_providers.dart' show localZoneProvider;
import '../../transactions/data/transactions_providers.dart' show clockProvider;
import 'capture_providers.dart' show captureRegistryLoaderProvider;
import 'scan_service.dart';

/// On-device OCR. iOS has the Vision host (T-160); Android answers
/// NOT_AVAILABLE until its host (T-159) lands, then only this provider
/// changes.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => f.defaultTargetPlatform == TargetPlatform.iOS
      ? PigeonOcrEngine()
      : const UnavailableOcrEngine(),
  name: 'ocrEngineProvider',
);

/// Lets the user pick an image from the photo library and returns the path of
/// its encrypted copy in the OCR host's spool, or null when the user
/// cancelled. No picker is wired yet (see the T-161 task file); until then the
/// Scan entry explains that choosing an image is not available.
typedef ScanImagePicker = Future<String?> Function();

final scanImagePickerProvider = Provider<ScanImagePicker?>(
  (ref) => null,
  name: 'scanImagePickerProvider',
);

final scanServiceProvider = Provider<ScanService>((ref) {
  final registry = ref.watch(captureRegistryLoaderProvider)();
  final clock = ref.watch(clockProvider);
  final zone = ref.watch(localZoneProvider);
  return ScanService(
    engine: ref.watch(ocrEngineProvider),
    pipeline: ParsingPipeline(registry),
    wallClock: () {
      final utc = clock().toUtc();
      return utc.add(
        Duration(minutes: zone.offsetAtInstant(utc.millisecondsSinceEpoch)),
      );
    },
  );
}, name: 'scanServiceProvider');
