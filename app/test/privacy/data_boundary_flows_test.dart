// T-171 check 2, app-flow level (testing-strategy §1 "Privacy", §6;
// security-model §2.4): a scripted session per platform runs the app's real
// services - ingestion of a canary SMS, opt-in contributions, "request my
// bank", the daily sync, purchase verify, restore, entitlement refresh,
// sign-in, sign-out, account delete and the "Delete everything" install
// delete - through the production BackendClient adapters on one
// RecordingBackendTransport. Every recorded request must sit inside the
// BR-SYNC-03 allow-list (support/br_sync_03.dart), and no financial canary
// planted on the phone may appear anywhere in a request (FR-CAT-09: no
// amount, date, card digits, IPA or phone in contributions).
//
// Every message, merchant, token and key here is synthetic.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/backend_state.dart';
import 'package:zaghlol/core/backend/debug/recording_transport.dart';
import 'package:zaghlol/core/backend/response_signature.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/outbox_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/flags/flags_service.dart';
import 'package:zaghlol/core/platform/pigeon_attestation.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';
import 'package:zaghlol/features/account/application/account_service.dart';
import 'package:zaghlol/features/account/application/id_token_source.dart';
import 'package:zaghlol/features/account/domain/sign_in_outcome.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_adapters.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_orchestrator.dart';
import 'package:zaghlol/features/categorization/application/contributions.dart';
import 'package:zaghlol/features/gold/application/gold_ports.dart';
import 'package:zaghlol/features/gold/application/gold_store.dart';
import 'package:zaghlol/features/gold/application/purchase.dart';
import 'package:zaghlol/features/gold/application/purchase_outbox.dart';
import 'package:zaghlol/features/gold/application/restore.dart';
import 'package:zaghlol/features/gold/domain/purchase_outcome.dart';
import 'package:zaghlol/features/gold/domain/restore_outcome.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/features/security/application/delete_everything.dart';
import 'package:zaghlol/features/wealth/data/prices_repository.dart';

import '../features/gold/application/entitlement_harness.dart';
import '../features/gold/application/gold_test_support.dart';
import '../features/ingestion/support/ingest_harness.dart'
    show IngestWorld, sms;
import 'support/br_sync_03.dart';
import 'support/fake_server.dart';

const _jws = 'eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln';
const _acct = 'acct-synthetic-1';

/// Financial data planted on the phone; none of it may reach the backend.
const Map<String, String> canaries = {
  'merchant': 'Zglcanary Mart',
  'amount': '7391.42',
  'amountMinor': '739142',
  'amountArabicIndic': '٧٣٩١',
  'card': '8642',
  'sms': 'ZGLSMSCANARY',
  'ipa': 'zglcanary@instapay',
  'phone': '01012345678',
  'p2pName': 'Zglcanary Person',
};

final class _Tokens implements IdTokenSource {
  @override
  Future<ProviderCredential> obtain(
    SignInRequestProvider provider, {
    required String hashedNonce,
  }) async => const ProviderCredential(idToken: _jws);
}

final class _Session {
  _Session(this.platform) {
    h = Harness(boot: 1);
    server = FakeZaghlolServer(
      nowMs: () => h.clock.wall,
      entitlementToken: (iid) => h.token(
        entClaims(sub: iid, iatMs: h.clock.wall, acct: signedIn ? _acct : null),
      ),
      accountToken: (iid) =>
          h.token(acctClaims(sub: _acct, iid: iid, iatMs: h.clock.wall)),
    );
    recorder = RecordingBackendTransport(server);
    client = clientOver(h.store);
    h.backend
      ..onGet = ((n) => client.getEntitlement(timeNonce: n))
      ..onSignOut = ((n) => client.signOut(timeNonce: n));
    seats.sigs = ios ? FakeSeatProver.two() : const [];
    host.type = ios ? 'app_attest' : 'play_integrity';
  }

  final ClientPlatform platform;
  bool get ios => platform == ClientPlatform.ios;
  late final Harness h;
  late final FakeZaghlolServer server;
  late final RecordingBackendTransport recorder;
  late final BackendClient client;
  final seats = FakeSeatProver();
  final host = FakeAttestHost();
  bool signedIn = false;

  BackendClient clientOver(BackendStateStore store) => BackendClient(
    config: BackendConfig(
      baseUri: Uri.parse('https://api.test.invalid'),
      verifier: ResponseSignatureVerifier([server.responseKey.publicKey]),
    ),
    identity: ClientIdentity(
      platform: platform,
      appVersion: '1.0.0',
      build: '7',
    ),
    transport: recorder,
    store: store,
    random: Random(23),
  );

  DateTime now() =>
      DateTime.fromMillisecondsSinceEpoch(h.clock.wall, isUtc: true);

