// T-046 fix round: CR-1 / F2 (one poison message must not block the batch
// or the spool), CR-2 (T-075's categorizer, one per batch) and CR-6 (a hash
// duplicate never reaches the categorizer, hooks or accounts). Synthetic
// messages only.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/capture_api.g.dart';
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_ports.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/ingestion/ingest_store.dart';
import 'package:zaghlol/ingestion/ingestion_cycle.dart';

import '../../../ingestion/ingestion_fakes.dart' show FakeSpool;
import '../support/fake_categorizer.dart';
import '../support/ingest_harness.dart';

String buy(String amount, {String at = 'Synth Shop'}) =>
    'ZBANK: Purchase EGP $amount at $at card *4321';

final String poisonBody = buy('13.00', at: 'Poison Shop');

final class CountingHook implements PostPersistHook {
  int calls = 0;
  @override
  Future<void> afterPersist(PersistedTxn txn) async => calls++;
}

/// The cycle's store over one use case (the database is already open).
final class UseCaseStore implements IngestStore {
  UseCaseStore(this.useCase);
  final IngestRawMessages useCase;
  @override
  Future<bool> databaseExists() async => true;
  @override
  Future<void> open() async {}
  @override
  Future<IngestBatchResult> ingest(List<IncomingMessage> batch) =>
      useCase(batch);
  @override
  Future<void> close() async {}
}

SpoolEntry spoolSms(String id, String body) => SpoolEntry(
  id: id,
  channel: 'sms',
  source: zbankSms,
  body: body,
  receivedAtMs: t0,
  simSlot: 0,
);

