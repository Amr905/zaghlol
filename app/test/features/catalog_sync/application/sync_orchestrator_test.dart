// T-143: the daily sync on an encrypted database with fake backend and anchor.
// Synthetic catalog and tokens only.

import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_failure.dart';
import 'package:zaghlol/core/backend/generated/api_models.g.dart';
import 'package:zaghlol/core/backend/ids.dart';
import 'package:zaghlol/core/db/app_database.dart' hide Settings;
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';
import 'package:zaghlol/core/flags/flags_service.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_adapters.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_orchestrator.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';

import '../../../core/backend/backend_test_support.dart';
import '../../../core/db/financial_fixtures.dart';
import '../../gold/application/entitlement_harness.dart';

const int hr = 3600000;
final int base = DateTime.utc(2026, 11, 13, 10).millisecondsSinceEpoch;

String isoZ(int ms) =>
    '${DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().substring(0, 19)}Z';

final class FakeBackend implements SyncBackend {
  final List<SyncRequest> requests = [];
  final List<String> nonces = [];
  final List<Object> script = []; // SyncResponse or Object to throw
  final Map<int, CatalogSnapshot> full = {};
  Object? fullError;
  int fullCalls = 0;
  Completer<void>? gate;

  @override
  Future<SyncResponse> sync(SyncRequest request, TimeNonce nonce) async {
    requests.add(request);
    nonces.add(nonce.value);
    await gate?.future;
    final next = script.removeAt(0);
    if (next is SyncResponse) return next;
    throw next;
  }

  @override
  Future<CatalogSnapshot> getFullCatalog(int version) async {
    fullCalls++;
    if (fullError != null) throw fullError!;
    return full[version]!;
  }
}

final class FakeAnchor implements SyncAnchor {
  final List<String> log = [];
  int? iat;
  int n = 0;

  @override
  Future<SyncResponse> run(
    Future<SyncResponse> Function(TimeNonce) request,
  ) async {
    final nonce = TimeNonce("${'N${n++}'.padRight(21, 'a')}A");
    log.add('nonce ${nonce.value}');
    final r = await request(nonce);
    log.add('handed');
    return r;
  }

  @override
  Future<int?> issuedAtMs() async => iat;
}

final class ThrowingFlagStore implements FlagSnapshotStore {
  @override
  Future<Uint8List?> read() async => null;
  @override
  Future<void> write(Uint8List bytes, {required int at}) =>
      throw StateError('disk');
}

SyncResponse effective({
  int serverAt = 0,
  CatalogDelta? catalog,
  FlagsBlock? flags,
  PricesBlock? prices,
}) => SyncResponse(
  serverTime: isoZ(serverAt),
  nextSyncNotBefore: isoZ(serverAt + 24 * hr),
  catalog: catalog,
  flags: flags,
  prices: prices,
  accepted: const AcceptedCounts(contributions: 0, bankRequests: 0),
);

SyncResponse throttled(int serverAt, int nextAt) =>
    SyncResponse(serverTime: isoZ(serverAt), nextSyncNotBefore: isoZ(nextAt));

MerchantOp merchant(int id, String name, {String cat = 'food'}) =>
    MerchantOp(op: OpKind.upsert, id: id, canonical: name, category: cat);

AliasOp alias(int id, String a) =>
    AliasOp(op: OpKind.upsert, merchantId: id, alias: a, match: 'exact');