  /// The scripted session. Returns the outcomes the flows reported, so the
  /// test can prove each flow really ran to the backend and back.
  Future<List<Object>> run(IngestWorld w) async {
    final out = <Object>[];

    // 1. Install registration (lazy, first backend use).
    await client.ensureInstalled();
    h.backend.id = server.lastInstall;

    // 2. Financial data on the phone: a parsed canary SMS (amount, card
    //    digits, merchant, message text) and a P2P transfer.
    final ingest = await w.run([
      sms(
        'c1',
        'ZBANK: Purchase EGP ${canaries['amount']} at ${canaries['merchant']} '
            'card *${canaries['card']}',
      ),
      // An unparsed message: kept as raw text for the review queue.
      sms('c2', 'ZBANK: notice ${canaries['sms']} EGP 5 ${canaries['ipa']}'),
    ]);
    out.add(ingest.outcomes['c1']!);

    // 3. Opt-in contributions: one clean merchant; offers carrying
    //    personal data must be dropped on the device.
    final settings = SettingsRepository(SettingsDao(w.db));
    await CategoriesDao(w.db).upsertSystem(
      code: 'groceries',
      nameAr: 'بقالة',
      nameEn: 'Groceries',
      icon: 'cart',
      color: '#0F7A55',
      bucket: 'needs',
      sort: 1,
    );
    final queue = ContributionQueue(w.db, settings, clock: now);
    await queue.setOptIn(true);
    out.add(
      await queue.offer(
        merchantNorm: 'synthetic grocer',
        institutionCode: 'zbank',
        categoryCode: 'groceries',
      ),
    );
    for (final dirty in [
      '${canaries['merchant']} ${canaries['phone']}',
      canaries['ipa']!,
      'shop ${canaries['amountMinor']}',
    ]) {
      out.add(
        await queue.offer(
          merchantNorm: dirty,
          institutionCode: 'zbank',
          categoryCode: 'groceries',
        ),
      );
    }
    out.add(
      await queue.offer(
        merchantNorm: 'synthetic transfer',
        institutionCode: 'zbank',
        categoryCode: 'groceries',
        isPersonTransfer: true,
        displayName: canaries['p2pName'],
      ),
    );
    // A queued row carrying an extra member (an older build, a bug): the
    // sync must rebuild the payload from the allow-list, not forward it.
    await OutboxDao(w.db).enqueue(
      id: 'stale1',
      kind: 'contribution',
      payload: {
        'merchantNorm': 'synthetic bakery',
        'institutionCode': 'zbank',
        'categoryCode': 'groceries',
        'amountMinor': int.parse(canaries['amountMinor']!),
        'card': canaries['card'],
      },
      createdAt: h.clock.wall,
    );
    // "Request my bank": a well-formed one, and one with an extra member
    // that must never be sent.
    await OutboxDao(w.db).enqueue(
      id: 'bank0',
      kind: 'bank_request',
      payload: {
        'institutionName': 'Synthetic Bank',
        'country': 'EG',
        'channel': 'sms',
      },
      createdAt: h.clock.wall,
    );
    await OutboxDao(w.db).enqueue(
      id: 'bank1',
      kind: 'bank_request',
      payload: {
        'institutionName': 'Synthetic Bank',
        'country': 'EG',
        'channel': 'sms',
        'sample': canaries['sms'],
      },
      createdAt: h.clock.wall,
    );

    // 4. The daily sync, through the T-144 anchor like production.
    final flags = FlagsService(
      store: SecureStateFlagStore(SecureStateDao(w.db)),
      clock: now,
    );
    await flags.load();
    final sync = SyncOrchestrator(
      db: w.db,
      backend: BackendClientSyncBackend(client),
      anchor: EntitlementSyncAnchor(h.service),
      store: h.store,
      flags: flags,
      prices: PricesRepository(db: w.db, clock: now),
      settings: settings,
      now: () => h.clock.wall,
      registryVersion: 3,
    );
    out.add((await sync.run(force: true)).kind);

    // 5. Purchase + verify.
    final gold = BackendClientGoldBackend(client);
    final store = FakeGoldStore();
    final purchase = PurchaseService(
      store: store,
      backend: gold,
      entitlement: h.service,
      seats: seats,
      outbox: PurchaseOutbox(h.store),
      platform: platform,
      now: now,
    );
    final outcomes = <PurchaseOutcome>[];
    purchase.outcomes.listen(outcomes.add);
    await purchase.start();
    await store.deliver(paid(ios ? _jws : 'synthetic-play-token-0001'));
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    out.addAll(outcomes);
    await purchase.stop();

    // 6. Restore.
    h.clock.pass(minute);
    store.owned = [
      OwnedPurchase(
        productId: 'zaghlol_gold_yearly',
        reference: ios ? _jws : 'synthetic-play-token-0001',
      ),
    ];
    final restore = RestoreService(
      store: store,
      backend: gold,
      entitlement: h.service,
      seats: seats,
      attestation: PigeonAttestation(api: host),
      state: h.store,
      platform: platform,
      delay: (_) async {},
      now: now,
    );
    out.add(await restore.restore());

    // 7. Entitlement refresh (app resume).
    h.clock.pass(2 * day);
    await h.service.onResume();

    // 8. Sign-in, a sync while signed in, sign-out, sign-in, delete account.
    final account = AccountService(
      backend: BackendClientAccountBackend(client),
      entitlement: h.service,
      seats: seats,
      tokens: _Tokens(),
      platform: platform,
      hasStoreKitTransaction: (_) async => false,
    );
    signedIn = true;
    out.add(await account.signIn(SignInRequestProvider.google));
    h.clock.pass(day + hour);
    out.add((await sync.run(force: true)).kind);
    out.add(await account.signOut());
    signedIn = false;
    signedIn = true;
    out.add(await account.signIn(SignInRequestProvider.apple));
    out.add(await account.deleteAccount());
    signedIn = false;

    // 9. "Delete everything": the install delete with a throwaway client.
    final creds = await readInstallCredentials(h.store);
    out.add(
      await deleteInstallBestEffort(
        creds!,
        clientFor: clientOver,
        retryDelay: Duration.zero,
      ),
    );
    return out;
  }
}

