// T-092 wiring (WIRE-2): opens a reimbursement suggestion for an incoming
// person-to-person transfer right after it is stored. Runs inside the
// message's savepoint (PostPersistHook); only a newly inserted row is
// looked at, and nothing is linked until the user accepts. A suggestion that
// cannot be made never costs the transaction: the hook swallows its own
// failure (the suggestion is optional and can be made again later).

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/db/app_database.dart';
import '../../ingestion/domain/ingest_ports.dart';
import 'suggestions.dart';

final class ReimbursementSuggestionHook implements PostPersistHook {
  ReimbursementSuggestionHook(AppDatabase db, {DateTime Function()? clock})
    // `suggestReimbursement` never reads the schedule (only accepting does).
    : _suggestions = PairSuggestions(
        db,
        loadSchedule: () async => PaydaySchedule.single(1),
        clock: clock,
      );

  final PairSuggestions _suggestions;

  @override
  Future<void> afterPersist(PersistedTxn txn) async {
    if (!txn.inserted) return;
    try {
      await _suggestions.suggestReimbursement(txn.txnId);
    } on Object {
      // Best effort, see the file header.
    }
  }
}
