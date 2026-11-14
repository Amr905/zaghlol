// T-100 (FR-NTF-01): duplicate point-of-sale charge detection. Pure.
// Two expenses on the same account, same merchant, same amount and currency
// within [duplicateWindow] of each other are a duplicate. A run of such
// charges forms one cluster and yields one alert, keyed by its earliest
// transaction, so a third identical charge never alerts again.

const duplicateWindow = Duration(minutes: 10);

/// What the detector needs of a transaction. No message text.
final class DupTxn {
  const DupTxn({
    required this.id,
    required this.accountId,
    required this.merchantNorm,
    required this.amountMinor,
    required this.currency,
    required this.occurredAtMs,
  });

  final String id;
  final String accountId;
  final String merchantNorm;
  final int amountMinor;
  final String currency;
  final int occurredAtMs;
}

/// One cluster of identical charges, [first] the earliest (id tie-break).
final class DuplicateCluster {
  const DuplicateCluster(this.members);

  final List<DupTxn> members;

  DupTxn get first => members.first;
}

/// Clusters of two or more identical charges, each member within the window
/// of the previous one. Zero and negative amounts and blank merchants never
/// cluster (a blank merchant is not evidence of "the same shop").
List<DuplicateCluster> findDuplicateCharges(
  Iterable<DupTxn> txns, {
  Duration window = duplicateWindow,
}) {
  final groups = <String, List<DupTxn>>{};
  for (final t in txns) {
    if (t.amountMinor <= 0 || t.merchantNorm.trim().isEmpty) continue;
    groups
        .putIfAbsent(
          '${t.accountId}|${t.merchantNorm}|${t.currency}|${t.amountMinor}',
          () => [],
        )
        .add(t);
  }
  final out = <DuplicateCluster>[];
  for (final g in groups.values) {
    g.sort((a, b) {
      final c = a.occurredAtMs.compareTo(b.occurredAtMs);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    var run = <DupTxn>[];
    for (final t in g) {
      if (run.isNotEmpty &&
          t.occurredAtMs - run.last.occurredAtMs > window.inMilliseconds) {
        if (run.length > 1) out.add(DuplicateCluster(run));
        run = <DupTxn>[];
      }
      run.add(t);
    }
    if (run.length > 1) out.add(DuplicateCluster(run));
  }
  out.sort((a, b) => a.first.occurredAtMs.compareTo(b.first.occurredAtMs));
  return out;
}
