// T-246 (D-81): the payday follows the salary. Reads the salary credits of the
// last 12 months, asks the pure rule (`detectPayday`) and, when it says so,
// sets the payday through the schedule store (EC-21: the current cycle ends
// early). It remembers what it did so Home can show one banner with Undo.
//
// Safety: a payday the user typed is only changed by the rule's "all 3
// months disagree" case; Undo restores the old value and suppresses the same
// pattern. Only dates and currency codes are read, never amounts or text.
// Nothing here logs.

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_repository.dart';
import '../../budget/data/payday_schedule_store.dart';

class PaydayAutoService {
  PaydayAutoService(
    this._db,
    this._settings,
    this._store, {
    required this._nowUtcMs,
    this._primaryCurrency,
  });

  final AppDatabase _db;
  final SettingsRepository _settings;
  final PaydayScheduleStore _store;
  final int Function() _nowUtcMs;

  /// Null: read `primary_currency`.
  final String? _primaryCurrency;

  static const int _lookbackDays = 366;

  /// Detects and, when the rule says so, applies. Returns the day set, or
  /// null when nothing changed. Idempotent.
  Future<int?> run() async {
    final eras = await _settings.get(Settings.paydayEras);
    final configured = eras != null;
    final current = configured ? await _settings.get(Settings.paydayDay) : null;
    final state = await _settings.get(Settings.paydayAuto);
    final currency =
        _primaryCurrency ??
        (await _settings.get(Settings.primaryCurrency)).code;
    final credits = await _credits();
    final detection = detectPayday(
      credits: credits,
      currency: currency,
      currentPayday: current,
      typedByUser: state.typedBy(current),
    );
    final day = detection.day;
    if (!detection.apply || day == null || day == current) return null;
    if (state.suppressed.contains(day)) return null;
    await _store.setPayday(day);
    await _settings.set(
      Settings.paydayAuto,
      state.copyWith(
        autoDay: day,
        previous: current,
        clearPrevious: current == null,
        bannerPending: true,
      ),
    );
    return day;
  }

  /// The banner's Undo: restores the previous value (day 1, the default,
  /// when none was set) and never auto-sets the same pattern again.
  Future<void> undo() async {
    final state = await _settings.get(Settings.paydayAuto);
    final auto = state.autoDay;
    if (auto == null) return;
    final now = await _settings.get(Settings.paydayDay);
    if (now == auto) await _store.setPayday(state.previous ?? 1);
    await _settings.set(
      Settings.paydayAuto,
      state
          .withSuppressed(auto)
          .copyWith(
            clearAutoDay: true,
            clearPrevious: true,
            bannerPending: false,
          ),
    );
  }

  /// Closes the banner without undoing.
  Future<void> dismissBanner() async {
    final state = await _settings.get(Settings.paydayAuto);
    if (!state.bannerPending) return;
    await _settings.set(
      Settings.paydayAuto,
      state.copyWith(bannerPending: false),
    );
  }

  /// Salary credits: income, posted, not internal, not deleted, with the
  /// income category (salary template and "this is my salary" mark) or tied
  /// in `salary.state`.
  Future<List<PaydayCredit>> _credits() async {
    final salaryState = await _settings.get(Settings.salaryState);
    final ids = [
      for (final e in salaryState.entries)
        if (e.captured) e.txnId,
    ];
    final from = _nowUtcMs() - _lookbackDays * 86400000;
    final marks = [for (var i = 0; i < ids.length; i++) '?${i + 2}'];
    final rows = await _db
        .customSelect(
          'SELECT occurred_at, occurred_tz_offset_min, currency '
          'FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'posted' "
          "AND is_internal = 0 AND direction = 'income' "
          'AND occurred_at >= ?1 '
          "AND (category_id = 'sys:income'"
          '${ids.isEmpty ? '' : ' OR id IN (${marks.join(',')})'})',
          variables: [
            Variable.withInt(from),
            for (final id in ids) Variable.withString(id),
          ],
          readsFrom: {_db.transactions},
        )
        .get();
    return [
      for (final r in rows)
        PaydayCredit(
          CivilDate.fromLocalMs(
            r.read<int>('occurred_at'),
            r.read<int>('occurred_tz_offset_min'),
          ),
          r.read<String>('currency'),
        ),
    ];
  }
}
