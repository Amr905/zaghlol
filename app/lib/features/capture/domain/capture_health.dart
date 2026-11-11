// T-047 (design note §2): the app-level capture health, derived by a pure
// function from what the platform and the settings say. The UI (Home
// banners, onboarding S-02, settings S-61) maps the result to copy; this file
// has no user-facing text. Nothing here carries a sender, a message or an
// amount: codes, enums and counts only.

/// Capture channels the app knows today. iOS channels (T-066) and voice add
/// values; [deriveCaptureHealth] switches over this enum exhaustively, so
/// the compiler finds every place to extend.
enum CaptureChannel { smsLive, notifications, sharePaste, manual }

/// Why a channel is not active.
enum ChannelState {
  active,

  /// Not in this build (Play flavour without the SMS exception).
  unavailable,

  /// The build has it, the OS permission is missing.
  offPermission,

  /// The user turned it off on purpose.
  offUser,
}

/// The Guard config as native code holds it (platform-channels §1.1).
enum GuardFileState { unknown, full, baseOnly, userUnreadable, baseInvalid }

/// Platform capabilities (Android).
final class CaptureCaps {
  const CaptureCaps({
    required this.smsFlavor,
    required this.smsGranted,
    required this.notificationAccess,
  });

  final bool smsFlavor;
  final bool smsGranted;
  final bool notificationAccess;

  /// Before the first capabilities read: nothing is claimed.
  static const CaptureCaps none = CaptureCaps(
    smsFlavor: false,
    smsGranted: false,
    notificationAccess: false,
  );
}

/// The user's capture toggles (FR-ONB-07).
final class CaptureToggles {
  const CaptureToggles({required this.sms, required this.notifications});

  final bool sms;
  final bool notifications;
}

/// Alerts the app absorbed from the native status (durable app state).
final class AbsorbedAlerts {
  const AbsorbedAlerts({this.missedNotifications = 0, this.unreadableAtMs});

  static const AbsorbedAlerts none = AbsorbedAlerts();

  /// Informational count of notifications that were not kept.
  final int missedNotifications;

  /// Set when spool entries became unreadable (`decryptDeleted > 0`).
  final int? unreadableAtMs;
}

/// The state of the last Guard config write (a code only, never a value).
enum GuardWriteState {
  /// No write was attempted yet.
  notWritten,
  written,

  /// The builder refused a row (code + path); no native call.
  buildFailed,

  /// Native answered CONFIG_INVALID: a defect, not retried.
  rejected,

  /// IO_ERROR / PLATFORM_* / timeout; retried 2 s, 10 s, 60 s.
  transient,

  /// [transient] after the last retry: parked until the next trigger.
  parked,

  /// No native writer in this build.
  unavailable,

  /// Written but a re-read did not report `full`.
  notEffective,
}

final class GuardWriteStatus {
  const GuardWriteStatus(this.state, {this.code, this.path});

  static const GuardWriteStatus notWritten = GuardWriteStatus(
    GuardWriteState.notWritten,
  );
  static const GuardWriteStatus written = GuardWriteStatus(
    GuardWriteState.written,
  );

  final GuardWriteState state;

  /// A fixed error code (`badValue`, `CONFIG_INVALID`, ...).
  final String? code;

  /// The JSON path of a builder error (fixed key names and indexes).
  final String? path;

  /// True when a failure should reach the user as a settings-level warning.
  bool get isProblem => switch (state) {
    GuardWriteState.buildFailed ||
    GuardWriteState.rejected ||
    GuardWriteState.notEffective ||
    GuardWriteState.parked => true,
    GuardWriteState.notWritten ||
    GuardWriteState.written ||
    GuardWriteState.transient ||
    GuardWriteState.unavailable => false,
  };

  /// Code only.
  @override
  String toString() => 'GuardWriteStatus(${state.name}, ${code ?? '-'})';
}

/// The last drain cycle of the UI engine (counts only).
final class LastCycle {
  const LastCycle({this.stuck = 0, this.held = 0});

  static const LastCycle none = LastCycle();

  final int stuck;
  final int held;
}

enum CaptureMode {
  /// Every available channel works.
  full,

  /// Live SMS is unavailable or lacks its permission (FR-ING-A-05, EC-13).
  /// A deliberate toggle-off is not degraded.
  degraded,

  /// The Guard base is invalid: every message is dropped (a build defect, no
  /// user action).
  fault,
}

/// Independent issues; the UI maps each to copy and an action. Banner
/// priority and stacking are open (PO Q4).
enum CaptureIssue {
  /// `home_banner_smsOff` + `common_action_fix` (PO Q1: not on a build
  /// without the SMS exception).
  smsOff,

