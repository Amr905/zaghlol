// T-041 (from the T-008 spike's SpikeIngestion): wires one IngestionCycle for
// an engine. The headless engine (ingestion_main.dart) never creates, wipes or
// migrates (Q6); the UI engine (foreground_ingestion.dart) opens like the app
// does (create allowed). Cycles are serialised: a request during a run
// schedules exactly one more. close() (native `close`, sent at once when the
// engine is to be destroyed, also mid-drain) sets the stop flag, so the
// running cycle ends after its current batch, waits for it, then closes the
// database; a later drain reopens.

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../core/db/app_database.dart';
import '../core/db/db_directory.dart';
import '../core/db/db_key_providers.dart';
import '../features/ingestion/data/custom_institutions.dart';
import '../features/ingestion/application/ingest_raw_messages.dart';
import '../features/ingestion/data/ingest_factory.dart';
import 'ingest_store.dart';
import 'ingestion_config.dart';
import 'ingestion_cycle.dart';
import 'bundled_registry.dart';
import 'spike_registry.dart';
import 'spool_port.dart';
import 'ulid.dart';

/// The registry a build parses with: the synthetic spike registry in devSms
/// only (a compile-time constant, so AOT drops it from every other build);
/// elsewhere the bundled registry (`assets/registry/`), which must have been
/// preloaded in this isolate ([ensureDefaultRegistry]; before that the call
/// throws `INGEST_REGISTRY_MISSING` and the cycle ends `INGEST_SETUP_FAILED`).
Registry Function() get defaultRegistryLoader =>
    kIsSpikeBuild ? loadSpikeRegistry : bundledRegistrySync;

/// Makes [defaultRegistryLoader] ready (no-op for the spike build).
Future<void> ensureDefaultRegistry() async {
  if (!kIsSpikeBuild) await preloadBundledRegistry();
}

final class IngestionRunner {
  IngestionRunner({
    required this.marks,
    required this.headless,
    SpoolPort? spool,
    IngestStore Function(
      Directory dbDirectory,
      FutureOr<IngestRawMessages> Function(AppDatabase db) build,
    )?
    store,
    Future<Directory> Function()? dbDirectory,
    Registry Function()? registry,
  }) : _spool = spool ?? platformSpoolPort(),
       _storeFactory = store ?? (headless ? _headlessStore : _uiStore),
       _dbDirectory = dbDirectory ?? resolveDbDirectory,
       _registry = registry ?? defaultRegistryLoader,
       _loadsDefaultRegistry = registry == null;

  final CycleMarks marks;
  final bool headless;
  final SpoolPort _spool;
  final IngestStore Function(
    Directory,
    FutureOr<IngestRawMessages> Function(AppDatabase db),
  )
  _storeFactory;
  final Future<Directory> Function() _dbDirectory;

  /// The database directory resolver (FU-065 S-7: the same function in both
  /// engines).
  Future<Directory> Function() get dbDirectoryResolver => _dbDirectory;
  final Registry Function() _registry;
  final bool _loadsDefaultRegistry;

  IngestionCycle? _cycle;
  Future<CycleResult>? _running;
  Future<void>? _closing;
  bool _again = false;

  /// Set by [close] until it completes: the running cycle starts no new
  /// batch, and the "one more run" is skipped.
  bool _stop = false;

  static IngestStore _headlessStore(
    Directory dir,
    FutureOr<IngestRawMessages> Function(AppDatabase db) build,
  ) => ProviderIngestStore(
    ProviderIngestStore.headlessContainer(dir),
    build: build,
    rebuildPerBatch: true,
  );

  static IngestStore _uiStore(
    Directory dir,
    FutureOr<IngestRawMessages> Function(AppDatabase db) build,
  ) => ProviderIngestStore(
    ProviderContainer(overrides: [dbDirectoryProvider.overrideWithValue(dir)]),
    build: build,
    rebuildPerBatch: true,
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
      while (_again && !_stop && result.outcome == CycleOutcome.ok) {
        _again = false;
        result = await _runOnce();
      }
      return result;
    } finally {
      _again = false;
      _running = null;
    }
  }

  /// Stops the running cycle after its current batch (T-041), waits for it,
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
    _stop = true;
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
      _stop = false;
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
    if (_loadsDefaultRegistry) await ensureDefaultRegistry();
    final registry = _registry();
    final guardBase = RegistryGuardBase(registry);
    final ids = UlidGenerator();
    return IngestionCycle(
      spool: _spool,
      store: _storeFactory(
        await _dbDirectory(),
        // The user's saved templates (T-164) are read per batch, so one saved
        // meanwhile applies at once; a corrupt one is skipped.
        (db) async => buildIngestRawMessages(
          db,
          pipeline: ParsingPipeline(
            await registryWithCustomTemplates(registry, db),
          ),
          guardBase: guardBase,
          newId: ids.next,
        ),
      ),
      mayCreateDatabase: !headless,
      marks: marks,
      stopRequested: () => _stop,
    );
  }
}
