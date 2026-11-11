// T-040: the devSms build's native Guard decides with a base exported from
// the synthetic spike registry (an Android asset of the devSms source set,
// read by `BaseConfigSource.readForBuild` only when the real bundled base of
// T-036 is absent). This test pins the asset to the export, so the native
// Guard and the Dart drain-time re-check (`RegistryGuardBase`) use the same
// rules. The only difference: the per-sender rate is raised so the sms-spike
// burst (40 SMS from 5550100 within seconds) is not rate-limited; the
// production limit is tested on the JVM (SenderRateLimiterTest).
//
// Regenerate: UPDATE_SPIKE_GUARD_BASE=1 flutter test test/ingestion/spike_guard_base_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const String _assetPath =
    'android/app/src/devSms/assets/guard/spike_guard_base.json';

/// The spike burst is 40 messages; the limit leaves room for the cells around it.
const int _spikeRatePerSenderPerMinute = 600;

String _expected() {
  final export = exportGuardConfig(loadSpikeRegistry());
  expect(export.issues, isEmpty);
  final config = jsonDecode(export.json!) as Map<String, Object?>;
  (config['rate']! as Map<String, Object?>)['perSenderPerMin'] =
      _spikeRatePerSenderPerMinute;
  return '${const JsonEncoder.withIndent(' ').convert(config)}\n';
}

void main() {
  test('devSms spike Guard base equals the spike registry export', () {
    final expected = _expected();
    final file = File(_assetPath);
    if (Platform.environment['UPDATE_SPIKE_GUARD_BASE'] == '1') {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(expected);
    }
    expect(
      file.readAsStringSync(),
      expected,
      reason: 'regenerate with UPDATE_SPIKE_GUARD_BASE=1',
    );
  });

  test('the spike base keeps only the synthetic sender and drops OTPs', () {
    final config =
        jsonDecode(File(_assetPath).readAsStringSync()) as Map<String, Object?>;
    final senders = (config['senders']! as List).cast<Map<String, Object?>>();
    expect(senders.map((s) => s['value']), ['5550100']);
    expect((config['drop']! as Map)['global'], isNotEmpty);
    expect(
      (config['rate']! as Map)['perSenderPerMin'],
      _spikeRatePerSenderPerMinute,
    );
  });
}
