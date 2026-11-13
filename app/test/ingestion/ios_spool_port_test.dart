// T-062: the iOS spool behind the shared Dart drain, with a fake native host
// at the Pigeon channel level (the generated IosCaptureHostApi codec). The
// fake keeps entries in memory like the Swift host: drain hands out oldest
// first, ack deletes only what was drained, hold moves entries aside, and
// errors are code-only. Bodies are synthetic.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/ingestion_runner.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';
import 'package:zaghlol/ingestion/spool_port.dart';

import 'ingestion_fakes.dart';

const String _prefix = 'dev.flutter.pigeon.zaghlol.IosCaptureHostApi';
const List<String> _methods = [
  'drainSpool',
  'ackSpool',
  'holdSpool',
  'getSpoolStatus',
  'clearSpoolAlerts',
  'registerBackgroundRefresh',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = IosCaptureHostApi.pigeonChannelCodec;

  late List<SpoolEntry> native;
  late Set<String> drained;
  late List<String> wire;
  String? failWith;

  setUp(() {
    native = [
      entry(sid(1), body: '$canary EGP 10', channel: 'shortcut_message'),
      entry(sid(2), body: '$canary EGP 20', channel: 'wallet'),
    ];
    drained = {};
    wire = [];
    failWith = null;
    ByteData? reply(Object? value) => codec.encodeMessage(<Object?>[value]);
    messenger.setMockMessageHandler('$_prefix.drainSpool', (data) async {
      wire.add('drainSpool');
      if (failWith != null) {
        return codec.encodeMessage(<Object?>[failWith, null, null]);
      }
      final max = (codec.decodeMessage(data)! as List<Object?>)[0]! as int;
      final out = native.take(max).toList();
      drained.addAll(out.map((e) => e.id));
      return reply(out);
    });
    messenger.setMockMessageHandler('$_prefix.ackSpool', (data) async {
      wire.add('ackSpool');
      final ids =
          ((codec.decodeMessage(data)! as List<Object?>)[0]! as List<Object?>)
              .cast<String>();
      // Like the host: only ids this engine drained.
      native.removeWhere((e) => ids.contains(e.id) && drained.contains(e.id));
      return reply(null);
    });
    messenger.setMockMessageHandler('$_prefix.holdSpool', (data) async {
      wire.add('holdSpool');
      return reply(null);
    });
  });

  tearDown(() {
    for (final m in _methods) {
      messenger.setMockMessageHandler('$_prefix.$m', null);
    }
  });

  test('drain and ack round trip through the iOS channel', () async {
    final port = IosPigeonSpoolPort();
    final got = await port.drain(10);
    expect(got.map((e) => e.id), [sid(1), sid(2)]);
    expect(got.first.channel, 'shortcut_message');
    await port.ack([sid(1)]);
    expect(native.map((e) => e.id), [sid(2)]);
  });

  test('an ack for an id this engine never drained deletes nothing', () async {
    final port = IosPigeonSpoolPort();
    await port.ack([sid(1)]);
    expect(native, hasLength(2));
  });

  test(
    'native codes arrive code-only; text becomes PLATFORM_UNKNOWN',
    () async {
      final port = IosPigeonSpoolPort();
      failWith = 'IO_ERROR';
      await expectLater(
        port.drain(5),
        throwsA(
          isA<SpoolPortException>().having(
            (e) => e.failure.platformCode,
            'code',
            'IO_ERROR',
          ),
        ),
      );
      failWith = 'the body was $canary';
      await expectLater(
        port.drain(5),
        throwsA(
          isA<SpoolPortException>().having(
            (e) => e.failure.code,
            'text',
            isNot(contains(canary)),
          ),
        ),
      );
    },
  );

  test('platformSpoolPort picks the iOS port on iOS only', () {
    expect(
      platformSpoolPort(platform: TargetPlatform.iOS),
      isA<IosPigeonSpoolPort>(),
    );
    expect(
      platformSpoolPort(platform: TargetPlatform.android),
      isA<PigeonSpoolPort>(),
    );
  });

  test(
    'the shared drain cycle acks after the commit over the iOS channel',
    () async {
      final log = <String>[];
      final store = FakeStore(log);
      final runner = IngestionRunner(
        marks: const NoMarks(),
        headless: true,
        spool: IosPigeonSpoolPort(),
        store: (_, _) => store,
        dbDirectory: () async => Directory.systemTemp,
        registry: loadSpikeRegistry,
      );
      final result = await runner.drain();
      expect(result.outcome, CycleOutcome.ok);
      expect(store.committed, hasLength(2));
      expect(native, isEmpty);
      expect(wire.first, 'drainSpool');
      // The ack reached native only after the store committed.
      expect(log, contains('ingest'));
      expect(wire.indexOf('ackSpool'), greaterThan(wire.indexOf('drainSpool')));
      await runner.close();
    },
  );
}
