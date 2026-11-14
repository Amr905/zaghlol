// Pigeon contract: iCloud backup host (T-151). Contract:
// docs/03-technical/platform-channels.md §5 (ICloudBackupHostApi); design:
// docs/04-tasks/tasks/T-151.md "Design note". Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
//
// Rules for the native side (iOS only; Android never registers it):
// - Files live in the ubiquity container's `Documents/Backups/`. Only names
//   matching the backup patterns (final `zaghlol-backup-<seq>-<ms>.zaghlol.enc`
//   or the same + `.partial`) are ever written, moved, read or deleted.
// - The bytes are already encrypted (ADR-011). Nothing is logged; errors are
//   code-only `IcloudApiError`s (message and details null): ICLOUD_UNAVAILABLE,
//   INVALID_ARGUMENT, NOT_FOUND, ALREADY_EXISTS, UPLOAD_UNVERIFIED, TOO_LARGE,
//   TIMEOUT, IO_ERROR.
// - All calls run on one serial background queue (never the main thread).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/icloud_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/icloud/IcloudApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.icloud',
      errorClassName: 'IcloudApiError',
    ),
    swiftOut: 'ios/Runner/Platform/IcloudApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'IcloudApiError'),
  ),
)
/// One file in `Documents/Backups/` (our names only). Metadata from iCloud,
/// not authenticated: the restore authenticates the content.
class BackupMeta {
  BackupMeta({
    required this.name,
    required this.isUploaded,
    required this.isDownloaded,
    required this.quotaExceeded,
    required this.uploadFailed,
  });

  String name;

  /// Logical size in bytes; null when iCloud does not report it.
  int? sizeBytes;

  /// File-system creation time (ms since epoch, the creating device's clock);
  /// null when unknown.
  int? createdAtMs;

  /// iCloud reports the item's data as uploaded to the server.
  bool isUploaded;

  /// The current version is on this phone.
  bool isDownloaded;

  /// The last upload attempt failed because the user's iCloud is full.
  bool quotaExceeded;

  /// The last upload attempt failed for another reason.
  bool uploadFailed;

  /// Lowercase hex MD5 of the final file, read back after the move. Set only
  /// by `upload`.
  String? md5;
}

@HostApi()
abstract class ICloudBackupHostApi {
  /// True when an iCloud account is signed in and the app's ubiquity
  /// container can be opened. Never throws for "off": false.
  @async
  bool isAvailable();

  /// Copies the local file at [path] to `Backups/<name>.partial`, reads it back
  /// and compares the MD5 with the source, then moves it to `Backups/<name>`
  /// (never replacing an existing file). [name] must be a final backup name.
  @async
  BackupMeta upload(String path, String name);

  /// A complete listing of our files in `Backups/` (finals and partials,
  /// downloaded or not). Fails rather than return a partial listing.
  @async
  List<BackupMeta> list();

  /// Downloads `Backups/<name>` if needed and copies it into the app's temp
  /// directory; returns that copy's path. The caller deletes it.
  @async
  String download(String name);

  /// Deletes `Backups/<name>` (a final or partial backup name).
  @async
  void delete(String name);
}