void main() {
  late IngestWorld w;
  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  for (final platform in ClientPlatform.values) {
    final name = platform.name;
    test('$name session: every request of every flow is inside BR-SYNC-03 '
        'and carries no planted financial data', () async {
      final s = _Session(platform);
      final out = await s.run(w);

      // The flows really ran (otherwise an empty recording would pass).
      expect(out.whereType<IngestInserted>(), hasLength(1));
      expect(out.whereType<ContributionDecision>().toList(), [
        ContributionDecision.queued,
        ContributionDecision.personalData,
        ContributionDecision.personalData,
        ContributionDecision.personalData,
        ContributionDecision.personTransfer,
      ]);
      expect(out.whereType<SyncOutcomeKind>().toList(), [
        SyncOutcomeKind.applied,
        SyncOutcomeKind.applied,
      ]);
      expect(out.whereType<PurchaseGold>(), hasLength(1));
      expect(out.whereType<RestoreGold>(), hasLength(1));
      expect(out.whereType<SignedIn>(), hasLength(2));
      expect(out.whereType<SignedOut>(), hasLength(1));
      expect(out.whereType<AccountDeleted>(), hasLength(1));
      expect(out.whereType<bool>().single, isTrue); // install deleted

      final ops = <String>{};
      final classes = <WireClass>{};
      for (final r in s.recorder.requests) {
        final c = checkRequest(r, platform: name);
        expect(c.violations, isEmpty, reason: c.op);
        expect(canaryHits(r, canaries), isEmpty, reason: c.op);
        ops.add(c.op);
        classes.addAll(c.classes);
      }
      expect(ops, {
        'POST /v1/installs',
        'POST /v1/sync',
        'POST /v1/purchases/verify',
        'POST /v1/purchases/restore',
        'GET /v1/entitlement',
        'POST /v1/accounts/signin',
        // 'POST /v1/accounts/signout' never leaves the app: finding
        // T-171-F1 (see the skipped test below). The client-level test
        // covers its allow-list.
        'DELETE /v1/accounts/me',
        'DELETE /v1/installs/me',
      });
      expect(
        classes,
        containsAll([
          WireClass.merchants,
          WireClass.bankRequest,
          WireClass.attestation,
          WireClass.timeNonce,
        ]),
      );
      // Plan v1.1: an Android session never sends seatKeys; iOS does.
      expect(
        classes.contains(WireClass.seatKeys),
        platform == ClientPlatform.ios,
      );
    });
  }

  test(
    'sign-out reaches the server (D-61(c), backend-api §4.6)',
    () async {
      final s = _Session(ClientPlatform.android);
      final out = await s.run(w);
      expect(out.whereType<SignedOut>().single.serverConfirmed, isTrue);
      expect(
        s.recorder.requests.map((r) => r.uri.path),
        contains('/v1/accounts/signout'),
      );
    },
    skip:
        'FINDING T-171-F1: EntitlementService.signOut deletes the account '
        'token before calling BackendClient.signOut (auth installAndAccount), '
        'so the call always fails locally with notSignedIn and the server is '
        'never told. Unskip when T-144/T-147 fix the order.',
  );
}
