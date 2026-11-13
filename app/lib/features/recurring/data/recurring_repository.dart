// T-096: recurring money (FR-SUB-*, BR-SUB-*). Detection only ever writes a
// `suggested` item plus a review item; the user confirms or dismisses.
// Auto-mark links a payment to an occurrence in one transaction, with an
// `INSERT OR IGNORE` on the occurrence key so two engines have one winner.
// Amounts are Money (integer minor units, one currency per item). Nothing
// here logs, and review payloads carry ids only.

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/app_database_providers.dart';
import '../../../core/db/daos/recurring_dao.dart';
import '../../../core/db/daos/review_items_dao.dart';
import '../../../core/db/daos/write_errors.dart';
import '../../../core/db/money_columns.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show Clock, IdGenerator;
import '../../transactions/data/transactions_providers.dart'
    show clockProvider, idGeneratorProvider;

/// `recurring_items.kind` values.
abstract final class RecurringKind {
  static const String subscription = 'subscription';
  static const String installment = 'installment';
  static const String cardDue = 'card_due';
  static const String gameya = 'gameya';
  static const String bill = 'bill';
  static const Set<String> all = {
    subscription,
    installment,
    cardDue,
    gameya,
    bill,
  };
}

/// `recurring_items.status` values.
abstract final class RecurringStatus {
  static const String suggested = 'suggested';
  static const String active = 'active';
  static const String dismissed = 'dismissed';
  static const String completed = 'completed';
}

/// Typed failure; the code never carries user text.
final class RecurringException extends SafeException {
  RecurringException(super.code);

  static const String invalid = 'RECURRING_INVALID';
  static const String notFound = 'RECURRING_NOT_FOUND';
}

/// An item whose reminder is due now.
final class DueReminder {
  const DueReminder({required this.item, required this.dueDate});
  final RecurringItemRow item;
  final CivilDate dueDate;
}

/// A payment that was linked to an occurrence.
final class PaidMark {
  const PaidMark({
    required this.itemId,
    required this.dueDate,
    required this.txnId,
    required this.completed,
  });
  final String itemId;
  final CivilDate dueDate;
  final String txnId;
  final bool completed;
}

/// Review-item resolutions this feature writes.
abstract final class RecurringResolution {
  static const String confirmed = 'accepted';
  static const String dismissed = 'dismissed';
}

class RecurringRepository {
  RecurringRepository(this._db, {required this._clock, required this._newId})
    : _recurring = RecurringDao(_db),
      _reviews = ReviewItemsDao(_db);

  final AppDatabase _db;
  final RecurringDao _recurring;
  final ReviewItemsDao _reviews;
  final Clock _clock;
  final IdGenerator _newId;

  /// History scanned by detection (a year of charges holds any monthly chain
  /// that is still running).
  static const int detectionLookbackDays = 400;
  static const int maxChargesScanned = 20000;
  static const int maxCatchUpPerItem = 24;

  int get _now => _clock().toUtc().millisecondsSinceEpoch;

  CivilDate get _today {
    final c = _clock();
    return CivilDate.fromLocalMs(
      c.toUtc().millisecondsSinceEpoch,
      c.toLocal().timeZoneOffset.inMinutes,
    );
  }

  // ---- detection (BR-SUB-01) ----

