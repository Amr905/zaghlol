// T-008: the latency report over a synthetic metrics.csv and a synthetic
// broadcast history (review F2: broadcast enqueue, dispatch and process
// start are reported next to receive → commit).

import 'package:flutter_test/flutter_test.dart';

import '../../tool/spike/latency_report.dart';

const String _header =
    'ulid,path,sdk,batt_exempt,doze,bucket,linger_ms,rx_wall_ms,t_proc,'
    't1_spooled,t2_enqueued,t3_worker,t4_dart,t5_db_open,t6_drained,'
    't7_parsed,t8_commit,t9_acked';

/// Receive wall clocks are 1 000 000 000 000 + 60 s · [i].
int _wall(int i) => 1000000000000 + i * 60000;

String _row(
  String path,
  int commit, {
  int exempt = 0,
  int i = 0,
  String proc = '-800',
}) =>
    '01JA0000000000000000000001,$path,34,$exempt,0,10,0,${_wall(i)},$proc,'
    '4,5,90,900,1000,1100,1200,$commit,${commit + 5}';

void main() {
  test('percentiles are nearest-rank', () {
    final v = [for (var i = 1; i <= 20; i++) i * 100];
    expect(percentile(v, 50), 1000);
    expect(percentile(v, 95), 1900);
    expect(percentile([7], 95), 7);
  });

  test('groups by condition; without a broadcast history only receive → '
      'commit and process start → commit have values', () {
    final csv = [
      _header,
      for (var i = 1; i <= 10; i++) _row('cold_process', i * 1000, i: i),
      _row('cold_process', 1500, exempt: 1),
      'garbage,line',
      '01JA0000000000000000000002,warm_engine,34,0,0,10,0,1,-9,4,5,90,900,'
          '1000,1100,1200,,',
    ].join('\n');
    final (rows, skipped) = parseMetrics(csv);
    expect(skipped, 1);
    expect(rows, hasLength(12));
    final table = latencyTable(rows, device: 'emu-34');
    expect(
      table,
      contains(
        '| emu-34 | path=cold_process sdk=34 exempt=0 doze=0 bucket=10 '
        'linger=0 | 10 | – (0) | – | – (0) | 5800 / 10800 / 10800 (10) '
        '| 5000 / 10000 / 10000 | 10/10 | 0 |',
      ),
    );
    expect(table, contains('exempt=1'));
    expect(table, isNot(contains('warm_engine')), reason: 'no commit stamp');
    expect(table, contains('(1 rows without a commit or ack stamp)'));
    expect(table, contains('(11 rows without a matched SMS_RECEIVED'));
    expect(table, contains(intervalLegend));
  });

  test('a row acked before its commit mark arrived counts with the ack '
      'stamp as an upper bound, never dropped', () {
    final csv = [
      _header,
      _row('cold_process', 400, i: 1),
      _row('cold_process', 300, i: 2),
      // commit mark lost the race with the ack: t8 empty, t9 = 12000.
      '01JA0000000000000000000003,cold_process,34,0,0,10,0,${_wall(3)},-800,'
          '4,5,90,900,1000,1100,1200,,12000',
    ].join('\n');
    final (rows, _) = parseMetrics(csv);
    expect(rows.last.commitMs, 12000);
    expect(rows.last.commitFromAck, isTrue);
    expect(rows.first.commitFromAck, isFalse);
    final table = latencyTable(rows, device: 'emu-36');
    expect(table, contains('| 400 / 12000 / 12000 | 2/3 | 1 |'));
    expect(table, isNot(contains('without a commit')));
  });

  group('broadcast history (F2)', () {
    const tz = Duration(hours: 2);

    // Device-local (UTC+2) clock strings for an epoch ms.
    String local(int ms) {
      final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(tz);
      String two(int v) => v.toString().padLeft(2, '0');
      return '${t.year}-${two(t.month)}-${two(t.day)} '
          '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
          '${t.millisecond.toString().padLeft(3, '0')}';
    }

    String fullRecord(int enq, int disp, {String action = 'SMS_RECEIVED'}) =>
        '''
  Historical Broadcast foreground #0:
    BroadcastRecord{1a2b3c u0 android.provider.Telephony.$action/u0} to user 0
    Intent { act=android.provider.Telephony.$action flg=0x19000010 (has extras) }
    extras: Bundle[mParcelledData.dataSize=812]
    caller=com.android.phone 1234:com.android.phone/1001 pid=1234 uid=1001
    enqueueClockTime=${local(enq)} dispatchClockTime=${local(disp)}
    dispatchTime=-1s200ms (+3ms since enq) finishTime=-1s100ms
    Receiver #0: ResolveInfo{9f8e app.zaghlol.dev/app.zaghlol.spike.sms.SpikeSmsReceiver}
''';

    String summaryRecord(int enq, int disp) =>
        '''
  #3: act=android.provider.Telephony.SMS_RECEIVED flg=0x19000010 (has extras)
    extras: Bundle[mParcelledData.dataSize=812]
    +3ms dispatch +90ms finish
    enqueue ${local(enq)}, dispatch ${local(disp)}, finish ${local(disp + 90)}
''';

    test('tz offsets parse in both forms', () {
      expect(parseTzOffset('+0200'), const Duration(hours: 2));
      expect(parseTzOffset('-05:30'), const Duration(hours: -5, minutes: -30));
      expect(() => parseTzOffset('UTC'), throwsFormatException);
    });

    test('extracts only SMS_RECEIVED timestamps from full and summary '
        'records, deduplicated, in device local time', () {
      final e1 = _wall(1) - 700;
      final e2 = _wall(2) - 400;
      final dump = [
        'ACTIVITY MANAGER BROADCAST STATE (dumpsys activity broadcasts)',
        fullRecord(e1, e1 + 3),
        fullRecord(e1 + 10, e1 + 20, action: 'SMS_DELIVER'),
        '  Historical broadcasts summary [foreground]:',
        summaryRecord(e1, e1 + 3), // the same broadcast again
        summaryRecord(e2, e2 + 5),
      ].join('\n');
      final b = extractBroadcasts(dump, tz);
      expect([for (final x in b) x.enqueueMs], [e1, e2]);
      expect([for (final x in b) x.dispatchMs], [e1 + 3, e2 + 5]);
      final text = formatBroadcasts(b);
      expect(
        text,
        'enqueue_ms=$e1 dispatch_ms=${e1 + 3} precision_ms=1\n'
        'enqueue_ms=$e2 dispatch_ms=${e2 + 5} precision_ms=1\n',
      );
      expect(text, isNot(contains('zaghlol')));
      expect(text, isNot(contains('Bundle')));
      final round = parseBroadcasts(text);
      expect(round.map((x) => x.enqueueMs), [e1, e2]);
    });

    test('rows are matched to the latest earlier broadcast, each used once; '
        'enqueue → commit adds the queueing before onReceive', () {
      final csv = [
        _header,
        _row('cold_process', 1000, i: 1), // proc −800 → 1800
        _row('cold_process', 2000, i: 2),
        _row('cold_process', 3000, i: 3), // no broadcast in the window
      ].join('\n');
      final (rows, _) = parseMetrics(csv);
      final broadcasts = [
        BroadcastTimes(_wall(1) - 5000, _wall(1) - 4990), // older, unused
        BroadcastTimes(_wall(1) - 700, _wall(1) - 690),
        BroadcastTimes(_wall(2) - 9500, _wall(2) - 9000),
        BroadcastTimes(_wall(3) + 1, _wall(3) + 2), // after receive: never
      ];
      final m = matchBroadcasts(rows, broadcasts);
      expect(m[0]!.enqueueMs, _wall(1) - 700);
      expect(m[1]!.enqueueMs, _wall(2) - 9500);
      expect(m.containsKey(2), isFalse);

      final table = latencyTable(rows, device: 'emu', broadcasts: broadcasts);
      // enqueue → commit: 700 + 1000, 9500 + 2000. dispatch: 690 + 1000,
      // 9000 + 2000. process start → commit: 1800, 2800, 3800 (p50 nearest-rank 2800).
      expect(
        table,
        contains(
          '| 3 | 1700 / 11500 / 11500 (2) | 1/2 '
          '| 1690 / 11000 / 11000 (2) | 2800 / 3800 / 3800 (3) '
          '| 2000 / 3000 / 3000 | 3/3 | 0 |',
        ),
      );
      expect(table, contains('(1 rows without a matched SMS_RECEIVED'));
    });

    test('Android 8.0 prints whole seconds: kept with precision 1000 and '
        'flagged under the table (overstated, never understated)', () {
      const dump = '''
  Historical Broadcast foreground #0:
    BroadcastRecord{ccdbd49 u0 android.provider.Telephony.SMS_RECEIVED} to user 0
    Intent { act=android.provider.Telephony.SMS_RECEIVED flg=0x19000010 (has extras) }
    enqueueClockTime=2001-09-09 01:46:40 dispatchClockTime=2001-09-09 01:46:41
''';
      final b = extractBroadcasts(dump, Duration.zero);
      expect(b.single.enqueueMs, 1000000000000);
      expect(b.single.dispatchMs, 1000000001000);
      expect(b.single.precisionMs, 1000);
      final round = parseBroadcasts(formatBroadcasts(b)).single;
      expect(round.precisionMs, 1000);
      final (rows, _) = parseMetrics(
        [_header, _row('cold_process', 500, i: 0)].join('\n'),
      );
      // rx at 1 000 000 000 000 + 0: dispatch (…1000) is after it, enqueue
      // is not; truncation can't put the true dispatch before the true rx.
      final rx = [
        _header,
        '01JA0000000000000000000001,cold_process,34,0,0,10,0,'
            '1000000001400,-800,4,5,90,900,1000,1100,1200,500,505',
      ].join('\n');
      expect(matchBroadcasts(rows, b), isEmpty);
      final (rows2, _) = parseMetrics(rx);
      final table = latencyTable(rows2, broadcasts: b);
      expect(table, contains('| 1900 / 1900 / 1900 (1) |'));
      expect(table, contains('(1 rows matched to broadcast times in whole'));
    });

    test('a burst: each row takes its own broadcast (ordered delivery: the '
        'next dispatch comes after this onReceive)', () {
      final base = _wall(0);
      final (rows, _) = parseMetrics(
        [
          _header,
          '01JA0000000000000000000001,cold_process,34,0,0,10,0,${base + 400},'
              '-800,4,5,90,900,1000,1100,1200,300,305',
          '01JA0000000000000000000002,cold_process,34,0,0,10,0,${base + 900},'
              '-800,4,5,90,900,1000,1100,1200,200,205',
        ].join('\n'),
      );
      final a = BroadcastTimes(base, base + 5);
      final b = BroadcastTimes(base + 100, base + 600);
      final m = matchBroadcasts(rows, [a, b]);
      expect(m[0], same(a));
      expect(m[1], same(b));
    });

    test('process start → commit only for a process started for the SMS', () {
      final (rows, _) = parseMetrics(
        [
          _header,
          _row('warm_process', 500, proc: '-3600000'),
          _row('cold_process', 500, proc: ''),
        ].join('\n'),
      );
      expect(rows[0].procToCommitMs, isNull);
      expect(rows[1].procToCommitMs, isNull);
      expect(rows[1].rxWallMs, _wall(0));
    });

    test('a broadcast more than the window before receive is not matched', () {
      final (rows, _) = parseMetrics(
        [_header, _row('cold_process', 10, i: 5)].join('\n'),
      );
      final m = matchBroadcasts(rows, [
        BroadcastTimes(_wall(5) - maxEnqueueToReceiveMs - 1, null),
      ]);
      expect(m, isEmpty);
    });
  });
}
