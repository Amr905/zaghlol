// T-008: the real database path of a drain cycle on the host's sqlite3mc:
// the UI engine (create allowed) creates zaghlol.db; the headless store
// (allowMigration/allowCreateOrWipe false) finds, opens and writes it through
// IngestRawMessages (T-046); body_hash dedupes a re-delivered entry.

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/db_directory.dart';
import 'package:zaghlol/core/db/db_key_providers.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';
import 'package:zaghlol/ingestion/spike_ingestion.dart';
import 'package:zaghlol/ingestion/spike_registry.dart';
import 'package:zaghlol/ingestion/ulid.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/fake_secret_store.dart';
import '../support/synthetic_key.dart';
import 'ingestion_fakes.dart';

void main() {
  late Directory root;
  late Directory dbDir;
  late FakeSecretStore secrets;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = Directory.systemTemp.createTempSync('ingest');
    dbDir = dbDirectoryFor(root);
    secrets = FakeSecretStore();
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<Override> keys() => [
    secretStoreProvider.overrideWithValue(secrets),
    keyGeneratorProvider.overrideWithValue(FixedKeyGenerator(61)),
    appTempDirectoryProvider.overrideWithValue(() async => root),
  ];

  final registry = loadSpikeRegistry();
  IngestRawMessages build(AppDatabase db) => buildIngestRawMessages(
    db,
    pipeline: ParsingPipeline(registry),
    guardBase: RegistryGuardBase(registry),
    newId: UlidGenerator().next,
  );

  ProviderIngestStore headlessStore() => ProviderIngestStore(
    ProviderIngestStore.headlessContainer(dbDir, testOverrides: keys()),
    build: build,
  );

  ProviderIngestStore uiStore() => ProviderIngestStore(
    ProviderContainer(
      overrides: [...keys(), dbDirectoryProvider.overrideWithValue(dbDir)],
    ),
    build: build,
  );

  IngestionCycle cycleOver(IngestStore store, FakeSpool spool) =>
      IngestionCycle(spool: spool, store: store, mayCreateDatabase: false);

  test(
    'headless before the UI ever ran: NO_DATABASE, nothing created',
    () async {
      final log = <String>[];
      final spool = FakeSpool([entry(sid(1))], log);
      final store = headlessStore();
      addTearDown(store.close);
      final r = await cycleOver(store, spool).run();
      expect(r.outcome, CycleOutcome.noDatabase);
      expect(dbDir.existsSync(), isFalse);
      expect(secrets.writeCalls, 0);
      expect(spool.pending, hasLength(1));
    },
  );

  test('UI creates the database; headless commits through the use case '
      'and dedupes a re-delivery by body_hash', () async {
    final ui = uiStore();
    await ui.open();
    await ui.close();
    expect(dbDir.listSync().whereType<File>(), isNotEmpty);

    final log = <String>[];
    final spool = FakeSpool([entry(sid(1)), entry(sid(2), body: 'other')], log);
    final headless = headlessStore();
    addTearDown(headless.close);
    final first = await cycleOver(headless, spool).run();
    expect(first.outcome, CycleOutcome.ok);
    expect(first.inserted, 2);
    expect(secrets.writeCalls, 1, reason: 'only the UI first run wrote a key');

    // Crash between commit and ack: the same message comes back.
    spool.pending.add(entry(sid(3)));
    final again = await cycleOver(headless, spool).run();
    expect(again.outcome, CycleOutcome.ok);
    expect(again.drained, 1);
    expect(again.inserted, 0, reason: 'unique body_hash absorbs it');
    expect(spool.pending, isEmpty);
  });

  // F1/F7: close() returns only after the connection is closed. Observed as
  // the process's open file descriptors on zaghlol.db (Linux /proc).
  int dbFds() =>
      Directory('/proc/self/fd')
          .listSync(followLinks: false)
          .map((l) {
            try {
              return (l as Link).targetSync();
            } on FileSystemException {
              return '';
            }
          })
          .where((t) => t.startsWith('${dbDir.path}/zaghlol.db'))
          .length;

  test('close after a drain closes the database before it returns; a drain '
      'after close reopens (F1/F7)', () async {
    final ui = uiStore();
    await ui.open();
    await ui.close();
    expect(dbFds(), 0, reason: 'the UI store closed its connection');

    final spool = FakeSpool([entry(sid(1))], <String>[]);
    final headless = SpikeIngestion(
      marks: const NoMarks(),
      headless: true,
      spool: spool,
      store: (_, _) => headlessStore(),
      dbDirectory: () async => dbDir,
    );
    expect((await headless.drain()).inserted, 1);
    expect(dbFds(), greaterThan(0), reason: 'open while the engine lives');
    await headless.close();
    expect(dbFds(), 0, reason: 'no connection left when close returns');

    spool.pending.add(entry(sid(2), body: 'other'));
    final again = await headless.drain();
    expect(again.outcome, CycleOutcome.ok);
    expect(again.inserted, 1, reason: 'a new store reopened the database');
    await headless.close();
    expect(dbFds(), 0);
  }, skip: Directory('/proc/self/fd').existsSync() ? false : 'needs /proc');

  test('the UI engine path (SpikeIngestion, headless false) creates the '
      'database on its first drain; the headless path then uses it', () async {
    final log = <String>[];
    final ui = SpikeIngestion(
      marks: const NoMarks(),
      headless: false,
      spool: FakeSpool([], log),
      store: (_, _) => uiStore(),
      dbDirectory: () async => dbDir,
    );
    final first = await ui.drain();
    expect(first.outcome, CycleOutcome.ok);
    expect(File('${dbDir.path}/zaghlol.db').existsSync(), isTrue);

    final spool = FakeSpool([entry(sid(1))], log);
    final headless = SpikeIngestion(
      marks: const NoMarks(),
      headless: true,
      spool: spool,
      store: (_, _) => headlessStore(),
      dbDirectory: () async => dbDir,
    );
    final r = await headless.drain();
    expect(r.outcome, CycleOutcome.ok);
    expect(r.inserted, 1);
    expect(spool.pending, isEmpty);
  });

  test('the headless engine path (SpikeIngestion) never creates', () async {
    final spool = FakeSpool([entry(sid(1))], <String>[]);
    final headless = SpikeIngestion(
      marks: const NoMarks(),
      headless: true,
      spool: spool,
      store: (_, _) => headlessStore(),
      dbDirectory: () async => dbDir,
    );
    expect((await headless.drain()).outcome, CycleOutcome.noDatabase);
    expect(dbDir.existsSync(), isFalse);
    expect(spool.pending, hasLength(1));
  });

  test('both engines resolve the database directory with the same function '
      '(FU-065 S-7)', () {
    final headless = SpikeIngestion(marks: const NoMarks(), headless: true);
    final ui = SpikeIngestion(marks: const NoMarks(), headless: false);
    expect(identical(headless.dbDirectoryResolver, resolveDbDirectory), isTrue);
    expect(identical(ui.dbDirectoryResolver, resolveDbDirectory), isTrue);
  });

  test('the headless container cannot be talked into migrating or '
      'creating', () {
    // Riverpod refuses a second override of the same provider.
    expect(
      () => ProviderIngestStore.headlessContainer(
        dbDir,
        testOverrides: [allowCreateOrWipeProvider.overrideWithValue(true)],
      ),
      throwsA(anything),
    );
    final c = ProviderIngestStore.headlessContainer(
      dbDir,
      testOverrides: keys(),
    );
    addTearDown(c.dispose);
    expect(c.read(allowMigrationProvider), isFalse);
    expect(c.read(allowCreateOrWipeProvider), isFalse);
    expect(c.read(dbDirectoryProvider).path, dbDir.path);
  });
}
