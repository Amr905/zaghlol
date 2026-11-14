// T-066 (FR-ING-I-07, EC-14): the iOS setup checker. iOS capture depends on
// Shortcuts automations the user sets up; the OS can disable them or ask for
// confirmation, and nothing then reaches the app. The only signal is silence:
// no Shortcut or Apple Pay capture for 7 days while the user opens the app.
// Pure: epoch ms in, a state out; no sender, message or amount.

/// Days of silence after which the checker nudges.
const int kIosSilenceDays = 7;

const int _dayMs = 24 * 60 * 60 * 1000;

enum IosSetupState {
  /// Cannot tell: no capture yet and no baseline (first run not recorded).
  unknown,

  /// A capture arrived within the window, or the setup is younger than it.
  ok,

  /// Nothing captured for [kIosSilenceDays]: nudge the user to check the
  /// automations.
  silent,
}

final class IosSetupStatus {
  const IosSetupStatus(this.state, {this.silentDays = 0});

  static const IosSetupStatus unknown = IosSetupStatus(IosSetupState.unknown);

  final IosSetupState state;

  /// Whole days since the last capture (or the baseline); 0 unless silent.
  final int silentDays;

  /// For the Settings row (true = passes, false = failed, null = cannot tell).
  bool? get passes => switch (state) {
    IosSetupState.unknown => null,
    IosSetupState.ok => true,
    IosSetupState.silent => false,
  };

  /// For the Home / Settings nudge.
  bool get shouldNudge => state == IosSetupState.silent;

  @override
  bool operator ==(Object other) =>
      other is IosSetupStatus &&
      other.state == state &&
      other.silentDays == silentDays;

  @override
  int get hashCode => Object.hash(state, silentDays);

  @override
  String toString() => 'IosSetupStatus(${state.name}, $silentDays)';
}

/// [lastCaptureAtMs]: newest Shortcut / Apple Pay capture (UTC epoch ms).
/// [baselineAtMs]: when capture was first set up (start of the first-run day);
/// silence before the first capture counts from here. A capture dated in the
/// future (clock change) counts as "now".
IosSetupStatus deriveIosSetupStatus({
  required int nowMs,
  int? lastCaptureAtMs,
  int? baselineAtMs,
}) {
  final since = lastCaptureAtMs ?? baselineAtMs;
  if (since == null) return IosSetupStatus.unknown;
  final silentMs = nowMs - since;
  if (silentMs < kIosSilenceDays * _dayMs) {
    return const IosSetupStatus(IosSetupState.ok);
  }
  return IosSetupStatus(IosSetupState.silent, silentDays: silentMs ~/ _dayMs);
}
