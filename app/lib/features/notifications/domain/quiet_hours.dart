// T-094 (FR-NTF-02, A-27): quiet hours in the user's local time. Pure.

/// Minutes after local midnight; start == end means "never quiet" is not
/// assumed: an empty window (start == end) is treated as no quiet hours.
final class QuietHours {
  const QuietHours({
    required this.enabled,
    required this.startMin,
    required this.endMin,
  });

  final bool enabled;
  final int startMin;
  final int endMin;

  bool _inside(int m) => startMin < endMin
      ? m >= startMin && m < endMin
      : m >= startMin || m < endMin; // wraps midnight (23:00-08:00)

  /// Whether the local wall-clock time [local] is quiet.
  bool isQuiet(DateTime local) =>
      enabled && startMin != endMin && _inside(local.hour * 60 + local.minute);

  /// The first non-quiet local time at or after [local] (the quiet end).
  /// Built from calendar fields so a DST change can't shift it by an hour.
  DateTime nextAllowed(DateTime local) {
    if (!isQuiet(local)) return local;
    final m = local.hour * 60 + local.minute;
    final endsToday = startMin < endMin || m < endMin;
    final day = endsToday
        ? DateTime(local.year, local.month, local.day)
        : DateTime(local.year, local.month, local.day + 1);
    return DateTime(day.year, day.month, day.day, endMin ~/ 60, endMin % 60);
  }
}
