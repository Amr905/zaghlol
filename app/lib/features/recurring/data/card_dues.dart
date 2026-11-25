// T-245 (D-83): card dues from notices. A parsed `cc_due` / `cc_statement`
// notice is stored per card (institution + last-4) as one JSON value in
// `settings` (no schema change; it also waits there for a card that does not
// exist yet) and is written to the card's `card_due` reminder item, so the
// existing due reminders fire from it. A payment on the card counts against
// it; it is paid only when the minimum is covered. Doubt never marks paid;
// an older notice never replaces a newer one; the user's typed due day
// changes only for a newer notice. Nothing here logs; values are amounts and
// dates only, never message text.

import 'package:drift/drift.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/recurring_dao.dart';
import '../../../core/db/daos/settings_dao.dart';
import '../../accounts/domain/card_due.dart';
import '../../ingestion/domain/ingest_ports.dart';
import '../../transactions/data/drift_transaction_repository.dart'
    show IdGenerator;
import 'recurring_repository.dart' show RecurringKind, RecurringStatus;

class CardDues {
  CardDues(this._db, {required this.nowMs, required this.newId})
    : _settings = SettingsDao(_db),
      _recurring = RecurringDao(_db);

  final AppDatabase _db;
  final SettingsDao _settings;
  final RecurringDao _recurring;
  final int Function() nowMs;
  final IdGenerator newId;

  /// The stored due of a card, null when none (or unreadable).
  Future<CardDue?> read(String institutionCode, String last4) async =>
      CardDue.decode(await _settings.read(cardDueKey(institutionCode, last4)));

  Future<void> _write(String inst, String last4, CardDue due) =>
      _settings.write(cardDueKey(inst, last4), due.encode(), at: nowMs());

  Future<AccountRow?> _card(String inst, String last4) =>
      (_db.select(_db.accounts)..where(
            (a) =>
                a.institutionCode.equals(inst) &
                a.last4.equals(last4) &
                a.kind.equals('credit') &
                a.mergedIntoId.isNull(),
          ))
          .getSingleOrNull();

  // ---- notices ----

  /// Stores [event]'s notice and applies it to the card when it is the newest
  /// for that card. A notice without institution, last-4, a currency, or
  /// without both an amount and a date is only kept as a raw message.
  Future<void> onNotice(
    CardNoticeEvent event, {
    required int receivedAtMs,
  }) async {
    final n = event.notice;
    final inst = n.institutionCode;
    final last4 = n.last4;
    final currency = (n.amountDue ?? n.minDue)?.currency.code;
    if (inst == null || last4 == null || currency == null) return;
    if (n.amountDue == null && n.minDue == null && n.dueDate == null) return;
    CivilDate? civil(DateTime? d) =>
        d == null ? null : CivilDate(d.year, d.month, d.day);
    final incoming = CardDue(
      currency: currency,
      noticeAtMs: receivedAtMs,
      amountDueMinor: n.amountDue?.minor,
      minDueMinor: n.minDue?.minor,
      dueDate: civil(n.dueDate),
      statementDate: civil(n.statementDate),
    );
    final merged = mergeNotice(await read(inst, last4), incoming);
    if (merged == null) return; // older or duplicate: never overwrites
    await _write(inst, last4, merged);
    final card = await _card(inst, last4);
    if (card != null) await _applyTo(card, inst, last4, merged);
  }

  /// Applies every stored, not yet applied due to the credit cards that exist
  /// now (a card created after its notice). Idempotent.
  Future<int> applyPending() async {
    final cards =
        await (_db.select(_db.accounts)..where(
              (a) =>
                  a.kind.equals('credit') &
                  a.institutionCode.isNotNull() &
                  a.last4.isNotNull() &
                  a.mergedIntoId.isNull(),
            ))
            .get();
    var n = 0;
    for (final a in cards) {
      final due = await read(a.institutionCode!, a.last4!);
      if (due == null || due.applied) continue;
      await _applyTo(a, a.institutionCode!, a.last4!, due);
      n++;
    }
    return n;
  }

  Future<RecurringItemRow?> _item(String accountId) =>
      (_db.select(_db.recurringItems)
            ..where(
              (r) =>
                  r.kind.equals(RecurringKind.cardDue) &
                  r.accountId.equals(accountId) &
                  r.status.equals(RecurringStatus.active),
            )
            ..limit(1))
          .getSingleOrNull();

