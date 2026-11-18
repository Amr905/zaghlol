// FU-239a: the Al Rajhi patterns once had an unbounded lazy `.*?` after the
// card digits, which backtracks about O(n^2) on a long body that never
// reaches the amount. The gap is bounded now. Synthetic bodies only.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  test('no Al Rajhi pattern has an unbounded lazy dot run', () {
    final json = jsonDecode(
      File('assets/registry/institutions/alrajhi.json').readAsStringSync(),
    ) as Map<String, Object?>;
    for (final t in json['templates']! as List<Object?>) {
      final m = t! as Map<String, Object?>;
      expect(
        m['pattern'].toString().contains('.*?'),
        isFalse,
        reason: m['id'].toString(),
      );
    }
  });

  test('long non-matching bodies parse (to nothing) quickly', () async {
    final registry = await preloadBundledRegistry();
    final pipeline = ParsingPipeline(registry);
    final starts = [
      'POS Purchase By: 4242',
      'POS Purchase Declined By: 4242',
      'ATM Withdrawal By: 4242',
      'شراء نقاط البيع بطاقه: 4242',
    ];
    final sw = Stopwatch()..start();
    for (final s in starts) {
      final body = '$s ${'amount x ' * 400}';
      final r = pipeline.parse(
        ParseRequest(
          body: body,
          source: 'AlRajhiBank',
          channel: RegistryChannel.sms,
          receivedAt: DateTime.utc(2026, 10, 23, 11),
        ),
      );
      expect(r, isNot(isA<ParseParsed>()));
    }
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
