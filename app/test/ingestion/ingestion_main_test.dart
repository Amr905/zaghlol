// T-041: the headless engine's control channel (pigeons/ingestion_api.dart)
// with a fake native side at the Pigeon channel level: `ready` is sent once
// the handler is installed; `drain` answers a counts-and-code report; `close`
// answers only after the running cycle and the DB close; nothing on the wire
// carries message text.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/ingestion_api.g.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/ingestion_main.dart';
import 'package:zaghlol/ingestion/ingestion_runner.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';

import 'ingestion_fakes.dart';

const String _api = 'dev.flutter.pigeon.zaghlol.HeadlessIngestionApi';
const String _host = 'dev.flutter.pigeon.zaghlol.HeadlessIngestionHostApi';

final class _GatedStore extends FakeStore {
  _GatedStore(super.log);

  Completer<void>? gate;

  @override
  Future<bool> databaseExists() async {
    await gate?.future;
    return super.databaseExists();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = HeadlessIngestionApi.pigeonChannelCodec;

  late List<String> log;
  late FakeSpool spool;
  late _GatedStore store;
  late int readies;

  setUp(() {
    log = [];
    readies = 0;
    spool = FakeSpool([entry(sid(1), body: '$canary EGP 1')], log);
    store = _GatedStore(log);
    messenger.setMockMessageHandler('$_host.ready', (data) async {
      readies++;
      return codec.encodeMessage(<Object?>[null]);
    });
  });

  tearDown(() {
    messenger.setMockMessageHandler('$_host.ready', null);
    HeadlessIngestionApi.setUp(null);
  });

  IngestionRunner runner() => IngestionRunner(
    marks: const NoMarks(),
    headless: true,
    spool: spool,
    store: (_, _) => store,
    dbDirectory: () async => Directory.systemTemp,
    registry: loadSpikeRegistry,
  );

  /// Sends a native → Dart call and decodes Pigeon's reply envelope.
  Future<List<Object?>> call(String method) async {
    final done = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      '$_api.$method',
      codec.encodeMessage(null),
      done.complete,
    );
    return codec.decodeMessage(await done.future)! as List<Object?>;
  }

  test('ready is sent after the handler is installed', () async {
    startHeadlessIngestion(runner());
    await pumpEventQueue();
    expect(readies, 1);
    // The handler answers immediately after ready.
    final reply = await call('drain');
    expect(reply, hasLength(1));
  });

  test('drain answers counts and a code only', () async {
    startHeadlessIngestion(runner());
    final reply = await call('drain');
    final report = reply.single! as IngestCycleReport;
    expect(report.outcome, IngestOutcome.ok);
    expect(report.drained, 1);
    expect(report.inserted, 1);
    expect(report.stuck, 0);
    expect(report.held, 0);
    expect(report.code, isNull);
    expect('${report.encode()}', isNot(contains(canary)));
    expect(spool.pending, isEmpty);
  });

  test('a missing database is NO_DATABASE (never created headless)', () async {
    store.exists = false;
    startHeadlessIngestion(runner());
    final report = (await call('drain')).single! as IngestCycleReport;
    expect(report.outcome, IngestOutcome.noDatabase);
    expect(store.opens, 0);
  });

  test('close sent mid-drain answers after the drain reply and the DB '
      'close (the order native ShutdownSequence relies on)', () async {
    store.gate = Completer<void>();
    startHeadlessIngestion(runner());
    final order = <String>[];
    final drain = call('drain').then((_) => order.add('drain'));
    await pumpEventQueue();
    final close = call('close').then((_) => order.add('close'));
    await pumpEventQueue();
    expect(order, isEmpty, reason: 'close waits for the running cycle');
    store.gate!.complete();
    await Future.wait<void>([drain, close]);
    expect(order, ['drain', 'close']);
    expect(store.closes, 1);
    expect(log.last, 'close');
  });

  test('no native side: ready failing never throws', () async {
    messenger.setMockMessageHandler('$_host.ready', null);
    startHeadlessIngestion(runner(), retryDelay: Duration.zero);
    await pumpEventQueue();
  });

  // T-062: iOS installs its handler only after FlutterEngine.run() returns,
  // so the first ready can find nobody; Dart retries until native answers.
  test('ready is retried until native answers', () async {
    var calls = 0;
    messenger.setMockMessageHandler('$_host.ready', (data) async {
      calls++;
      if (calls < 3) return null; // no handler yet (channel-error)
      readies++;
      return codec.encodeMessage(<Object?>[null]);
    });
    startHeadlessIngestion(
      runner(),
      retryDelay: const Duration(milliseconds: 1),
    );
    for (var i = 0; i < 100 && readies == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(calls, 3);
    expect(readies, 1);
  });
}
