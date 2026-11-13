// T-076: the re-parse job after a registry version bump. ACs: "AC1" (an
// updated template turns a review item into a transaction), "AC2"
// (user-verified rows unchanged). All messages are synthetic.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/application/reparse.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show Registry;

import '../support/ingest_harness.dart';

const String purchase = 'ZBANK: Purchase EGP 120.50 at Synth Shop card *4321';
const String purchaseNotif = 'Purchase EGP 120.50 at Synth Shop';

// Old build: the purchase template does not match this text yet.
final Registry oldReg = loadTestRegistry(
  transformBank: (j) => j.replaceAll('^zbank: purchase egp', '^zbank: buy egp'),
);

// Old build: the purchase template was filed under an event with no handler.
final Registry pendingReg = loadTestRegistry(
  transformBank: (j) => j.replaceFirstMapped(
    RegExp(r'("zbank\.purchase\.sms".*?"event": ")card_purchase', dotAll: true),
    (m) => '${m[1]}fx_conversion',
  ),
);

// New build: the registry version is the highest template version, so a
// bump is a template that went to version 2.
final Registry newReg = loadTestRegistry(
  version: 2,
  transformBank: (j) => j.replaceFirst(
    '"id": "zbank.purchase.sms", "version": 1',
    '"id": "zbank.purchase.sms", "version": 2',
  ),
);

