// T-051: the payday eras in `settings` (design note §2). `payday_eras` is
// the history, `payday_day` the user-facing value (the last era's day).
// Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/setting_key.dart' show SettingsException;
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../ingestion/domain/ingest_ports.dart' show LocalZone;

/// PO Q1 (provisional — PO to confirm): the first explicit payday, set while
/// no era is recorded, replaces the A-43 default for all history. `false`
/// would treat it as an EC-21 change from today. The single decision point.
const bool kFirstPaydayRewritesHistory = true;

/// The local civil date of the clock's instant.
CivilDate localToday(int nowUtcMs, LocalZone zone) =>
    CivilDate.fromLocalMs(nowUtcMs, zone.offsetAtInstant(nowUtcMs));

class PaydayScheduleStore {
  PaydayScheduleStore(
    this._settings, {
    required this._nowUtcMs,
    required this._zone,
    this._invalidateCycles,
  });

  final SettingsRepository _settings;
  final int Function() _nowUtcMs;
  final LocalZone _zone;

  /// Drops every `cycle_summaries` row; called before a write that can move
  /// cycle boundaries (design note §6).
  final Future<void> Function()? _invalidateCycles;

  CivilDate get _today => localToday(_nowUtcMs(), _zone);

  /// The schedule in force. No eras stored: `[(null, payday_day)]` (nothing
  /// is written). Last era's day differs from `payday_day` (restore, another
  /// writer): appends `(today, payday_day)` and persists it once, so the
  /// result does not depend on when it is read.
  Future<PaydaySchedule> load() async {
    final stored = await _settings.get(Settings.paydayEras);
    final day = await _settings.get(Settings.paydayDay);
    if (stored == null) return PaydaySchedule.single(day);
    if (stored.currentDay == day) return stored;
    final reconciled = stored.withChange(_today, day);
    await _invalidateCycles?.call();
    await _settings.set(Settings.paydayEras, reconciled);
    return reconciled;
  }

  /// Sets the payday (1-28; else [SettingsException], nothing written):
  /// `payday_eras` first, then `payday_day`. EC-21 for a change after the
  /// first one (see [kFirstPaydayRewritesHistory]).
  Future<PaydaySchedule> setPayday(int day) async {
    if (day < 1 || day > 28) {
      throw SettingsException(SettingsException.invalidValue);
    }
    final stored = await _settings.get(Settings.paydayEras);
    final PaydaySchedule next;
    if (stored == null && kFirstPaydayRewritesHistory) {
      next = PaydaySchedule.single(day);
    } else {
      next = (await load()).withChange(_today, day);
    }
    await _invalidateCycles?.call();
    await _settings.set(Settings.paydayEras, next);
    await _settings.set(Settings.paydayDay, day);
    return next;
  }
}
