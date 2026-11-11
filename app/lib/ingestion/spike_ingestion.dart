// T-008 (SPK-01): wires one IngestionCycle for an engine. The headless engine
// (ingestion_main.dart) never creates, wipes or migrates (Q6); the devSms UI
// engine (spike_foreground.dart) opens like the app will (create allowed).
// Cycles are serialised: a request during a run schedules exactly one more.
// close() (native `close` command before the engine is destroyed, F1) waits
// for a running cycle, then closes the database; a later drain reopens.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../core/db/db_directory.dart';
import '../core/db/db_key_providers.dart';
import 'ingest_store.dart';
import 'ingestion_cycle.dart';
import 'spike_registry.dart';
import 'spool_port.dart';

final class SpikeIngestion {
  SpikeIngestion({
    required this.marks,
    required this.headless,
    SpoolPort? spool,
    IngestStore Function(Directory dbDirectory)? store,
    Future<Directory> Function()? dbDirectory,
    Registry Function()? registry,
  }) : _spool = spool ?? PigeonSpoolPort(),
       _storeFactory = store ?? (headless ? _headlessStore : _uiStore),
       _dbDirectory = dbDirectory ?? resolveDbDirectory,
       _registry = registry ?? loadSpikeRegistry;

  final CycleMarks marks;
  final bool headless;
  final SpoolPort _spool;
  final IngestStore Function(Directory) _storeFactory;
  final Future<Directory> Function() _dbDirectory;

  /// The database directory resolver (FU-065 S-7: the same function in both
  /// engines).
  Future<Directory> Function() get dbDirectoryResolver => _dbDirectory;
  final Registry Function() _registry;

  IngestionCycle? _cycle;
  Future<CycleResult>? _running;
  Future<void>? _closing;
  bool _again = false;

  static IngestStore _headlessStore(Directory dir) =>
      ProviderIngestStore(ProviderIngestStore.headlessContainer(dir));

  static IngestStore _uiStore(Directory dir) => ProviderIngestStore(
    ProviderContainer(overrides: [dbDirectoryProvider.overrideWithValue(dir)]),
  );

  /// Runs a cycle, or joins the running one and runs once more after it.
  Future<CycleResult> drain() {
    final closing = _closing;
    if (closing != null) return closing.then((_) => drain());
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final next = _loop();
    _running = next;
    return next;
  }

  Future<CycleResult> _loop() async {
    try {
      var result = await _runOnce();
      while (_again && result.outcome == CycleOutcome.ok) {
        _again = false;
        result = await _runOnce();
      }
      return result;
    } finally {
      _again = false;
      _running = null;
    }
  }

  /// Waits for a running cycle (and the one more run it may have scheduled),
  /// then closes the store: `await`s the database close, so when this
  /// completes no connection, transaction or WAL lock of this engine is left.
  /// Never throws. A drain requested meanwhile runs after it and reopens.
  Future<void> close() {
    final closing = _closing;
    if (closing != null) return closing;
    final next = _close();
    _closing = next;
    return next;
  }

  Future<void> _close() async {
    try {
      while (_running != null) {
        await _running!.then<void>((_) {}, onError: (Object _) {});
      }
      final cycle = _cycle;
      _cycle = null;
      await cycle?.store.close();
    } on Object {
      // Code-free: the engine is torn down next either way.
    } finally {
      _closing = null;
    }
  }

  Future<CycleResult> _runOnce() async {
    try {
      final cycle = _cycle ??= await _build();
      return await cycle.run();
    } on Object {
      return const CycleResult(CycleOutcome.retry, code: 'INGEST_SETUP_FAILED');
    }
  }

  Future<IngestionCycle> _build() async {
    final registry = _registry();
    final pipeline = ParsingPipeline(registry);
    return IngestionCycle(
      spool: _spool,
      store: _storeFactory(await _dbDirectory()),
      parse: pipelineParser(pipeline),
      registryVersion: registry.registryVersion,
      mayCreateDatabase: !headless,
      marks: marks,
    );
  }
}