  Future<void> _applyTo(
    AccountRow card,
    String inst,
    String last4,
    CardDue due,
  ) async {
    final date = due.dueDate;
    if (date != null && !due.isPaid) {
      // A settled due leaves the reminder alone (it already moved on).
      // The typed due day changes only when empty or when the notice is
      // newer than the account's last edit.
      var day = card.statementDueDay;
      if (day == null || due.noticeAtMs > card.updatedAt) {
        day = date.day;
        if (day != card.statementDueDay) {
          await (_db.update(
            _db.accounts,
          )..where((a) => a.id.equals(card.id))).write(
            AccountsCompanion(
              statementDueDay: Value(day),
              updatedAt: Value(nowMs()),
            ),
          );
        }
      }
      final sameCurrency = card.defaultCurrency == due.currency;
      final amount = sameCurrency
          ? (due.remainingMinor ?? due.amountDueMinor ?? 0)
          : 0;
      final item = await _item(card.id);
      if (item == null) {
        await _recurring.insertItem(
          RecurringItemsCompanion.insert(
            id: newId(),
            kind: RecurringKind.cardDue,
            status: RecurringStatus.active,
            name: card.label,
            accountId: Value(card.id),
            amountMinor: amount,
            currency: card.defaultCurrency,
            cadence: 'monthly',
            dueDay: Value(day),
            nextDueDate: Value(date.toIso()),
            createdAt: nowMs(),
          ),
        );
      } else {
        await _recurring.updateItem(
          item.id,
          RecurringItemsCompanion(
            nextDueDate: Value(date.toIso()),
            amountMinor: Value(amount),
          ),
        );
      }
    }
    await _write(inst, last4, due.copyWith(applied: true));
  }

  // ---- payments ----

  /// Counts a stored inbound transfer on a credit card against its due.
  Future<void> onPayment(PersistedTxn txn) async {
    if (!txn.inserted) return;
    final t = await (_db.select(
      _db.transactions,
    )..where((r) => r.id.equals(txn.txnId))).getSingleOrNull();
    if (t == null ||
        t.direction != 'transfer_in' ||
        t.status != 'posted' ||
        t.deletedAt != null) {
      return;
    }
    final card = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(t.accountId))).getSingleOrNull();
    final inst = card?.institutionCode;
    final last4 = card?.last4;
    if (card == null ||
        card.kind != 'credit' ||
        inst == null ||
        last4 == null) {
      return;
    }
    final due = await read(inst, last4);
    if (due == null) return;
    final counted = applyPayment(
      due,
      txnId: t.id,
      amountMinor: t.amountMinor,
      currency: t.currency,
      paidOn: CivilDate.fromLocalMs(t.occurredAt, t.occurredTzOffsetMin),
      noticeDay: CivilDate.fromLocalMs(due.noticeAtMs, t.occurredTzOffsetMin),
    );
    if (counted == null) return;
    await _write(inst, last4, counted);
    final date = counted.dueDate;
    final item = await _item(card.id);
    if (date == null || item == null || item.nextDueDate != date.toIso()) {
      return; // the reminder already moved on (auto-mark) or is not ours
    }
    if (!counted.isPaid) {
      if (card.defaultCurrency == counted.currency) {
        await _recurring.updateItem(
          item.id,
          RecurringItemsCompanion(
            amountMinor: Value(counted.remainingMinor ?? 0),
          ),
        );
      }
      return;
    }
    final claimed = await _db.customUpdate(
      'INSERT OR IGNORE INTO recurring_occurrences '
      '(item_id, due_date, txn_id, paid_at) VALUES (?1, ?2, ?3, ?4)',
      variables: [
        Variable<String>(item.id),
        Variable<String>(date.toIso()),
        Variable<String>(t.id),
        Variable<int>(nowMs()),
      ],
      updates: {_db.recurringOccurrences},
    );
    if (claimed == 0) return;
    final p = progressAfterPayment(
      paidCount: item.paidCount,
      totalCount: item.totalCount,
      dueDate: date,
      cadence: RecurrenceCadence.monthly,
      dueDay: item.dueDay,
    );
    await _recurring.updateItem(
      item.id,
      RecurringItemsCompanion(
        paidCount: Value(p.paidCount),
        nextDueDate: Value(p.nextDue?.toIso() ?? item.nextDueDate),
        amountMinor: const Value(0),
      ),
    );
  }
}