void main() {
  late IngestWorld w;

  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  Future<Map<String, Object?>> onlyReviewPayload() async =>
      jsonDecode((await w.reviews()).single['payload']! as String)
          as Map<String, Object?>;

  group('CR-1/F2: a poison message is isolated (use case)', () {
    test('a StateError in the categorizer does not take the other messages '
        'of the batch with it', () async {
      final spy = SpyCategorizerPorts(poison: 'poison');
      final r = await w.useCase(categorizerFactory: spy.factory)([
        sms('g1', buy('10.00')),
        sms('p', poisonBody),
        sms('g2', buy('11.00')),
      ]);
      expect(r.outcomes['g1'], isA<IngestInserted>());
      expect(r.outcomes['g2'], isA<IngestInserted>());
      expect((r.outcomes['p']! as IngestReview).reviewKind, 'unrecognized');
      expect(r.ackable, ['g1', 'p', 'g2']);
      expect(r.kept, isEmpty);
      expect(await w.count('transactions'), 2);
      expect(await w.count('raw_messages'), 3);
      expect(await onlyReviewPayload(), {
        'reason': 'ingestFailed',
        'code': 'INGEST_INTERNAL',
      });
      expect(w.diag.counts['ING_QUARANTINED'], 1);
      expect(r.event, isNotNull);
    });

    test('a batch of one: quarantined at once; its re-delivery is a '
        'duplicate', () async {
      final useCase = w.useCase(
        categorizerFactory: SpyCategorizerPorts(poison: 'poison').factory,
      );
      final r = await useCase([sms('p', poisonBody)]);
      expect(r.outcomes['p'], isA<IngestReview>());
      expect(r.ackable, ['p']);
      expect(await w.count('transactions'), 0);
      final again = await useCase([sms('p', poisonBody)]);
      expect(again.outcomes['p'], isA<IngestDuplicate>());
      expect(await w.count('raw_messages'), 1);
    });

    test('FU-109: a personal-origin poison message is dropped, never '
        'queued for review', () async {
      final r = await w.useCase(
        categorizerFactory: SpyCategorizerPorts(poison: 'poison').factory,
      )([sms('p', poisonBody, origin: MessageOrigin.inboxScanPersonal)]);
      expect(r.outcomes['p'], isA<IngestDropped>());
      expect((r.outcomes['p']! as IngestDropped).reason, 'personal_unparsed');
      expect(await w.reviews(), isEmpty);
      expect(await w.count('raw_messages'), 0);
    });

    test('an OTP is never quarantined: the Guard and stage 0 still drop '
        'it', () async {
      final r = await w.useCase(
        categorizerFactory: SpyCategorizerPorts(poison: 'poison').factory,
      )([sms('p', poisonBody), sms('o', 'ZBANK: your OTP is 482913')]);
      expect(r.outcomes['o'], isA<IngestDropped>());
      expect(r.ackable, ['p', 'o']);
      expect(await w.count('raw_messages'), 1);
    });

    test('a message that can not be stored even alone is kept (not acked, '
        'no outcome); the others commit', () async {
      final useCase = w.useCase(
        wrap: (inner) =>
            FaultyStore(inner, poisonRaw: (row) => row.body == poisonBody),
      );
      final r = await useCase([
        sms('p', poisonBody),
        sms('g1', buy('10.00')),
        sms('g2', buy('11.00')),
      ]);
      expect(r.kept, ['p']);
      expect(r.ackable, ['g1', 'g2']);
      expect(r.outcomes.containsKey('p'), isFalse);
      expect(await w.count('transactions'), 2);
      expect(await w.count('raw_messages'), 2);
      expect(w.diag.counts['ING_KEPT'], 1);
    });
  });

  group('CR-1/F2: the drain cycle gets past a poison entry', () {
    test('spool [poison, good1, good2, good3], batch size 2 → goods stored, '
        'poison in review, all acked; a later cycle proceeds', () async {
      final spool = FakeSpool([
        spoolSms('p', poisonBody),
        spoolSms('g1', buy('10.00')),
        spoolSms('g2', buy('11.00')),
        spoolSms('g3', buy('12.00')),
      ], []);
      final store = UseCaseStore(
        w.useCase(
          categorizerFactory: SpyCategorizerPorts(poison: 'poison').factory,
        ),
      );
      IngestionCycle cycle() => IngestionCycle(
        spool: spool,
        store: store,
        mayCreateDatabase: false,
        batchSize: 2,
      );
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.ok);
      expect(r.stuck, 0);
      expect(spool.pending, isEmpty);
      expect(spool.acked.expand((a) => a).toSet(), {'p', 'g1', 'g2', 'g3'});
      expect(await w.count('transactions'), 3);
      expect(await onlyReviewPayload(), {
        'reason': 'ingestFailed',
        'code': 'INGEST_INTERNAL',
      });

      spool.pending.add(spoolSms('g4', buy('14.00')));
      final next = await cycle().run();
      expect(next.outcome, CycleOutcome.ok);
      expect(spool.pending, isEmpty);
      expect(await w.count('transactions'), 4);
    });

    test('an entry that can not be stored at all is held (T-041, FU-105); '
        'everything behind it is acked', () async {
      final spool = FakeSpool([
        spoolSms('p', poisonBody),
        spoolSms('g1', buy('10.00')),
        spoolSms('g2', buy('11.00')),
        spoolSms('g3', buy('12.00')),
      ], []);
      final store = UseCaseStore(
        w.useCase(
          wrap: (inner) =>
              FaultyStore(inner, poisonRaw: (row) => row.body == poisonBody),
        ),
      );
      IngestionCycle cycle() => IngestionCycle(
        spool: spool,
        store: store,
        mayCreateDatabase: false,
        batchSize: 2,
      );
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.ok);
      expect(r.stuck, 0);
      expect(r.held, 1);
      expect(r.code, 'INGEST_MSG_UNSTORABLE');
      expect(spool.pending, isEmpty);
      expect([for (final e in spool.held) e.id], ['p']);
      expect(spool.acked.expand((a) => a), isNot(contains('p')));
      expect(await w.count('transactions'), 3);

      spool.pending.add(spoolSms('g4', buy('14.00')));
      final next = await cycle().run();
      expect(next.stuck, 0);
      expect(next.held, 0);
      expect(spool.pending, isEmpty);
      expect(await w.count('transactions'), 4);
    });

    test('when the hold fails, the unstorable entry stays in the spool as '
        'the only stuck entry; everything behind it is acked', () async {
      final spool = FakeSpool([
        spoolSms('p', poisonBody),
        spoolSms('g1', buy('10.00')),
        spoolSms('g2', buy('11.00')),
        spoolSms('g3', buy('12.00')),
      ], []);
      final store = UseCaseStore(
        w.useCase(
          wrap: (inner) =>
              FaultyStore(inner, poisonRaw: (row) => row.body == poisonBody),
        ),
      );
      IngestionCycle cycle() => IngestionCycle(
        spool: spool,
        store: store,
        mayCreateDatabase: false,
        batchSize: 2,
      );
      spool.holdFails = 'IO_ERROR';
      final r = await cycle().run();
      expect(r.outcome, CycleOutcome.ok);
      expect(r.stuck, 1);
      expect(r.code, 'INGEST_MSG_UNSTORABLE');
      expect([for (final e in spool.pending) e.id], ['p']);
      expect(await w.count('transactions'), 3);

      spool.pending.add(spoolSms('g4', buy('14.00')));
      final next = await cycle().run();
      expect(next.stuck, 1);
      expect([for (final e in spool.pending) e.id], ['p']);
      expect(await w.count('transactions'), 4);
    });

    test('a transient failure still ends the cycle RETRY with nothing '
        'acked', () async {
      final spool = FakeSpool([spoolSms('g1', buy('10.00'))], []);
      final store = UseCaseStore(
        w.useCase(wrap: (inner) => FaultyStore(inner, failAt: 1)),
      );
      final r = await IngestionCycle(
        spool: spool,
        store: store,
        mayCreateDatabase: false,
      ).run();
      expect(r.outcome, CycleOutcome.retry);
      expect(r.code, 'DB_WRITE_FAILED');
      expect(spool.acked, isEmpty);
    });
  });

  group('CR-2 / CR-6: categorizer seam', () {
    test('one categorizer per batch', () async {
      final spy = SpyCategorizerPorts();
      final useCase = w.useCase(categorizerFactory: spy.factory);
      await useCase([sms('a', buy('10.00')), sms('b', buy('11.00'))]);
      expect(spy.made, 1);
      expect(spy.ruleCalls, 2);
      await useCase([sms('c', buy('12.00'))]);
      expect(spy.made, 2);
    });

    test('a hash duplicate reaches neither the categorizer nor a hook, and '
        'creates no account', () async {
      await w.run([sms('a', buy('10.00'))]);
      final accounts = await w.count('accounts');
      final spy = SpyCategorizerPorts();
      final hook = CountingHook();
      final r = await w.useCase(categorizerFactory: spy.factory, hooks: [hook])(
        [sms('a2', buy('10.00'))],
      );
      expect(r.outcomes['a2'], isA<IngestDuplicate>());
      expect(spy.ruleCalls, 0);
      expect(hook.calls, 0);
      expect(await w.count('accounts'), accounts);
    });

    test("the stored source comes from T-075's decision (user rule)", () async {
      await w.db.customStatement(
        'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
        "sort) VALUES ('c1', 'أكل', 'Food', 'i', '#000000', 'needs', 1)",
      );
      await w.db.customStatement(
        'INSERT INTO merchant_rules (id, match_kind, match_value, '
        "category_id, created_at) VALUES ('r1', 'merchant_norm', "
        "'synth shop', 'c1', 0)",
      );
      await w.run([sms('a', buy('10.00'))]);
      final t = (await w.txns()).single;
      expect(t['category_id'], 'c1');
      expect(t['category_source'], 'user_rule');
    });
  });
}
