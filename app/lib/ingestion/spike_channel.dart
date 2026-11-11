// T-008 (SPK-01) / T-041: the devSms-only stage marks channel
// `zaghlol/spike_metrics` (not a platform contract; removed with the spike
// recorder). Dart → native only: {ev: db_open | mark, stage, ids}; the native
// side (SpikeTrace in src/devSms) writes them to the latency CSV. The command
// protocol it used to carry is the Pigeon HeadlessIngestionApi now
// (pigeons/ingestion_api.dart). Only stage names and ULIDs cross it; never a
// body, sender or amount. Selected by `kIsSpikeBuild` only.

import 'dart:async';

import 'package:flutter/services.dart';

import 'ingestion_config.dart';
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

  @override
  void dbOpen() => _send(const {'ev': 'db_open'});

  @override
  void mark(String stage, List<String> ids) =>
      _send({'ev': 'mark', 'stage': stage, 'ids': ids});

  void _send(Object message) {
    unawaited(
      _channel.send(message).then<void>((_) {}, onError: (Object _) {}),
    );
  }
}

/// The marks of this build: the spike channel in devSms, none elsewhere.
CycleMarks defaultCycleMarks() =>
    kIsSpikeBuild ? SpikeChannel() : const NoMarks();