  /// `home_banner_notifOff` + `common_action_fix`.
  notificationsOff,

  /// `capture_settings_unreadable` + re-scan.
  unreadable,

  /// "Some notifications were missed (N)": copy TBD (PO Q2).
  missedNotifications,

  /// The Guard config could not be written: copy TBD (PO Q2/Q5).
  guardWriteFailed,

  /// S-61 diagnostic row only, never a banner: copy TBD.
  stuckEntries,
}

final class CaptureHealth {
  const CaptureHealth({
    required this.mode,
    required this.channels,
    required this.issues,
    this.missedNotifications = 0,
  });

  static const CaptureHealth initial = CaptureHealth(
    mode: CaptureMode.full,
    channels: {
      CaptureChannel.smsLive: ChannelState.unavailable,
      CaptureChannel.notifications: ChannelState.offPermission,
      CaptureChannel.sharePaste: ChannelState.active,
      CaptureChannel.manual: ChannelState.active,
    },
    issues: {},
  );

  final CaptureMode mode;
  final Map<CaptureChannel, ChannelState> channels;
  final Set<CaptureIssue> issues;

  /// For the missed-notifications notice (informational).
  final int missedNotifications;

  /// The channels that are active now.
  Set<CaptureChannel> get activeChannels => {
    for (final e in channels.entries)
      if (e.value == ChannelState.active) e.key,
  };

  @override
  bool operator ==(Object other) =>
      other is CaptureHealth &&
      other.mode == mode &&
      other.missedNotifications == missedNotifications &&
      _sameMap(other.channels, channels) &&
      other.issues.length == issues.length &&
      other.issues.containsAll(issues);

  @override
  int get hashCode =>
      Object.hash(mode, missedNotifications, issues.length, channels.length);

  static bool _sameMap(
    Map<CaptureChannel, ChannelState> a,
    Map<CaptureChannel, ChannelState> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  String toString() => 'CaptureHealth(${mode.name}, ${issues.length} issues)';
}

ChannelState _smsState(CaptureCaps c, CaptureToggles t) {
  if (!c.smsFlavor) return ChannelState.unavailable;
  if (!t.sms) return ChannelState.offUser;
  if (!c.smsGranted) return ChannelState.offPermission;
  return ChannelState.active;
}

ChannelState _notificationState(CaptureCaps c, CaptureToggles t) {
  if (!t.notifications) return ChannelState.offUser;
  if (!c.notificationAccess) return ChannelState.offPermission;
  return ChannelState.active;
}

/// Derives the health. A user's toggle-off wins over a missing permission
/// (the user chose it, so it is neither degraded nor an issue).
/// `keyInvalidatedAtMs` is not an input: alone it raises no notice (T-039
/// code #5); the notice needs [absorbed].unreadableAtMs.
CaptureHealth deriveCaptureHealth({
  required CaptureCaps caps,
  required CaptureToggles toggles,
  required AbsorbedAlerts absorbed,
  required GuardWriteStatus guardWrite,
  required LastCycle lastCycle,
  required GuardFileState guardState,
}) {
  final channels = <CaptureChannel, ChannelState>{
    for (final ch in CaptureChannel.values)
      ch: switch (ch) {
        CaptureChannel.smsLive => _smsState(caps, toggles),
        CaptureChannel.notifications => _notificationState(caps, toggles),
        CaptureChannel.sharePaste => ChannelState.active,
        CaptureChannel.manual => ChannelState.active,
      },
  };
  final sms = channels[CaptureChannel.smsLive]!;
  final CaptureMode mode;
  if (guardState == GuardFileState.baseInvalid) {
    mode = CaptureMode.fault;
  } else if (sms == ChannelState.unavailable ||
      sms == ChannelState.offPermission) {
    mode = CaptureMode.degraded;
  } else {
    mode = CaptureMode.full;
  }
  final issues = <CaptureIssue>{
    if (sms == ChannelState.offPermission) CaptureIssue.smsOff,
    if (channels[CaptureChannel.notifications] == ChannelState.offPermission)
      CaptureIssue.notificationsOff,
    if (absorbed.unreadableAtMs != null) CaptureIssue.unreadable,
    if (absorbed.missedNotifications > 0) CaptureIssue.missedNotifications,
    if (guardWrite.isProblem) CaptureIssue.guardWriteFailed,
    if (lastCycle.stuck > 0) CaptureIssue.stuckEntries,
  };
  return CaptureHealth(
    mode: mode,
    channels: channels,
    issues: issues,
    missedNotifications: absorbed.missedNotifications,
  );
}
