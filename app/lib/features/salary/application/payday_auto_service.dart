// T-246 (D-81): the payday follows the salary. Reads the salary credits of the
// last 12 months, asks the pure rule (`detectPayday`) and, when it says so,
// sets the payday through the schedule store (EC-21: the current cycle ends
// early). It remembers what it did so Home can show one banner with Undo.
//
// Safety: a payday the user typed is only changed by the rule's "all 3
// months disagree" case; Undo restores the old value and suppresses the same
// pattern. Only dates and currency codes are read, never amounts or text.
// Nothing here logs.

import 'package:drift/drift.dart' show QueryRow, Variable;
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
    final erasBefore = (await _settings.get(Settings.paydayEras))?.toJson();
    // FU-296 m-4: the change and its memory (banner, Undo) are one write; a
    // failure in between never leaves a changed payday without them.
    await _db.transaction(() async {
      await _store.setPayday(day);
      await _settings.set(
        Settings.paydayAuto,
        state.copyWith(
          autoDay: day,
          previous: current,
          previousEras: erasBefore,
          clearPrevious: current == null,
          salaryDay: detection.salaryDay,
          bannerPending: true,
        ),
      );
    });
    return day;
  }

  /// The banner's Undo: restores the previous `payday_eras` exactly (unset
  /// when none was set) and never auto-sets the same pattern again.
  Future<void> undo() async {
    final state = await _settings.get(Settings.paydayAuto);
    final auto = state.autoDay;
    if (auto == null) return;
    await _db.transaction(() async {
      final now = await _settings.get(Settings.paydayDay);
      if (now == auto) {
        final text = state.previousEras;
        final prev = state.previous;
        if (text == null && prev != null) {
          // State saved before the eras were kept.
          await _store.setPayday(prev);
        } else {
          await _store.restore(
            text == null ? null : PaydaySchedule.tryFromJson(text),
          );
        }
      }
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
    });
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

  /// FU-296 m-1: the post-persist entry. Only a stored salary credit can
  /// move the payday, so any other row (an expense, a transfer, a plain
  /// income) costs one indexed read and no 12-month query.
  Future<int?> onPersisted(String txnId) async {
    if (txnId.isEmpty) return null;
    final rows = await _salaryRows(onlyId: txnId);
    if (rows.isEmpty) return null;
    return run();
  }

  /// Salary credits of the last 12 months, by date and currency only.
  Future<List<PaydayCredit>> _credits() async {
    final rows = await _salaryRows();
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

  /// FU-296 m-2: what counts as a salary. Income, posted, not internal, not
  /// deleted rows that either are tied in `salary.state` (the matcher's tag
  /// and "this is my salary" / "it arrived" entries) or carry the income
  /// category from the salary template event (`heuristic`), from a rule the
  /// user made (`user_rule`), or look like a salary by their text. A credit
  /// the user merely filed under Income (a gift) does not move the payday.
  Future<List<QueryRow>> _salaryRows({String? onlyId}) async {
    final salaryState = await _settings.get(Settings.salaryState);
    // Manual rows carry the expected payday as anchor, so they cannot be told
    // from a real arrival: only captured entries count as tied (FU-308).
    final tied = {
      for (final e in salaryState.entries)
        if (e.captured) e.txnId,
    };
    final from = _nowUtcMs() - _lookbackDays * 86400000;
    final rows = await _db
        .customSelect(
          'SELECT id, occurred_at, occurred_tz_offset_min, currency, '
          'category_id, category_source, merchant_raw, counterparty_value, '
          'note FROM transactions '
          "WHERE deleted_at IS NULL AND status = 'posted' "
          "AND is_internal = 0 AND direction = 'income' "
          'AND occurred_at >= ?1'
          '${onlyId == null ? '' : ' AND id = ?2'}',
          variables: [
            Variable.withInt(from),
            if (onlyId != null) Variable.withString(onlyId),
          ],
          readsFrom: {_db.transactions},
        )
        .get();
    return [
      for (final r in rows)
        if (_countsAsSalary(r, tied)) r,
    ];
  }

  static bool _countsAsSalary(QueryRow r, Set<String> tied) {
    if (tied.contains(r.read<String>('id'))) return true;
    if (r.readNullable<String>('category_id') != 'sys:income') return false;
    final source = r.readNullable<String>('category_source');
    if (source == 'heuristic' || source == 'user_rule') return true;
    return salaryLooksLikeSalary([
      r.readNullable<String>('merchant_raw'),
      r.readNullable<String>('counterparty_value'),
      r.readNullable<String>('note'),
    ]);
  }
}
