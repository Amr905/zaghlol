// Pigeon contract: capture (T-004 names; T-008 fills the Android API from
// docs/03-technical/platform-channels.md section 2, unchanged). Regenerate
// with app/tool/generate_pigeon.sh; CI fails when the generated files are
// stale.
//
// Errors are `PlatformException(code)` with a code from platform-channels.md
// section 6 and null message/details. No message body ever appears in an
// error. Native code does OS integration, the Capture Guard and the
// encrypted spool only; parsing is in Dart.
//
// T-008 (SPK-01 spike, devSms only) implements drainSpool, ackSpool,
// scheduleIngestionNow, isIgnoringBatteryOptimizations,
// requestIgnoreBatteryOptimizations and getCapabilities. T-039 adds the
// production host (AndroidCaptureHost: spool, status, writeGuardConfig
// pass-through) and getSpoolStatus / clearSpoolAlerts; writeGuardConfig takes
// the plaintext user part (renamed from encryptedConfig, FU-097 L-2). T-041
// adds holdSpool and SpoolStatus.held (FU-105, platform-channels.md 1.3). Every
// other method answers NOT_AVAILABLE until its owner task (T-040 receiver,
// permission and Guard wiring, T-042 inbox, T-043 notifications).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/capture_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/capture/CaptureApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.capture',
      errorClassName: 'CaptureApiError',
    ),
    swiftOut: 'ios/Runner/Platform/CaptureApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'CaptureApiError'),
  ),
)
/// A paged historical inbox scan; native code filters by sender in SQL.
class InboxQuery {
  InboxQuery({
    required this.sinceEpochMs,
    required this.senderAddresses,
    this.afterCursor,
    required this.pageSize,
  });

  int sinceEpochMs;
  List<String> senderAddresses;
  String? afterCursor;

  /// At most 500.
  int pageSize;
}

class InboxPage {
  InboxPage({required this.items, this.nextCursor, required this.scannedTotal});

  List<RawInboxMessage> items;
  String? nextCursor;
  int scannedTotal;
}

class RawInboxMessage {
  RawInboxMessage({
    required this.address,
    required this.body,
    required this.dateMs,
    this.simSlot,
    required this.providerId,
  });

  String address;
  String body;
  int dateMs;
  int? simSlot;
  String providerId;
}

/// A decrypted spool entry (in memory only). Deleted natively only after
/// Dart acknowledges it with ackSpool, after the DB commit.
class SpoolEntry {
  SpoolEntry({
    required this.id,
    required this.channel,
    required this.source,
    required this.body,
    required this.receivedAtMs,
    this.simSlot,
  });

  String id;
  String channel;
  String source;
  String body;
  int receivedAtMs;
  int? simSlot;
}

/// The Guard config as native code holds it (platform-channels.md 1.1).
enum GuardConfigState { unknown, full, baseOnly, userUnreadable, baseInvalid }

/// Capture alert counters (platform-channels.md 1.3, T-039). Counts never
/// carry content; times are wall-clock epoch ms.
class SpoolStatus {
  SpoolStatus({
    required this.pending,
    required this.seq,
    required this.refusedFull,
    required this.refusedGeneric,
    required this.rateLimited,
    required this.missedNotifications,
    this.firstMissedSmsAtMs,
    required this.decryptDeleted,
    this.keyInvalidatedAtMs,
    required this.guardState,
    required this.held,
  });

  /// Entries waiting in the spool.
  int pending;

  /// Pass back to clearSpoolAlerts (compare-and-clear).
  int seq;
  int refusedFull;
  int refusedGeneric;
  int rateLimited;
  int missedNotifications;

  /// Earliest SMS that was not kept; the inbox catch-up starts here.
  int? firstMissedSmsAtMs;
  int decryptDeleted;

  /// Set when entries written under a lost spool key were found (reported,
  /// never thrown): rewrite the Guard config, run the catch-up.
  int? keyInvalidatedAtMs;
  GuardConfigState guardState;

  /// Held entries (T-041, FU-105): stored in the spool but not storable even
  /// alone; not pending, retried after the next app update. Diagnostics only.
  int held;
}

class CaptureCapabilities {
  CaptureCapabilities({
    required this.smsGranted,
    required this.smsFlavor,
    required this.notificationAccess,
    required this.postNotifications,
    required this.sdkInt,
  });

  bool smsGranted;
  bool smsFlavor;
  bool notificationAccess;
  bool postNotifications;
  int sdkInt;
}

@HostApi()
abstract class AndroidCaptureHostApi {
  CaptureCapabilities getCapabilities();

  /// READ_SMS + RECEIVE_SMS (only in the 'sms' flavor, ADR-004).
  @async
  bool requestSmsPermission();

  void openNotificationAccessSettings();

  bool isIgnoringBatteryOptimizations();

  /// Shown only if live capture is observed to be delayed.
  void requestIgnoreBatteryOptimizations();

  /// The plaintext user part of the Guard config (platform-channels.md 1.1);
  /// native code validates, encrypts with the spool key and writes it.
  /// CONFIG_INVALID | IO_ERROR.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void writeGuardConfig(Uint8List userConfigJson);

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  InboxPage queryInbox(InboxQuery query);

  /// Returns decrypted entries (in memory only), oldest first.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<SpoolEntry> drainSpool(int max);

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void ackSpool(List<String> ids);

  /// Expedited WorkManager.
  void scheduleIngestionNow();

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  SpoolStatus getSpoolStatus();

  /// Zeroes the alert counters if [seq] still matches getSpoolStatus().seq.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clearSpoolAlerts(int seq);

  /// T-041 (FU-105): entries IngestRawMessages could not store even alone
  /// (IngestBatchResult.kept), called after the ack of the rest. Only ids this
  /// engine drained; moved to spool/held/ (platform-channels.md 1.3). IO_ERROR.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void holdSpool(List<String> ids);
}

/// iOS host (T-062): the encrypted spool in the App Group container and the
/// background refresh. Same drain / ack / hold / status semantics as
/// AndroidCaptureHostApi (platform-channels.md 1.3), so the Dart drain is
/// shared. Errors: IO_ERROR | NOT_AVAILABLE (no App Group container).
/// T-061 adds writeGuardConfig and the Shortcut-setup methods (section 3).
@HostApi()
abstract class IosCaptureHostApi {
  /// Returns decrypted entries (in memory only), oldest first.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  List<SpoolEntry> drainSpool(int max);

  /// Only ids this engine drained.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void ackSpool(List<String> ids);

  /// Entries IngestRawMessages could not store even alone; moved to spool/held/.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void holdSpool(List<String> ids);

  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  SpoolStatus getSpoolStatus();

  /// Zeroes the alert counters if [seq] still matches getSpoolStatus().seq.
  @TaskQueue(type: TaskQueueType.serialBackgroundThread)
  void clearSpoolAlerts(int seq);

  /// Submits the BGAppRefreshTask 'app.zaghlol.ingest' (the launch handler is
  /// registered natively at launch). A best-effort nudge: the system decides
  /// when it runs; the foreground drain is the guarantee.
  void registerBackgroundRefresh();
}

@FlutterApi()
abstract class CaptureEventsApi {
  void onSpoolChanged(int pendingCount);

  void onPermissionChanged(CaptureCapabilities c);
}
