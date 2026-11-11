// T-008: the channels with a fake platform side. The spool host is mocked at
// the Pigeon channel level (the generated codec), the spike metrics channel
// at the BasicMessageChannel level. Proves the drain/ack wire format, the
// code-only error mapping (FU-034) and that only ULIDs/codes are sent.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spike_channel.dart';
import 'package:zaghlol/ingestion/spool_port.dart';

import 'ingestion_fakes.dart';

const String _prefix = 'dev.flutter.pigeon.zaghlol.AndroidCaptureHostApi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = AndroidCaptureHostApi.pigeonChannelCodec;

  tearDown(() {
    messenger.setMockMessageHandler('$_prefix.drainSpool', null);
    messenger.setMockMessageHandler('$_prefix.ackSpool', null);
    messenger.setMockMessageHandler(spikeChannelName, null);
  });

  group('PigeonSpoolPort over a fake native host', () {
    test('drain returns entries; ack sends exactly the ids', () async {
      final acked = <Object?>[];
      int? askedMax;
      messenger.setMockMessageHandler('$_prefix.drainSpool', (data) async {
        askedMax = (codec.decodeMessage(data)! as List<Object?>)[0]! as int;
        return codec.encodeMessage(<Object?>[
          [entry(sid(1)), entry(sid(2))],
        ]);
      });
      messenger.setMockMessageHandler('$_prefix.ackSpool', (data) async {
        acked.add((codec.decodeMessage(data)! as List<Object?>)[0]);
        return codec.encodeMessage(<Object?>[null]);
      });
      final port = PigeonSpoolPort();
      final got = await port.drain(20);
      expect(askedMax, 20);
      expect(got.map((e) => e.id), [sid(1), sid(2)]);
      expect(got.first.simSlot, 0);
      await port.ack([sid(1), sid(2)]);
      expect(acked, [
        [sid(1), sid(2)],
      ]);
    });

    test('a native error becomes a code-only exception', () async {
      messenger.setMockMessageHandler('$_prefix.drainSpool', (data) async {
        return codec.encodeMessage(<Object?>[
          'SPOOL_DECRYPT_FAILED',
          null,
          null,
        ]);
      });
      await expectLater(
        PigeonSpoolPort().drain(1),
        throwsA(
          isA<SpoolPortException>().having(
            (e) => e.code,
            'code',
            'PLATFORM_SPOOL_DECRYPT_FAILED',
          ),
        ),
      );
    });

    test('an error code carrying text becomes PLATFORM_UNKNOWN', () async {
      messenger.setMockMessageHandler('$_prefix.ackSpool', (data) async {
        return codec.encodeMessage(<Object?>[
          '$canary paid EGP 5',
          '$canary message',
          'details $canary',
        ]);
      });
      Object? error;
      try {
        await PigeonSpoolPort().ack([sid(1)]);
      } on SpoolPortException catch (e) {
        error = e;
      }
      expect('$error', 'PLATFORM_UNKNOWN');
    });

    test('no native host (not devSms) → code-only failure', () async {
      await expectLater(
        PigeonSpoolPort().drain(1),
        throwsA(
          isA<SpoolPortException>().having(
            (e) => e.code,
            'code',
            'PLATFORM_UNKNOWN',
          ),
        ),
      );
    });
  });

  group('spike metrics channel', () {
    test('marks carry only stage names and ids; drain is answered', () async {
      final sent = <Object?>[];
      messenger.setMockMessageHandler(spikeChannelName, (data) async {
        sent.add(const StandardMessageCodec().decodeMessage(data));
        return null;
      });
      final channel = SpikeChannel();
      channel.onCommand((cmd) async {
        expect(cmd, 'drain');
        return const CycleResult(CycleOutcome.ok, drained: 2).toWire();
      });
      channel.ready();
      channel.dbOpen();
      channel.mark('commit', [sid(1)]);
      await pumpEventQueue();
      expect(sent, [
        {'ev': 'ready'},
        {'ev': 'db_open'},
        {
          'ev': 'mark',
          'stage': 'commit',
          'ids': [sid(1)],
        },
      ]);

      ByteData? reply;
      await messenger.handlePlatformMessage(
        spikeChannelName,
        const StandardMessageCodec().encodeMessage({'cmd': 'drain'}),
        (r) => reply = r,
      );
      expect(const StandardMessageCodec().decodeMessage(reply), {
        'result': 'OK',
        'drained': 2,
        'inserted': 0,
        'code': null,
      });
    });

    test('unknown commands get no answer', () async {
      final channel = SpikeChannel();
      channel.onCommand((cmd) async => 'should not run');
      ByteData? reply;
      await messenger.handlePlatformMessage(
        spikeChannelName,
        const StandardMessageCodec().encodeMessage('drain'),
        (r) => reply = r,
      );
      expect(const StandardMessageCodec().decodeMessage(reply), isNull);
    });
  });
}
