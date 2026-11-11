// T-008 (SPK-01): summarises the spike's metrics.csv into the ADR-005
// latency table (p50 / p95 / max per condition, review F2):
// - broadcast enqueue → commit: the FR-ING-A-01 number. The system's
//   SMS_RECEIVED enqueue time comes from `dumpsys activity broadcasts
//   history`, matched to each row by the receive wall clock;
// - broadcast dispatch → commit (same source);
// - process start → commit, for rows of a process started for the SMS
//   (path cold_process; `t_proc`, Process.getStartElapsedRealtime());
// - receive (onReceive, t0) → commit, the stage the app controls.
//
//   adb shell run-as app.zaghlol.dev cat no_backup/spike/metrics.csv > m.csv
//   adb shell dumpsys activity broadcasts history > bh/1.txt   (per message)
//   dart run tool/spike/latency_report.dart --extract-broadcasts bh \
//       "$(adb shell date +%z)" > broadcasts.txt
//   dart run tool/spike/latency_report.dart m.csv [device-label] \
//       [broadcasts.txt]
//
// The CSV holds ULIDs, a path label, device conditions, the receive wall
// clock and stage deltas in ms only (SpikeMetrics.kt). The extractor keeps
// only the two timestamps of SMS_RECEIVED records (no intent, extras or
// package names), so broadcasts.txt can't carry message content either.

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
    this.rxWallMs,
    this.procMs,
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

  /// Receive wall clock (epoch ms), to match the broadcast history.
  final int? rxWallMs;

  /// Start of the receiving process in ms relative to receive (≤ 0).
  final int? procMs;

  /// True for rows of a process started for this SMS.
  bool get processStartedForIt => path == 'cold_process';

  /// Process start → commit (cold-process rows only).
  int? get procToCommitMs {
    final c = commitMs;
    final p = procMs;
    if (!processStartedForIt || c == null || p == null || p > 0) return null;
    return c - p;
  }

  /// Receive → commit. When the `commit` mark is missing, the native ack
  /// stamp stands in as an upper bound: Dart acks only after the commit
  /// returned, but the mark (metrics channel, main thread) can reach native
  /// after the ack (Pigeon background queue) that writes the row. Using t9
  /// never understates the latency; dropping such rows would bias p95.
  int? get commitMs => stages['t8_commit'] ?? stages['t9_acked'];

  /// True when [commitMs] comes from the ack stamp.
  bool get commitFromAck =>
      stages['t8_commit'] == null && stages['t9_acked'] != null;

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
        rxWallMs: int.tryParse(m['rx_wall_ms'] ?? ''),
        procMs: int.tryParse(m['t_proc'] ?? ''),
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

/// One SMS_RECEIVED record of the system broadcast history (epoch ms).
final class BroadcastTimes {
  const BroadcastTimes(this.enqueueMs, this.dispatchMs, {this.precisionMs = 1});

  final int enqueueMs;
  final int? dispatchMs;

  /// 1, or 1000 when the system printed whole seconds (Android 8.0): the
  /// times are then truncated, so intervals from them are overstated by
  /// less than a second, never understated.
  final int precisionMs;

  /// The time matched against the receive: SMS_RECEIVED is an ordered
  /// broadcast, so a message's onReceive runs after its own dispatch and
  /// before the next message's dispatch, also in a burst.
  int get matchMs => dispatchMs ?? enqueueMs;
}

final RegExp _recordStart = RegExp(
  r'BroadcastRecord\{|^\s*#\d+:|Historical Broadcast',
);
final RegExp _stamp = RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(\.\d{3})?$');
final RegExp _enqueueFull = RegExp(r'enqueueClockTime=(\S+ \S+)');
final RegExp _dispatchFull = RegExp(r'dispatchClockTime=(\S+ \S+)');
final RegExp _enqueueSummary = RegExp(r'\benqueue (\S+ \S+?),');
final RegExp _dispatchSummary = RegExp(r'\bdispatch (\S+ \S+?),');
final RegExp _tz = RegExp(r'^([+-])(\d\d):?(\d\d)$');

/// Parses `+0200` / `-05:30` (the device's `date +%z`).
Duration parseTzOffset(String tz) {
  final m = _tz.firstMatch(tz.trim());
  if (m == null) throw FormatException('bad tz offset', tz);
  final minutes = int.parse(m[2]!) * 60 + int.parse(m[3]!);
  return Duration(minutes: m[1] == '-' ? -minutes : minutes);
}

/// Device-local `yyyy-MM-dd HH:mm:ss.SSS` → epoch ms.
int? _epochMs(String? local, Duration tz) {
  if (local == null || !_stamp.hasMatch(local)) return null;
  final utc = DateTime.tryParse('${local.replaceFirst(' ', 'T')}Z');
  return utc?.subtract(tz).millisecondsSinceEpoch;
}

