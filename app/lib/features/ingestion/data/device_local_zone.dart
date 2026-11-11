// T-046: the device time zone (EC-10) through Dart's local DateTime. Tests
// use a fixed zone instead.

import '../domain/ingest_ports.dart';

final class DeviceLocalZone implements LocalZone {
  const DeviceLocalZone();

  @override
  int offsetAtInstant(int utcMs) =>
      DateTime.fromMillisecondsSinceEpoch(utcMs).timeZoneOffset.inMinutes;

  @override
  int offsetAtWallClock(DateTime w) => DateTime(
    w.year,
    w.month,
    w.day,
    w.hour,
    w.minute,
    w.second,
  ).timeZoneOffset.inMinutes;
}

/// A zone with one fixed offset (tests, and a fallback).
final class FixedLocalZone implements LocalZone {
  const FixedLocalZone(this.offsetMin);

  final int offsetMin;

  @override
  int offsetAtInstant(int utcMs) => offsetMin;

  @override
  int offsetAtWallClock(DateTime wallClock) => offsetMin;
}