void main() {
  late IngestWorld w;
  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  ReparseJob job({
    Registry? registry,
    List<String>? persisted,
    bool hookThrows = false,
  }) {
    final reg = registry ?? newReg;
    final uc = w.useCase(registry: reg);
    return ReparseJob(
      store: DriftIngestStore(w.db),
      ingest: uc,
      registryVersion: reg.registryVersion,
      onPersisted: (id) async {
        persisted?.add(id);
        if (hookThrows) throw StateError('hook');
      },
      diag: w.diag,
    );
  }

  Future<void> ingestOld(String id, String body, {Registry? reg}) async {
    await w.useCase(registry: reg ?? oldReg)([sms(id, body)]);
  }

  group('AC1: review item → transaction', () {
    test('the same raw row becomes parsed, the item resolves, the '
        'transaction is created', () async {
      await ingestOld('a', purchase);
      expect((await w.raws()).single['parse_status'], 'review');
      expect(await w.count('review_items', 'resolved_at IS NULL'), 1);
      final persisted = <String>[];
      final s = await job(persisted: persisted).run();
      expect(s.converted, 1);
      final raw = (await w.raws()).single;
      expect(raw['parse_status'], 'parsed');
      expect(raw['registry_version'], 2);
      expect(raw['template_id'], 'zbank.purchase.sms');
      expect(await w.count('raw_messages'), 1);
      final t = (await w.txns()).single;
      expect(t['amount_minor'], 12050);
      expect(t['raw_message_id'], raw['id']);
      expect(t['is_user_verified'], 0);
      final item = (await w.reviews()).single;
      expect(item['resolution'], 'reparsed');
      expect(persisted, [t['id']]);
      expect(w.events, isNotEmpty);
    });

    test('a second run finds nothing to do', () async {
      await ingestOld('a', purchase);
      await job().run();
      final s = await job().run();
      expect(s.examined, 0);
      expect(await w.count('transactions'), 1);
    });

    test(
      'still unrecognized: no new review item, stamped, not retried',
      () async {
        await w.useCase(registry: oldReg)([sms('a', 'ZBANK: something new')]);
        final s = await job().run();
        expect(s.unchanged, 1);
        expect(await w.count('review_items'), 1);
        expect((await w.raws()).single['registry_version'], 2);
        expect((await job().run()).examined, 0);
      },
    );

    test('reparse_pending row with a handler now becomes a transaction; one '
        'without stays pending and is retried every run', () async {
      await ingestOld('a', purchase, reg: pendingReg);
      await w.useCase(registry: pendingReg)([
        sms('b', 'ZBANK: Converted USD 10.00 to EGP 500.00 acct *5555'),
      ]);
      expect(
        await w.count('raw_messages', "parse_status = 'reparse_pending'"),
        2,
      );
      final s = await job().run();
      expect(s.converted, 1);
      expect(s.unchanged, 1);
      expect(await w.count('transactions'), 1);
      expect(
        await w.count('raw_messages', "parse_status = 'reparse_pending'"),
        1,
      );
      expect((await job().run()).examined, 1);
      expect(await w.count('review_items'), 0);
    });

    test(
      'dedupe 2 still applies: merges into the notification payment',
      () async {
        await w.run([notif('n', purchaseNotif)]);
        await ingestOld('a', purchase);
        final s = await job().run();
        expect(s.converted, 1);
        expect(await w.count('transactions'), 1);
        expect(
          (await w.raws()).every((r) => r['parse_status'] == 'parsed'),
          isTrue,
        );
      },
    );
  });

  group('AC2: user-verified rows unchanged', () {
    Future<void> staleParsed() async {
      await w.run([sms('a', purchase)]);
      await w.db.customStatement(
        'UPDATE raw_messages SET registry_version = 1, template_version = 0',
      );
      await w.db.customStatement(
        'UPDATE transactions SET merchant_raw = NULL, merchant_norm = NULL',
      );
    }

    test('an unverified transaction gets its NULL fields filled', () async {
      await staleParsed();
      final s = await job().run();
      expect(s.updated, 1);
      expect((await w.txns()).single['merchant_raw'], isNotNull);
      expect((await w.raws()).single['template_version'], 2);
    });

    test('a user-verified transaction is not written', () async {
      await staleParsed();
      await w.db.customStatement(
        'UPDATE transactions SET is_user_verified = 1',
      );
      final before = await w.txns();
      final s = await job().run();
      expect(s.updated, 0);
      expect(await w.txns(), before);
    });

    test('a deleted transaction is not written', () async {
      await staleParsed();
      await w.db.customStatement('UPDATE transactions SET deleted_at = 5');
      final before = await w.txns();
      await job().run();
      expect(await w.txns(), before);
    });

    test('amount, direction and status are never changed', () async {
      await staleParsed();
      await w.db.customStatement('UPDATE transactions SET amount_minor = 999');
      final s = await job().run();
      expect(s.updated, 0);
      expect((await w.txns()).single['amount_minor'], 999);
    });
  });

  group('concurrency and races', () {
    test('two jobs at once convert once', () async {
      await ingestOld('a', purchase);
      final r = await Future.wait([job().run(), job().run()]);
      expect(r.fold<int>(0, (n, s) => n + s.converted), 1);
      expect(await w.count('transactions'), 1);
    });

    test(
      'live capture of the same text while the job runs: one transaction',
      () async {
        await ingestOld('a', purchase);
        await Future.wait([
          job().run(),
          w.run([sms('live', purchase)]),
        ]);
        expect(await w.count('transactions'), 1);
        expect(await w.count('raw_messages'), 1);
      },
    );

    test(
      'the user dismissed the item after the job read the row: skipped',
      () async {
        await ingestOld('a', purchase);
        final stale = (await DriftIngestStore(
          w.db,
        ).rawsToReparse(registryVersion: 2, afterId: '', limit: 10)).single;
        await w.db.customStatement(
          "UPDATE raw_messages SET parse_status = 'dismissed'",
        );
        final r = await w.useCase(registry: newReg).reparse(stale);
        expect(r.outcome, ReparseOutcome.skipped);
        expect(await w.count('transactions'), 0);
        expect((await w.raws()).single['parse_status'], 'dismissed');
      },
    );

    test('user-confirmed channels are never selected', () async {
      await w.useCase(registry: oldReg)([
        IncomingMessage(
          deliveryId: 'p',
          channel: 'paste',
          source: 'ZBANK',
          body: purchase,
          receivedAtMs: t0,
          origin: MessageOrigin.userConfirmed,
        ),
      ]);
      final s = await job().run();
      expect(s.examined, 0);
    });
  });

  group('failures and privacy', () {
    test('a throwing pairing hook is counted, the transaction stays', () async {
      await ingestOld('a', purchase);
      final s = await job(hookThrows: true).run();
      expect(s.hookFailures, 1);
      expect(await w.count('transactions'), 1);
    });

    test('no output carries the body', () async {
      final out = <String>[];
      await runZoned(
        () async {
          await w.useCase(registry: oldReg)([sms('a', 'ZBANK: new $canary')]);
          final s = await job().run();
          out.add(s.toString());
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => out.add(line),
        ),
      );
      expect(out.join(), isNot(contains(canary)));
      expect(w.diag.counts.keys.join(), isNot(contains(canary)));
    });
  });
}