  /// Scans posted expenses and queues a `subscription_suggestion` review
  /// item (with a `suggested` item behind it) for each new chain. Idempotent:
  /// a merchant/account/currency that already has any subscription item, in
  /// any status (so a dismissed one stays dismissed), is skipped. Returns the
  /// ids of the items it created.
  Future<List<String>> detectAndSuggest() => guardWrite(
    () => _db.transaction(() async {
      final since = _now - detectionLookbackDays * Duration.millisecondsPerDay;
      final rows =
          await (_db.select(_db.transactions)
                ..where(
                  (t) =>
                      t.direction.equals('expense') &
                      t.status.equals('posted') &
                      t.isInternal.equals(0) &
                      t.deletedAt.isNull() &
                      t.merchantNorm.isNotNull() &
                      t.occurredAt.isBiggerOrEqualValue(since),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
                ..limit(maxChargesScanned))
              .get();
      final charges = <RecurringCharge>[];
      for (final t in rows) {
        charges.add(
          RecurringCharge(
            id: t.id,
            merchantNorm: t.merchantNorm!,
            accountId: t.accountId,
            amount: t.amount,
            date: CivilDate.fromLocalMs(t.occurredAt, t.occurredTzOffsetMin),
            displayName: t.merchantRaw,
          ),
        );
      }
      final existing =
          await (_db.select(_db.recurringItems)..where(
                (r) =>
                    r.kind.equals(RecurringKind.subscription) &
                    r.merchantNorm.isNotNull(),
              ))
              .get();
      final exclude = {
        for (final e in existing)
          recurringKey(e.merchantNorm!, e.accountId ?? '', e.currency),
      };
      final created = <String>[];
      for (final s in detectSubscriptions(charges, exclude: exclude)) {
        final id = _newId();
        await _recurring.insertItem(
          RecurringItemsCompanion.insert(
            id: id,
            kind: RecurringKind.subscription,
            status: RecurringStatus.suggested,
            name: s.name,
            merchantNorm: Value(s.merchantNorm),
            accountId: Value(s.accountId),
            amountMinor: 0,
            currency: s.amount.currency.code,
            cadence: 'monthly',
            dueDay: Value(s.dueDay),
            nextDueDate: Value(s.nextDue.toIso()),
            createdAt: _now,
          ).withAmount(s.amount),
        );
        await _reviews.insert(
          id: _newId(),
          kind: ReviewKind.subscriptionSuggestion,
          payload: {'itemId': id, 'chain': s.chargeIds.length},
          createdAt: _now,
        );
        created.add(id);
      }
      return created;
    }),
  );

  /// The user confirms a suggestion: the item becomes `active` and its review
  /// item is resolved. False when it was not `suggested` any more.
  Future<bool> confirm(String itemId) =>
      _decide(itemId, RecurringStatus.active, RecurringResolution.confirmed);

  /// The user dismisses a suggestion. The row stays (status `dismissed`) so
  /// detection does not suggest it again.
  Future<bool> dismiss(String itemId) =>
      _decide(itemId, RecurringStatus.dismissed, RecurringResolution.dismissed);

  Future<bool> _decide(String itemId, String status, String resolution) =>
      guardWrite(
        () => _db.transaction(() async {
          final changed =
              await (_db.update(_db.recurringItems)..where(
                    (r) =>
                        r.id.equals(itemId) &
                        r.status.equals(RecurringStatus.suggested),
                  ))
                  .write(RecurringItemsCompanion(status: Value(status)));
          if (changed == 0) return false;
          final open = await _db
              .customSelect(
                'SELECT id FROM review_items WHERE kind = ?1 '
                'AND resolved_at IS NULL '
                "AND json_extract(payload, '\$.itemId') = ?2",
                variables: [
                  Variable<String>(ReviewKind.subscriptionSuggestion),
                  Variable<String>(itemId),
                ],
                readsFrom: {_db.reviewItems},
              )
              .get();
          for (final r in open) {
            await _reviews.resolve(
              r.read<String>('id'),
              resolution: resolution,
              at: _now,
            );
          }
          return true;
        }),
      );

  // ---- manual items (installments, gameya, bills; FR-SUB-04) ----

  /// Adds an active item the user typed in. [dueDay] 1..31 is the anchor;
  /// [nextDue] defaults to the next such day on or after today. A gameya is
  /// manual only: its [amount] is the monthly share and [totalCount] the
  /// number of rounds. A `card_due` may have a zero [amount] (unknown until
  /// the statement). Returns the new id.
  Future<String> addManual({
    required String kind,
    required String name,
    required Money amount,
    required int dueDay,
    RecurrenceCadence cadence = RecurrenceCadence.monthly,
    int? cadenceDays,
    int? totalCount,
    int paidCount = 0,
    String? merchantNorm,
    String? accountId,
    CivilDate? nextDue,
    int reminderDays = defaultReminderDays,
  }) async {
    final n = name.trim();
    final okName =
        n.isNotEmpty && n.runes.length <= 60 && !n.contains('\u0000');
    final okAmount =
        amount.isPositive || (kind == RecurringKind.cardDue && amount.isZero);
    if (!RecurringKind.all.contains(kind) ||
        !okName ||
        !okAmount ||
        dueDay < 1 ||
        dueDay > 31 ||
        reminderDays < 0 ||
        reminderDays > 60 ||
        (totalCount != null && (totalCount < 1 || paidCount > totalCount)) ||
        paidCount < 0 ||
        (cadence == RecurrenceCadence.customDays) != (cadenceDays != null) ||
        (cadenceDays != null && (cadenceDays < 1 || cadenceDays > 3660)) ||
        (merchantNorm != null && !isStorableMerchantNorm(merchantNorm)) ||
        (merchantNorm == null && accountId == null)) {
      throw RecurringException(RecurringException.invalid);
    }
    final id = _newId();
    final due = nextDue ?? nextDueOnOrAfter(_today, dueDay);
    return guardWrite(() async {
      await _recurring.insertItem(
        RecurringItemsCompanion.insert(
          id: id,
          kind: kind,
          status: totalCount != null && paidCount >= totalCount
              ? RecurringStatus.completed
              : RecurringStatus.active,
          name: n,
          merchantNorm: Value(merchantNorm),
          accountId: Value(accountId),
          amountMinor: 0,
          currency: amount.currency.code,
          cadence: _cadenceCode(cadence),
          cadenceDays: Value(cadenceDays),
          dueDay: Value(dueDay),
          nextDueDate: Value(due.toIso()),
          totalCount: Value(totalCount),
          paidCount: Value(paidCount),
          reminderDays: Value(reminderDays),
          createdAt: _now,
        ).withAmount(amount),
      );
      return id;
    });
  }

  /// Card due dates (FR-SUB-04): one active `card_due` item per credit
  /// account that has a statement due day (S-43). A changed due day moves the
  /// item's anchor and next date. Returns the number of items created or
  /// moved.
  Future<int> syncCardDues() => guardWrite(
    () => _db.transaction(() async {
      final cards =
          await (_db.select(_db.accounts)..where(
                (a) =>
                    a.kind.equals('credit') &
                    a.statementDueDay.isNotNull() &
                    a.mergedIntoId.isNull(),
              ))
              .get();
      var touched = 0;
      for (final a in cards) {
        final day = a.statementDueDay!;
        final item =
            await (_db.select(_db.recurringItems)..where(
                  (r) =>
                      r.kind.equals(RecurringKind.cardDue) &
                      r.accountId.equals(a.id) &
                      r.status.equals(RecurringStatus.active),
                ))
                .getSingleOrNull();
        if (item == null) {
          await _recurring.insertItem(
            RecurringItemsCompanion.insert(
              id: _newId(),
              kind: RecurringKind.cardDue,
              status: RecurringStatus.active,
              name: a.label,
              accountId: Value(a.id),
              amountMinor: 0,
              currency: a.defaultCurrency,
              cadence: 'monthly',
              dueDay: Value(day),
              nextDueDate: Value(nextDueOnOrAfter(_today, day).toIso()),
              createdAt: _now,
            ),
          );
          touched++;
        } else if (item.dueDay != day) {
          await _recurring.updateItem(
            item.id,
            RecurringItemsCompanion(
              dueDay: Value(day),
              nextDueDate: Value(nextDueOnOrAfter(_today, day).toIso()),
            ),
          );
          touched++;
        }
      }
      return touched;
    }),
  );

  // ---- auto-mark paid (FR-SUB-05) ----

  /// Links payments to due occurrences. For each active item whose due date
  /// is at most [autoMarkWindowDays] ahead, an `expense` or `transfer_out`
  /// (also `transfer_in` for a card due, whose payment lands on the card)
  /// that matches by the domain rule marks the occurrence paid, counts it and
  /// moves the item to its next due date; a counted item that reaches its
  /// total becomes `completed`. A transaction pays at most one occurrence.
  /// Safe to call after every ingest and daily.
  Future<List<PaidMark>> autoMarkPaid() => guardWrite(
    () => _db.transaction(() async {
      final marks = <PaidMark>[];
      final horizon = _today.plusDays(autoMarkWindowDays).toIso();
      final items = await _recurring.activeDueBy(horizon);
      for (final item in items) {
        for (var i = 0; i < maxCatchUpPerItem; i++) {
          final current = await _recurring.itemById(item.id);
          if (current == null ||
              current.status != RecurringStatus.active ||
              current.nextDueDate == null ||
              current.nextDueDate!.compareTo(horizon) > 0) {
            break;
          }
          final mark = await _markOne(current);
          if (mark == null) break;
          marks.add(mark);
        }
      }
      return marks;
    }),
  );

  Future<PaidMark?> _markOne(RecurringItemRow item) async {
    final due = CivilDate.tryParse(item.nextDueDate!);
    final cadence = _cadenceOf(item.cadence);
    if (due == null || cadence == null) return null;
    final dueMs = DateTime.utc(
      due.year,
      due.month,
      due.day,
    ).millisecondsSinceEpoch;
    const day = Duration.millisecondsPerDay;
    // Wide in UTC; the exact local-date test is the domain rule's.
    final lo = dueMs - (autoMarkWindowDays + 2) * day;
    final hi = dueMs + (autoMarkWindowDays + 3) * day;
    final isCard = item.kind == RecurringKind.cardDue;
    final directions = ['expense', 'transfer_out', if (isCard) 'transfer_in'];
    final rows =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.direction.isIn(directions) &
                  t.status.equals('posted') &
                  t.deletedAt.isNull() &
                  t.currency.equals(item.currency) &
                  t.occurredAt.isBetweenValues(lo, hi) &
                  notExistsQuery(
                    _db.select(_db.recurringOccurrences)
                      ..where((o) => o.txnId.equalsExp(t.id)),
                  ),
            ))
            .get();
    final match = matchPayment(
      DueItem(
        id: item.id,
        amount: item.amount,
        dueDate: due,
        merchantNorm: item.merchantNorm,
        accountId: item.accountId,
      ),
      [
        for (final t in rows)
          PaymentCandidate(
            id: t.id,
            amount: t.amount,
            date: CivilDate.fromLocalMs(t.occurredAt, t.occurredTzOffsetMin),
            merchantNorm: t.merchantNorm,
            accountId: t.accountId,
          ),
      ],
    );
    if (match == null) return null;
    final claimed = await _db.customUpdate(
      'INSERT OR IGNORE INTO recurring_occurrences '
      '(item_id, due_date, txn_id, paid_at) VALUES (?1, ?2, ?3, ?4)',
      variables: [
        Variable<String>(item.id),
        Variable<String>(due.toIso()),
        Variable<String>(match.id),
        Variable<int>(_now),
      ],
      updates: {_db.recurringOccurrences},
    );
    if (claimed == 0) return null; // another actor already paid this one
    final p = progressAfterPayment(
      paidCount: item.paidCount,
      totalCount: item.totalCount,
      dueDate: due,
      cadence: cadence,
      dueDay: item.dueDay,
      cadenceDays: item.cadenceDays,
    );
    await _recurring.updateItem(
      item.id,
      RecurringItemsCompanion(
        paidCount: Value(p.paidCount),
        status: Value(
          p.completed ? RecurringStatus.completed : RecurringStatus.active,
        ),
        nextDueDate: Value(p.nextDue?.toIso() ?? item.nextDueDate),
      ),
    );
    return PaidMark(
      itemId: item.id,
      dueDate: due,
      txnId: match.id,
      completed: p.completed,
    );
  }

  // ---- reminders (BR-SUB-03) ----

  /// Active items whose reminder should fire now (default 3 days before the
  /// due date, from 10:00 local), unpaid. Feed each to the notifications
  /// service as `NotificationType.upcomingDue` with subject = item id and
  /// period key = the due date: it dedupes, so calling again is safe.
  Future<List<DueReminder>> dueReminders() => guardRead(() async {
    final c = _clock();
    final today = _today;
    final local = c.toLocal();
    final minute = local.hour * 60 + local.minute;
    final items = await _recurring.activeDueBy(today.plusDays(60).toIso());
    final out = <DueReminder>[];
    for (final item in items) {
      final due = CivilDate.tryParse(item.nextDueDate ?? '');
      if (due == null) continue;
      if (reminderIsDue(
        dueDate: due,
        reminderDays: item.reminderDays,
        localToday: today,
        localMinuteOfDay: minute,
      )) {
        out.add(DueReminder(item: item, dueDate: due));
      }
    }
    return out;
  });

  /// Items for the list screen: suggested, active and completed.
  Future<List<RecurringItemRow>> list({String? status}) => guardRead(
    () =>
        (_db.select(_db.recurringItems)
              ..where(
                (r) => status == null
                    ? r.status.isNotValue(RecurringStatus.dismissed)
                    : r.status.equals(status),
              )
              ..orderBy([
                (r) => OrderingTerm.asc(r.nextDueDate),
                (r) => OrderingTerm.asc(r.id),
              ]))
            .get(),
  );

  static String _cadenceCode(RecurrenceCadence c) => switch (c) {
    RecurrenceCadence.monthly => 'monthly',
    RecurrenceCadence.yearly => 'yearly',
    RecurrenceCadence.weekly => 'weekly',
    RecurrenceCadence.customDays => 'custom_days',
  };

  static RecurrenceCadence? _cadenceOf(String code) => switch (code) {
    'monthly' => RecurrenceCadence.monthly,
    'yearly' => RecurrenceCadence.yearly,
    'weekly' => RecurrenceCadence.weekly,
    'custom_days' => RecurrenceCadence.customDays,
    _ => null,
  };
}

final recurringRepositoryProvider = FutureProvider<RecurringRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return RecurringRepository(
    db,
    clock: ref.watch(clockProvider),
    newId: ref.watch(idGeneratorProvider),
  );
}, name: 'recurringRepositoryProvider');
