// T-048: InboxScanner over fakes. Synthetic data; a canary proves no body,
// address or amount reaches progress or errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/capture/application/scan.dart';
import 'package:zaghlol/features/capture/domain/scan_plan.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';

import '../support/capture_fakes.dart';
import '../support/scan_fakes.dart';

const int now = 1800000000000;
const int since = now - 86400000 * 30;

void main() {
  late FakeHost host;
  late FakeIngestStore store;
  late FakeSenders senders;
  late InboxScanner scanner;

  const zbank = ScanSender(
    'ZBANK',
    ScanSenderKind.registry,
    institutionCode: 'zbank',
  );
  const ybank = ScanSender(
    'YBANK',
    ScanSenderKind.registry,
    institutionCode: 'ybank',
  );
  const coop = ScanSender('MYCOOP', ScanSenderKind.userNamed);
  const phone = ScanSender('01000000000', ScanSenderKind.userPhone);

  setUp(() {
    host = FakeHost();
    store = FakeIngestStore();
    senders = FakeSenders([zbank, ybank, coop, phone]);
    scanner = InboxScanner(
      host: host,
      senders: senders,
      store: store,
      nowMs: () => now,
    );
  });
  tearDown(() => scanner.dispose());

  ScanRequest req({bool personal = false, Set<String>? only}) => ScanRequest(
    sinceMs: since,
    includePersonal: personal,
    onlyInstitutions: only,
  );

  test('pages through the inbox: first page small, later pages 500; every row '
      'ingested once with origin inboxScan and channel sms', () async {
    host.onQueryInbox = inboxOf([
      for (var i = 1; i <= 1200; i++) row(i, i.isEven ? 'ZBANK' : 'YBANK'),
    ]);
    final p = await scanner.run(req());
    expect(p.phase, ScanPhase.done);
    expect(p.scanned, 1200);
    expect(p.imported, 1200);
    expect(p.institutions, 2);
    expect(
      [for (final q in host.inboxQueries) q.pageSize],
      [100, 500, 500, 500],
    );
    expect(store.all.length, 1200);
    expect(store.all.every((m) => m.channel == 'sms'), isTrue);
    expect(store.all.every((m) => m.origin == MessageOrigin.inboxScan), isTrue);
    expect(store.batches.every((b) => b.length <= kIngestBatchSize), isTrue);
    expect({for (final m in store.all) m.deliveryId}.length, 1200);
  });

  test('asks only for registry and non-phone user senders by default; never '
      'the phone-number sender (FU-109)', () async {
    host.onQueryInbox = inboxOf([row(1, 'ZBANK')]);
    await scanner.run(req());
    final asked = host.inboxQueries.expand((q) => q.senderAddresses).toSet();
    expect(asked, {'MYCOOP', 'YBANK', 'ZBANK'});
  });

  test('personal opt-in: separate query, since raised to 3 months, origin '
      'inboxScanPersonal; others keep the full depth', () async {
    host.onQueryInbox = inboxOf([row(1, '01000000000'), row(2, 'ZBANK')]);
    final wide = ScanRequest(
      sinceMs: monthsAgoMs(now, 12),
      includePersonal: true,
    );
    final p = await scanner.run(wide);
    expect(p.phase, ScanPhase.done);
    final personalQ = host.inboxQueries.where(
      (q) => q.senderAddresses.contains('01000000000'),
    );
    expect(personalQ.single.senderAddresses, ['01000000000']);
    expect(
      personalQ.single.sinceEpochMs,
      monthsAgoMs(now, kPersonalScanMonths),
    );
    final fullQ = host.inboxQueries.where(
      (q) => q.senderAddresses.contains('ZBANK'),
    );
    expect(fullQ.single.sinceEpochMs, monthsAgoMs(now, 12));
    expect(fullQ.single.senderAddresses.contains('01000000000'), isFalse);
    final origins = {for (final m in store.all) m.source: m.origin};
    expect(origins['01000000000'], MessageOrigin.inboxScanPersonal);
    expect(origins['ZBANK'], MessageOrigin.inboxScan);
  });

  test('more than 900 senders are split into several queries', () async {
    senders.senders = [
      for (var i = 0; i < 1000; i++) ScanSender('S$i', ScanSenderKind.registry),
    ];
    host.onQueryInbox = inboxOf([row(1, 'S5'), row(2, 'S950')]);
    final p = await scanner.run(req());
    expect(host.inboxQueries.map((q) => q.senderAddresses.length).toList(), [
      900,
      100,
    ]);
    expect(p.imported, 2);
  });

  test(
    'a re-scan for one institution asks only for its senders (FR-CAP-07)',
    () async {
      host.onQueryInbox = inboxOf([row(1, 'ZBANK'), row(2, 'YBANK')]);
      final p = await scanner.run(req(only: {'zbank'}));
      expect(host.inboxQueries.single.senderAddresses, ['ZBANK']);
      expect(p.imported, 1);
    },
  );

  test('duplicates and drops (ignored cards, EC-62) are counted as skipped, '
      'not imported', () async {
    store.outcome = (m) => switch (m.deliveryId) {
      '1' => const IngestDuplicate(),
      '2' => const IngestDropped('ignored_card'),
      _ => const IngestInserted('t'),
    };
    host.onQueryInbox = inboxOf([for (var i = 1; i <= 4; i++) row(i, 'ZBANK')]);
    final p = await scanner.run(req());
    expect((p.imported, p.skipped), (2, 2));
  });

  test('INVALID_ARGUMENT restarts the scan with a fresh sender list and '
      'finishes (FU-109)', () async {
    var calls = 0;
    final inner = inboxOf([for (var i = 1; i <= 150; i++) row(i, 'ZBANK')]);
    host.onQueryInbox = (q) async {
      calls++;
      if (calls == 2) throw hostError('INVALID_ARGUMENT');
      return inner(q);
    };
    final p = await scanner.run(req());
    expect(p.phase, ScanPhase.done);
    expect(p.restarts, 1);
    expect(senders.reads, 2);
  });

  test(
    'a cursor that keeps being refused ends as failed after the restart cap',
    () async {
      host.onQueryInbox = (q) async => throw hostError('INVALID_ARGUMENT');
      final p = await scanner.run(req());
      expect(p.phase, ScanPhase.failed);
      expect(p.code, 'INVALID_ARGUMENT');
      expect(p.restarts, kMaxScanRestarts);
      expect(store.all, isEmpty);
    },
  );

  test('IO_ERROR on a page is retried, then fails with the code', () async {
    var calls = 0;
    final inner = inboxOf([row(1, 'ZBANK')]);
    host.onQueryInbox = (q) async {
      if (++calls <= 2) throw hostError('IO_ERROR');
      return inner(q);
    };
    expect((await scanner.run(req())).phase, ScanPhase.done);
    host.onQueryInbox = (q) async => throw hostError('IO_ERROR');
    final p = await scanner.run(req());
    expect((p.phase, p.code), (ScanPhase.failed, 'IO_ERROR'));
  });

  for (final code in ['PERMISSION_DENIED', 'NOT_AVAILABLE']) {
    test('$code ends as failed with that code and ingests nothing', () async {
      host.onQueryInbox = (q) async => throw hostError(code);
      final p = await scanner.run(req());
      expect((p.phase, p.code), (ScanPhase.failed, code));
      expect(store.all, isEmpty);
    });
  }

  test(
    'a transient write failure is retried; a hard one fails the scan',
    () async {
      host.onQueryInbox = inboxOf([row(1, 'ZBANK')]);
      store.failOn = (c) =>
          c == 1 ? IngestBatchFailed(IngestBatchFailed.writeFailed) : null;
      expect((await scanner.run(req())).phase, ScanPhase.done);
      expect(store.all.length, 1);

      final s2 = FakeIngestStore()
        ..failOn = (c) => IngestBatchFailed(IngestBatchFailed.configInvalid);
      final sc = InboxScanner(
        host: host,
        senders: senders,
        store: s2,
        nowMs: () => now,
      );
      final p = await sc.run(req());
      expect((p.phase, p.code), (ScanPhase.failed, 'CONFIG_INVALID'));
      await sc.dispose();
    },
  );

  test(
    'a store that cannot open fails with its code before any query',
    () async {
      store.openFails = const IngestStoreUnavailable('DB_MIGRATION_PENDING');
      final p = await scanner.run(req());
      expect((p.phase, p.code), (ScanPhase.failed, 'DB_MIGRATION_PENDING'));
      expect(host.inboxQueries, isEmpty);
    },
  );

  test(
    'kept (unstorable) messages are not counted and do not stop the scan',
    () async {
      host.onQueryInbox = inboxOf([row(1, 'ZBANK'), row(2, 'ZBANK')]);
      store.outcome = (m) => const IngestInserted('t');
      final real = store;
      final wrapper = _DropFirst(real);
      final sc = InboxScanner(
        host: host,
        senders: senders,
        store: wrapper,
        nowMs: () => now,
      );
      final p = await sc.run(req());
      expect((p.phase, p.imported), (ScanPhase.done, 1));
      await sc.dispose();
    },
  );

  test('cancel stops after the current batch', () async {
    host.onQueryInbox = inboxOf([
      for (var i = 1; i <= 1000; i++) row(i, 'ZBANK'),
    ]);
    final sub = scanner.changes.listen((p) {
      if (p.imported >= 100) scanner.cancel();
    });
    final p = await scanner.run(req());
    await sub.cancel();
    expect(p.phase, ScanPhase.cancelled);
    expect(p.imported, lessThan(1000));
    expect(p.imported, greaterThanOrEqualTo(100));
  });

  test('two concurrent requests run one scan (single flight)', () async {
    host.onQueryInbox = inboxOf([row(1, 'ZBANK')]);
    final a = scanner.run(req());
    final b = scanner.run(req());
    expect(identical(a, b), isTrue);
    await a;
    expect(host.inboxQueries.length, 1);
    expect(scanner.isRunning, isFalse);
  });

  test('progress is emitted per batch and carries counts only', () async {
    host.onQueryInbox = inboxOf([
      for (var i = 1; i <= 250; i++) row(i, 'ZBANK', body: 'ZG_CANARY_7731 $i'),
    ]);
    final seen = <ScanProgress>[];
    final sub = scanner.changes.listen(seen.add);
    await scanner.run(req());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first.phase, ScanPhase.running);
    expect(seen.last.phase, ScanPhase.done);
    expect(
      seen.map((p) => p.imported).toList(),
      orderedEquals([...seen.map((p) => p.imported)]..sort()),
    );
    for (final p in seen) {
      expect('$p', isNot(contains('ZG_CANARY')));
      expect('$p', isNot(contains('ZBANK')));
    }
  });

  test('an unexpected error becomes SCAN_INTERNAL without its text', () async {
    host.onQueryInbox = (q) async => throw StateError('ZG_CANARY_7731 body');
    final p = await scanner.run(req());
    expect((p.phase, p.code), (ScanPhase.failed, 'SCAN_INTERNAL'));
    expect('${p.code}', isNot(contains('CANARY')));
  });

  test('no senders at all: done with nothing queried', () async {
    senders.senders = [phone];
    final p = await scanner.run(req());
    expect((p.phase, p.scanned), (ScanPhase.done, 0));
    expect(host.inboxQueries, isEmpty);
  });
}

/// Leaves the first message of every batch without an outcome (kept).
final class _DropFirst implements IngestStore {
  _DropFirst(this._inner);
  final FakeIngestStore _inner;
  @override
  Future<bool> databaseExists() => _inner.databaseExists();
  @override
  Future<void> open() => _inner.open();
  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) async {
    final r = await _inner.ingest(batch);
    final id = batch.first.deliveryId;
    return IngestBatchResult(
      outcomes: {...r.outcomes}..remove(id),
      ackable: [
        for (final a in r.ackable)
          if (a != id) a,
      ],
      changedTxnIds: const {},
      changedAccountIds: const {},
      createdAccountIds: const {},
      kept: [id],
    );
  }

  @override
  Future<void> close() => _inner.close();
}