/// The SMS_RECEIVED records of `dumpsys activity broadcasts history` output
/// (full records: `enqueueClockTime=… dispatchClockTime=…`; summary
/// records: `enqueue …, dispatch …, finish …`), deduplicated by enqueue
/// time, oldest first. Only the two timestamps are kept.
List<BroadcastTimes> extractBroadcasts(String dumpsys, Duration tz) {
  final byEnqueue = <int, BroadcastTimes>{};
  final record = StringBuffer();
  void flush() {
    final text = record.toString();
    record.clear();
    if (!text.contains('android.provider.Telephony.SMS_RECEIVED')) return;
    final enqText =
        (_enqueueFull.firstMatch(text) ?? _enqueueSummary.firstMatch(text))?[1];
    final enq = _epochMs(enqText, tz);
    if (enq == null) return;
    final precision = enqText!.contains('.') ? 1 : 1000;
    final disp = _epochMs(
      (_dispatchFull.firstMatch(text) ?? _dispatchSummary.firstMatch(text))?[1],
      tz,
    );
    final known = byEnqueue[enq];
    if (known == null || (known.dispatchMs == null && disp != null)) {
      byEnqueue[enq] = BroadcastTimes(enq, disp, precisionMs: precision);
    }
  }

  for (final line in dumpsys.split('\n')) {
    if (_recordStart.hasMatch(line)) flush();
    record.writeln(line);
  }
  flush();
  return byEnqueue.values.toList()
    ..sort((a, b) => a.enqueueMs.compareTo(b.enqueueMs));
}

final RegExp _broadcastLine = RegExp(
  r'^enqueue_ms=(\d+) dispatch_ms=(\d*) precision_ms=(1|1000)$',
);

/// `enqueue_ms=<ms> dispatch_ms=<ms|> precision_ms=<1|1000>` lines (the
/// extractor's output).
List<BroadcastTimes> parseBroadcasts(String text) {
  final out = <BroadcastTimes>[];
  for (final line in text.split('\n')) {
    final m = _broadcastLine.firstMatch(line.trim());
    if (m == null) continue;
    out.add(
      BroadcastTimes(
        int.parse(m[1]!),
        int.tryParse(m[2]!),
        precisionMs: int.parse(m[3]!),
      ),
    );
  }
  return out;
}

String formatBroadcasts(List<BroadcastTimes> list) => [
  for (final b in list)
    'enqueue_ms=${b.enqueueMs} dispatch_ms=${b.dispatchMs ?? ''} '
        'precision_ms=${b.precisionMs}',
].map((l) => '$l\n').join();

/// Longest gap between a broadcast's enqueue and the receive it is matched
/// to; a larger gap is not taken as the same message.
const int maxEnqueueToReceiveMs = 120000;

/// Matches each row to the unused SMS_RECEIVED broadcast with the latest
/// dispatch (enqueue when unknown) at or before its receive wall clock,
/// enqueued at most [maxEnqueueToReceiveMs] before it. Needs the history of
/// every SMS sent (also dropped ones), or a row can take an older
/// broadcast. Returns row index → broadcast.
Map<int, BroadcastTimes> matchBroadcasts(
  List<LatencyRow> rows,
  List<BroadcastTimes> broadcasts,
) {
  final order = [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].rxWallMs != null) i,
  ]..sort((a, b) => rows[a].rxWallMs!.compareTo(rows[b].rxWallMs!));
  final used = <BroadcastTimes>{};
  final out = <int, BroadcastTimes>{};
  for (final i in order) {
    final rx = rows[i].rxWallMs!;
    BroadcastTimes? best;
    for (final b in broadcasts) {
      if (used.contains(b) || b.matchMs > rx || b.enqueueMs > rx) continue;
      if (rx - b.enqueueMs > maxEnqueueToReceiveMs) continue;
      if (best == null || b.matchMs > best.matchMs) best = b;
    }
    if (best != null) {
      used.add(best);
      out[i] = best;
    }
  }
  return out;
}

String _stats(List<int> v) {
  if (v.isEmpty) return '–';
  v.sort();
  return '${percentile(v, 50)} / ${percentile(v, 95)} / ${v.last}';
}

String _within(List<int> v) =>
    v.isEmpty ? '–' : '${v.where((x) => x <= 10000).length}/${v.length}';

/// Text printed under every table: which interval each column is.
const String intervalLegend =
    'Intervals (ms, p50 / p95 / max): **enqueue → commit** = system '
    'SMS_RECEIVED enqueue (dumpsys broadcast history) to the DB commit, the '
    'FR-ING-A-01 number; dispatch → commit = system dispatch of that '
    'broadcast to the commit; process start → commit = '
    'Process.getStartElapsedRealtime() to the commit, rows of a process '
    'started for the SMS (cold_process) only; receive → commit = onReceive '
    '(t0) to the commit. Broadcast times are wall clock, matched per message '
    'by the receive wall clock; the rest is elapsedRealtime. (n) = rows with '
    'that interval.';

