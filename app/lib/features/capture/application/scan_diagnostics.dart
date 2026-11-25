// T-260: counts of scan outcomes for dev builds. Counters only: never the
// text, the amounts or the merchant of a scan.

enum ScanCounter { ocrFailed, noText, noTotal, foundLabel, foundFallback }

final class ScanDiagnostics {
  final Map<ScanCounter, int> _counts = {};

  void record(ScanCounter c) =>
      _counts.update(c, (n) => n + 1, ifAbsent: () => 1);

  int count(ScanCounter c) => _counts[c] ?? 0;

  /// Snapshot keyed by the counter names (`ocr_failed`, `no_text`, ...).
  Map<String, int> get snapshot => {
    for (final c in ScanCounter.values) _wire(c): count(c),
  };

  static String _wire(ScanCounter c) => switch (c) {
    ScanCounter.ocrFailed => 'ocr_failed',
    ScanCounter.noText => 'no_text',
    ScanCounter.noTotal => 'no_total',
    ScanCounter.foundLabel => 'found_label',
    ScanCounter.foundFallback => 'found_fallback',
  };

  @override
  String toString() => 'ScanDiagnostics($snapshot)';
}