CatalogDelta delta(int from, int to, List<CatalogOp> ops) => CatalogDelta(
  fromVersion: from,
  toVersion: to,
  mode: CatalogDeltaMode.delta,
  ops: ops,
);

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late FakeBackend backend;
  late FakeAnchor anchor;
  late FakeBackendStore store;
  late FlagsService flags;
  late SettingsRepository settings;
  late int clock;
  late int recats;

  SyncOrchestrator make({
    FlagsService? f,
    FakeBackendStore? s,
    SyncAnchor? a,
    Future<void> Function()? recat,
  }) => SyncOrchestrator(
    db: db,
    backend: backend,
    anchor: a ?? anchor,
    store: s ?? store,
    flags: f ?? flags,
    prices: PricesRepository(
      db: db,
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
    ),
    settings: settings,
    recategorize:
        recat ??
        () async {
          recats++;
        },
    now: () => clock,
  );

  Future<int> catalogVersion() async =>
      (await CatalogDao(db).meta())?.version ?? 0;

  Future<int> merchantCount() async =>
      (await db
              .customSelect('SELECT count(*) AS c FROM catalog_merchants')
              .getSingle())
          .read<int>('c');

  Future<void> queue(String id, {String kind = 'contribution'}) => OutboxDao(db)
      .enqueue(
        id: id,
        kind: kind,
        payload: kind == 'contribution'
            ? {
                'merchantNorm': 'koshary tahrir',
                'institutionCode': 'nbe',
                'categoryCode': 'food',
              }
            : {'institutionName': 'Bank X', 'country': 'EG', 'channel': 'sms'},
        createdAt: base,
      );

  Future<int> outboxCount() async =>
      (await db.customSelect('SELECT count(*) AS c FROM outbox').getSingle())
          .read<int>('c');

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    backend = FakeBackend();
    anchor = FakeAnchor();
    store = FakeBackendStore([]);
    clock = base;
    recats = 0;
    flags = FlagsService(
      store: SecureStateFlagStore(SecureStateDao(db)),
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
    );
    await flags.load();
    settings = SettingsRepository(SettingsDao(db));
    await CatalogDao(db).setMeta(version: 1, appliedAt: 1, signatureKid: 'k');
    await CatalogDao(db).upsertMerchant(
      CatalogMerchantsCompanion.insert(
        id: const Value(1),
        canonical: 'Old',
        categoryCode: 'food',
        version: 1,
      ),
    );
  });
  tearDown(() => edb.close());

  test('10 opens in a day make at most 1 successful sync', () async {
    final o = make();
    backend.script.add(effective(serverAt: clock));
    final kinds = <SyncOutcomeKind>[];
    for (var i = 0; i < 10; i++) {
      clock += hr ~/ 2;
      kinds.add((await o.run()).kind);
    }
    expect(backend.requests.length, 1);
    expect(kinds.first, SyncOutcomeKind.applied);
    expect(kinds.skip(1).every((k) => k == SyncOutcomeKind.notDue), isTrue);
    clock += 24 * hr;
    backend.script.add(effective(serverAt: clock));
    expect((await o.run()).kind, SyncOutcomeKind.applied);
    expect(backend.requests.length, 2);
  });

  test('R4-2: fresh nonce per request; answers (throttle too) are handed to '
      'the anchor', () async {
    final o = make();
    backend.script.add(throttled(clock, clock + 20 * hr));
    expect((await o.run()).kind, SyncOutcomeKind.throttled);
    expect(anchor.log.length, 2); // nonce, then handed (request ran between)
    expect(anchor.log.first, 'nonce ${backend.nonces.single}');
    expect(anchor.log.last, 'handed');

    clock += 21 * hr;
    backend.script.add(effective(serverAt: clock));
    await o.run();
    expect(backend.nonces.toSet().length, 2);
  });

  test('throttle answer applies nothing and keeps the outbox', () async {
    await settings.set(Settings.contributionOptIn, true);
    await queue('c1');
    final o = make();
    backend.script.add(throttled(clock, clock + 5 * hr));
    await o.run();
    expect(backend.requests.single.contributions!.length, 1);
    expect(await outboxCount(), 1);
    // The window the server named is respected.
    clock += 4 * hr;
    expect((await o.run()).kind, SyncOutcomeKind.notDue);
    clock += 2 * hr;
    backend.script.add(effective(serverAt: clock));
    await o.run();
    expect(await outboxCount(), 0);
  });

  test('delta applies in order and sets the version; sent rows deleted, '
      'later rows stay', () async {
    await settings.set(Settings.contributionOptIn, true);
    await queue('c1');
    await queue('b1', kind: 'bank_request');
    backend.script.add(
      effective(
        serverAt: clock,
        catalog: delta(1, 3, [merchant(2, 'New'), alias(2, 'new shop')]),
      ),
    );
    final out = await make().run();
    expect(out.kind, SyncOutcomeKind.applied);
    expect(out.catalogChanged, isTrue);
    expect(await catalogVersion(), 3);
    expect((await CatalogDao(db).aliasesEqualTo('new shop')).length, 1);
    expect(await outboxCount(), 0);
    expect(recats, 1);
    expect(backend.requests.single.catalogVersion, 1);
    expect(backend.requests.single.bankRequests!.single.country, 'EG');
  });

  test('opted out: no contributions are sent', () async {
    await queue('c1');
    backend.script.add(effective(serverAt: clock));
    await make().run();
    expect(backend.requests.single.contributions, isNull);
  });

  test('a malformed queued row is dropped, never sent', () async {
    await settings.set(Settings.contributionOptIn, true);
    await OutboxDao(db).enqueue(
      id: 'bad',
      kind: 'contribution',
      payload: {'merchantNorm': 'x', 'amount': '12'},
      createdAt: base,
    );
    backend.script.add(effective(serverAt: clock));
    await make().run();
    expect(backend.requests.single.contributions, isNull);
    expect(await outboxCount(), 0);
  });

  test('kill mid-apply (flags write fails): catalog, outbox, flags intact '
      'and a back-off starts', () async {
    await settings.set(Settings.contributionOptIn, true);
    await queue('c1');
    final broken = FlagsService(
      store: ThrowingFlagStore(),
      clock: () => DateTime.fromMillisecondsSinceEpoch(clock, isUtc: true),
    );
    backend.script.add(
      effective(
        serverAt: clock,
        catalog: delta(1, 2, [merchant(2, 'New')]),
        flags: const FlagsBlock(version: 3, values: {'zakah': true}),
      ),
    );
    final o = make(f: broken);
    final out = await o.run();
    expect(out.kind, SyncOutcomeKind.failed);
    expect(out.code, SyncException.applyFailed);
    expect(await catalogVersion(), 1);
    expect(await merchantCount(), 1);
    expect(await outboxCount(), 1);
    expect(recats, 0);
    // back-off: not before an hour
    clock += hr ~/ 2;
    expect((await o.run()).kind, SyncOutcomeKind.notDue);
    expect((await o.status()).failures, 1);
  });

  test('an invalid op rolls back the whole answer', () async {
    backend.script.add(
      effective(
        serverAt: clock,
        catalog: delta(1, 2, [
          merchant(2, 'New'),
          const MerchantOp(op: OpKind.upsert, id: 3), // no canonical
        ]),
      ),
    );
    final out = await make().run();
    expect(out.kind, SyncOutcomeKind.failed);
    expect(out.code, 'CATALOG_OP_INVALID');
    expect(await merchantCount(), 1);
    expect(await catalogVersion(), 1);
  });

  test(
    'back-off after a failure: one attempt an hour; Retry-After wins',
    () async {
      final o = make();
      backend.script.add(BackendFailure(BackendFailureKind.offline));
      expect((await o.run()).kind, SyncOutcomeKind.failed);
      clock += hr - 1;
      expect((await o.run()).kind, SyncOutcomeKind.notDue);
      clock += 2;
      backend.script.add(
        BackendFailure(
          BackendFailureKind.problem,
          httpStatus: 503,
          retryAfter: const Duration(hours: 5),
        ),
      );
      expect((await o.run()).kind, SyncOutcomeKind.failed);
      clock += 4 * hr;
      expect((await o.run()).kind, SyncOutcomeKind.notDue);
      clock += 2 * hr;
      backend.script.add(effective(serverAt: clock));
      expect((await o.run()).kind, SyncOutcomeKind.applied);
      expect((await o.status()).failures, 0);
    },
  );

  test('full mode downloads the snapshot and prunes what it no longer '
      'lists', () async {
    backend.full[5] = CatalogSnapshot(
      version: 5,
      ops: [merchant(7, 'Seven'), alias(7, 'seven')],
    );
    backend.script.add(
      effective(
        serverAt: clock,
        catalog: const CatalogDelta(
          fromVersion: 1,
          toVersion: 5,
          mode: CatalogDeltaMode.full,
        ),
      ),
    );
    final out = await make().run();
    expect(out.catalogChanged, isTrue);
    expect(backend.fullCalls, 1);
    expect(await catalogVersion(), 5);
    expect(await CatalogDao(db).merchantById(1), isNull);
    expect(await CatalogDao(db).merchantById(7), isNotNull);
  });

  test('a delta that does not start at our version is replaced by the '
      'snapshot', () async {
    backend.full[9] = CatalogSnapshot(version: 9, ops: [merchant(4, 'Four')]);
    backend.script.add(
      effective(serverAt: clock, catalog: delta(6, 9, [merchant(5, 'Five')])),
    );
    await make().run();
    expect(backend.fullCalls, 1);
    expect(await CatalogDao(db).merchantById(5), isNull);
    expect(await CatalogDao(db).merchantById(4), isNotNull);
  });

  test('snapshot download fails: other blocks apply, the next run fetches '
      'only the snapshot', () async {
    backend.fullError = BackendFailure(BackendFailureKind.offline);
    backend.full[5] = CatalogSnapshot(version: 5, ops: [merchant(7, 'Seven')]);
    backend.script.add(
      effective(
        serverAt: clock,
        flags: const FlagsBlock(version: 2, values: {'zakah': false}),
        catalog: const CatalogDelta(
          fromVersion: 1,
          toVersion: 5,
          mode: CatalogDeltaMode.full,
        ),
      ),
    );
    final o = make();
    final first = await o.run();
    expect(first.catalogChanged, isFalse);
    expect(await catalogVersion(), 1);
    expect(flags.current.version, 2);
    clock += hr + 1;
    backend.fullError = null;
    final second = await o.run();
    expect(second.catalogChanged, isTrue);
    expect(backend.requests.length, 1); // no second sync call
    expect(await catalogVersion(), 5);
  });

  test('snapshot of the wrong version is refused', () async {
    backend.full[5] = CatalogSnapshot(version: 4, ops: const []);
    backend.script.add(
      effective(
        serverAt: clock,
        catalog: const CatalogDelta(
          fromVersion: 1,
          toVersion: 5,
          mode: CatalogDeltaMode.full,
        ),
      ),
    );
    await make().run();
    expect(await catalogVersion(), 1);
  });

  test('flags and prices are stored with the answer', () async {
    backend.script.add(
      effective(
        serverAt: clock,
        flags: const FlagsBlock(version: 4, values: {'zakah': true}),
        prices: PricesBlock(
          asOf: isoZ(clock),
          stale: false,
          gold: const [
            GoldPrice(symbol: 'XAU24_G', currency: 'EGP', price: '4820.00'),
          ],
          fx: const FxBlock(base_: 'USD', rates: {'EGP': '48.9500'}),
        ),
      ),
    );
    await make().run();
    expect(flags.current.version, 4);
    expect(flags.isOn(FeatureFlag.zakah), isTrue);
    final next = backend;
    clock += 25 * hr;
    next.script.add(effective(serverAt: clock));
    await make().run();
    expect(backend.requests.last.flagsVersion, 4);
    expect(backend.requests.last.pricesAsOf, isNotNull);
  });

  test('two runners never sync at once (lease); the same instance shares '
      'one run', () async {
    backend.gate = Completer<void>();
    backend.script.add(effective(serverAt: clock));
    final a = make();
    final b = make(); // another engine on the same store
    final first = a.run();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await b.run(force: true)).kind, SyncOutcomeKind.alreadyRunning);
    expect(identical(a.run(), first), isTrue);
    backend.gate!.complete();
    expect((await first).kind, SyncOutcomeKind.applied);
    expect(backend.requests.length, 1);
  });

  test('R5-7: entitlementIssuedAt is the cached token iat', () async {
    final h = Harness();
    final iatMs = h.clock.wall - 3 * hr;
    await h.online(h.token(entClaims(iatMs: iatMs)), serverMs: h.clock.wall);
    backend.script.add(effective(serverAt: clock));
    final o = make(a: EntitlementSyncAnchor(h.service));
    await o.run();
    expect(backend.requests.single.entitlementIssuedAt, isoZ(iatMs));
  });

  test('no token: entitlementIssuedAt is omitted', () async {
    backend.script.add(effective(serverAt: clock));
    await make().run();
    expect(backend.requests.single.entitlementIssuedAt, isNull);
  });

  test(
    're-categorization never overrides a user or user-rule choice',
    () async {
      // The job a real wiring passes: T-075's guarded UPDATE.
      // (Behaviour of the guards themselves: recategorizer_test.dart.)
      backend.script.add(
        effective(serverAt: clock, catalog: delta(1, 2, [merchant(2, 'New')])),
      );
      var ran = false;
      await make(recat: () async => ran = true).run();
      expect(ran, isTrue);
      // A failing job does not fail the sync.
      clock += 25 * hr;
      backend.script.add(
        effective(serverAt: clock, catalog: delta(2, 3, [merchant(3, 'X')])),
      );
      final out = await make(recat: () async => throw StateError('x')).run();
      expect(out.kind, SyncOutcomeKind.applied);
      expect(await catalogVersion(), 3);
    },
  );
}
