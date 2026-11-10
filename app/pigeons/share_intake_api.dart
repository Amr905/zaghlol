// Pigeon contract: Android share intake (T-060). Added to
// docs/03-technical/platform-channels.md section 2 (share intake). Regenerate
// with app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
//
// Native code validates, size-limits and encrypts every share (text, image,
// PDF, CSV) before Dart sees it. Dart reads the decrypted content in memory,
// shows the confirmation / OCR flow and then discards the share.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/share_intake_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/share/ShareIntakeApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.share',
      errorClassName: 'ShareIntakeApiError',
    ),
    swiftOut: 'ios/Runner/Platform/ShareIntakeApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'ShareIntakeApiError'),
  ),
)
enum ShareKind { text, image, pdf, csv }

enum ShareRejectReason { tooLarge, unsupportedType, unreadable, empty }

/// Metadata only; never contains content.
class ShareDescriptor {
  ShareDescriptor({
    required this.id,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.receivedAtMs,
  });

  String id;
  ShareKind kind;
  String mimeType;
  int sizeBytes;
  int receivedAtMs;
}

/// Decrypted content, in memory only. `text` is set for [ShareKind.text],
/// `bytes` for the other kinds.
class ShareContent {
  ShareContent({required this.descriptor, this.text, this.bytes});

  ShareDescriptor descriptor;
  String? text;
  Uint8List? bytes;
}

@HostApi()
abstract class ShareIntakeHostApi {
  /// Shares waiting for Dart, oldest first. Purges stale ones (older than 24 h).
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<ShareDescriptor> listPendingShares();

  /// Throws `IO_ERROR` (unknown id) or `SPOOL_DECRYPT_FAILED` (entry is deleted).
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  ShareContent readShare(String id);

  /// Deletes the share's files. Idempotent.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void discardShare(String id);

  /// The reason the last share was refused, once; null when there is none.
  ShareRejectReason? takePendingRejection();
}

@FlutterApi()
abstract class ShareIntakeEventsApi {
  void onShareReceived(ShareDescriptor descriptor);

  void onShareRejected(ShareRejectReason reason);
}
