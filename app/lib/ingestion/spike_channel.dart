// T-008 (SPK-01): the spike-only metrics/control channel
// `zaghlol/spike_metrics` (not a platform contract; removed with the spike).
// Dart → native: {ev: ready | db_open | mark, stage, ids}. Native → Dart:
// {cmd: drain}, answered with CycleResult.toWire(); {cmd: close} (before the
// headless engine is destroyed), answered with {result: CLOSED} once the
// database is closed. Only stage names, codes, counts and ULIDs cross it;
// never a body, sender or amount.

import 'dart:async';

import 'package:flutter/services.dart';

import 'ingestion_cycle.dart';

const String spikeChannelName = 'zaghlol/spike_metrics';

final class SpikeChannel implements CycleMarks {
  SpikeChannel([BasicMessageChannel<Object?>? channel])
    : _channel =
          channel ??
          const BasicMessageChannel<Object?>(
            spikeChannelName,
            StandardMessageCodec(),
          );

  final BasicMessageChannel<Object?> _channel;

  /// Dart entry reached and the command handler is installed (t4).
  void ready() => _send(const {'ev': 'ready'});

  @override
  void dbOpen() => _send(const {'ev': 'db_open'});

  @override
  void mark(String stage, List<String> ids) =>
      _send({'ev': 'mark', 'stage': stage, 'ids': ids});

  /// Installs the native → Dart command handler.
  void onCommand(Future<Object?> Function(String command) handler) {
    _channel.setMessageHandler((message) async {
      final cmd = message is Map ? message['cmd'] : null;
      if (cmd is! String) return null;
      return handler(cmd);
    });
  }

  void _send(Object message) {
    unawaited(
      _channel.send(message).then<void>((_) {}, onError: (Object _) {}),
    );
  }
}
