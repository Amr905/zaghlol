// T-008: the latency report over a synthetic metrics.csv.

import 'package:flutter_test/flutter_test.dart';

import '../../tool/spike/latency_report.dart';

const String _header =
    'ulid,path,sdk,batt_exempt,doze,bucket,linger_ms,t1_spooled,t2_enqueued,'
    't3_worker,t4_dart,t5_db_open,t6_drained,t7_parsed,t8_commit,t9_acked';

String _row(String path, int commit, {int exempt = 0}) =>
    '01JA0000000000000000000001,$path,34,$exempt,0,10,0,4,5,90,900,1000,1100,1200,$commit,${commit + 5}';

void main() {
  test('percentiles are nearest-rank', () {
    final v = [for (var i = 1; i <= 20; i++) i * 100];
    expect(percentile(v, 50), 1000);
    expect(percentile(v, 95), 1900);
    expect(percentile([7], 95), 7);
  });

  test('groups by condition and reports p50/p95/max and the 10 s share', () {
    final csv = [
      _header,
      for (var i = 1; i <= 10; i++) _row('cold_process', i * 1000),
      _row('cold_process', 1500, exempt: 1),
      'garbage,line',
      '01JA0000000000000000000002,warm_engine,34,0,0,10,0,4,5,90,900,1000,1100,1200,,',
    ].join('\n');
    final (rows, skipped) = parseMetrics(csv);
    expect(skipped, 1);
    expect(rows, hasLength(12));
    final table = latencyTable(rows, device: 'emu-34');
    expect(
      table,
      contains(
        '| emu-34 | path=cold_process sdk=34 exempt=0 doze=0 bucket=10 '
        'linger=0 | 10 | 5000 | 10000 | 10000 | 10/10 |',
      ),
    );
    expect(table, contains('exempt=1'));
    expect(table, isNot(contains('warm_engine')), reason: 'no commit stamp');
  });
}
