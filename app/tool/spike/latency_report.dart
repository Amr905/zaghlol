// T-008 (SPK-01): summarises the spike's metrics.csv into the ADR-005
// latency table (p50 / p95 / max of receive → commit per condition).
//
//   adb shell run-as app.zaghlol.dev cat no_backup/spike/metrics.csv > m.csv
//   dart run tool/spike/latency_report.dart m.csv [device-label]
//
// The CSV holds ULIDs, a path label, device conditions and stage deltas in
// ms only (SpikeMetrics.kt); nothing here can see message content.

import 'dart:io';

/// One parsed CSV row.
final class LatencyRow {
  const LatencyRow({
    required this.path,
    required this.sdk,
    required this.batteryExempt,
    required this.doze,
    required this.bucket,
    required this.lingerMs,
    required this.stages,
  });

  final String path;
  final int sdk;
  final bool batteryExempt;
  final bool doze;
  final int bucket;
  final int lingerMs;

  /// Stage name (`t1_spooled` … `t9_acked`) → ms after receive; absent when
  /// not recorded.
  final Map<String, int> stages;

  int? get commitMs => stages['t8_commit'];

  String get condition =>
      'path=$path sdk=$sdk exempt=${batteryExempt ? 1 : 0} '
      'doze=${doze ? 1 : 0} bucket=$bucket linger=$lingerMs';
}

const List<String> stageColumns = [
  't1_spooled',
  't2_enqueued',
  't3_worker',
  't4_dart',
  't5_db_open',
  't6_drained',
  't7_parsed',
  't8_commit',
  't9_acked',
];

/// Parses the CSV; malformed rows are skipped and counted.
(List<LatencyRow>, int) parseMetrics(String csv) {
  final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return (const [], 0);
  final header = lines.first.split(',');
  final rows = <LatencyRow>[];
  var skipped = 0;
  for (final line in lines.skip(1)) {
    final cells = line.split(',');
    if (cells.length != header.length) {
      skipped++;
      continue;
    }
    final m = {for (var i = 0; i < header.length; i++) header[i]: cells[i]};
    final sdk = int.tryParse(m['sdk'] ?? '');
    final bucket = int.tryParse(m['bucket'] ?? '');
    final linger = int.tryParse(m['linger_ms'] ?? '');
    if (sdk == null || bucket == null || linger == null) {
      skipped++;
      continue;
    }
    rows.add(
      LatencyRow(
        path: m['path'] ?? 'unknown',
        sdk: sdk,
        batteryExempt: m['batt_exempt'] == '1',
        doze: m['doze'] == '1',
        bucket: bucket,
        lingerMs: linger,
        stages: {for (final s in stageColumns) s: ?int.tryParse(m[s] ?? '')},
      ),
    );
  }
  return (rows, skipped);
}

/// Nearest-rank percentile of sorted [values] (p in 1..100).
int percentile(List<int> sorted, int p) {
  if (sorted.isEmpty) throw ArgumentError('empty');
  final rank = (p * sorted.length + 99) ~/ 100; // ceil(p/100 · n)
  return sorted[(rank < 1 ? 1 : rank) - 1];
}

/// Markdown rows: condition | n | p50 | p95 | max | ≤10 s share.
String latencyTable(List<LatencyRow> rows, {String device = ''}) {
  final groups = <String, List<int>>{};
  for (final r in rows) {
    final c = r.commitMs;
    if (c == null) continue;
    (groups[r.condition] ??= []).add(c);
  }
  final out = StringBuffer()
    ..writeln('| Device | Condition | n | p50 ms | p95 ms | max ms | ≤ 10 s |')
    ..writeln('|---|---|---|---|---|---|---|');
  for (final key in groups.keys.toList()..sort()) {
    final v = groups[key]!..sort();
    final within = v.where((x) => x <= 10000).length;
    out.writeln(
      '| $device | $key | ${v.length} | ${percentile(v, 50)} | '
      '${percentile(v, 95)} | ${v.last} | $within/${v.length} |',
    );
  }
  return out.toString();
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: latency_report.dart <metrics.csv> [device]');
    exitCode = 64;
    return;
  }
  final (rows, skipped) = parseMetrics(File(args[0]).readAsStringSync());
  stdout.write(latencyTable(rows, device: args.length > 1 ? args[1] : ''));
  if (skipped > 0) stdout.writeln('\n($skipped malformed rows skipped)');
}