/// Markdown rows per condition: n, then each interval (see
/// [intervalLegend]), the ≤ 10 s share of enqueue → commit and of receive →
/// commit, and the rows whose commit time is the ack stamp. Rows with
/// neither stamp, and rows without a matched broadcast, are counted below
/// the table, never silently left out.
String latencyTable(
  List<LatencyRow> rows, {
  String device = '',
  List<BroadcastTimes> broadcasts = const [],
}) {
  final matched = matchBroadcasts(rows, broadcasts);
  final rx = <String, List<int>>{};
  final enq = <String, List<int>>{};
  final disp = <String, List<int>>{};
  final proc = <String, List<int>>{};
  final fromAck = <String, int>{};
  var unstamped = 0;
  var unmatched = 0;
  var coarse = 0;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final c = r.commitMs;
    if (c == null) {
      unstamped++;
      continue;
    }
    final key = r.condition;
    (rx[key] ??= []).add(c);
    enq[key] ??= [];
    disp[key] ??= [];
    proc[key] ??= [];
    if (r.commitFromAck) fromAck[key] = (fromAck[key] ?? 0) + 1;
    final b = matched[i];
    if (b == null) {
      unmatched++;
    } else {
      if (b.precisionMs > 1) coarse++;
      final ahead = r.rxWallMs! - b.enqueueMs;
      enq[key]!.add(ahead + c);
      final d = b.dispatchMs;
      if (d != null && d <= r.rxWallMs!) disp[key]!.add(r.rxWallMs! - d + c);
    }
    final p = r.procToCommitMs;
    if (p != null) proc[key]!.add(p);
  }
  final out = StringBuffer()
    ..writeln(
      '| Device | Condition | n | enqueue → commit (n) | ≤ 10 s enqueue → '
      'commit | dispatch → commit (n) | process start → commit (n) '
      '| receive → commit | ≤ 10 s receive → commit | commit = ack stamp |',
    )
    ..writeln('|---|---|---|---|---|---|---|---|---|---|');
  for (final key in rx.keys.toList()..sort()) {
    final e = enq[key]!;
    final d = disp[key]!;
    final p = proc[key]!;
    final r = rx[key]!;
    out.writeln(
      '| $device | $key | ${r.length} '
      '| ${_stats(e)} (${e.length}) | ${_within(e)} '
      '| ${_stats(d)} (${d.length}) '
      '| ${_stats(p)} (${p.length}) '
      '| ${_stats(r)} | ${_within(r)} | ${fromAck[key] ?? 0} |',
    );
  }
  out.writeln('\n$intervalLegend');
  if (unstamped > 0) {
    out.writeln('\n($unstamped rows without a commit or ack stamp)');
  }
  if (coarse > 0) {
    out.writeln(
      '\n($coarse rows matched to broadcast times in whole seconds: their '
      'enqueue/dispatch → commit is overstated by < 1 s)',
    );
  }
  if (unmatched > 0) {
    out.writeln('\n($unmatched rows without a matched SMS_RECEIVED broadcast)');
  }
  return out.toString();
}

void main(List<String> args) {
  if (args.length == 3 && args[0] == '--extract-broadcasts') {
    final tz = parseTzOffset(args[2]);
    final all = <BroadcastTimes>[];
    final dir = Directory(args[1]);
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      all.addAll(extractBroadcasts(f.readAsStringSync(), tz));
    }
    final unique = {for (final b in all) b.enqueueMs: b}.values.toList()
      ..sort((a, b) => a.enqueueMs.compareTo(b.enqueueMs));
    stdout.write(formatBroadcasts(unique));
    return;
  }
  if (args.isEmpty || args[0].startsWith('--')) {
    stderr.writeln(
      'usage: latency_report.dart <metrics.csv> [device] [broadcasts.txt]\n'
      '       latency_report.dart --extract-broadcasts <dir> <tz +hhmm>',
    );
    exitCode = 64;
    return;
  }
  final (rows, skipped) = parseMetrics(File(args[0]).readAsStringSync());
  final broadcasts = args.length > 2
      ? parseBroadcasts(File(args[2]).readAsStringSync())
      : const <BroadcastTimes>[];
  stdout.write(
    latencyTable(
      rows,
      device: args.length > 1 ? args[1] : '',
      broadcasts: broadcasts,
    ),
  );
  if (skipped > 0) stdout.writeln('\n($skipped malformed rows skipped)');
}
