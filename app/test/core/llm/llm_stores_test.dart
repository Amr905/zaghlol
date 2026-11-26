// T-340 AC5: consent and quota stores on the encrypted database; provider or
// version change → needsConsent; unknown quota before first contact, after
// `resetsAt` and on bad text; "Delete everything" (the DB goes) leaves none.
// Synthetic data.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/llm/llm_gateway_client.dart'
    show llmConsentStoreProvider;
import 'package:zaghlol/core/backend/backend_client.dart' show LlmQuota;
import 'package:zaghlol/core/db/daos/llm_cat_queue_dao.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/llm/llm_consent.dart';
import 'package:zaghlol/core/llm/llm_feature.dart';
import 'package:zaghlol/core/llm/llm_quota_snapshot.dart';
import 'package:zaghlol/core/settings/settings_repository.dart';

import '../db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late SettingsDao dao;
  late SettingsRepository repo;
  late LlmConsentStore consent;
  late LlmQuotaStore quota;

  setUp(() async {
    edb = await EncryptedDb.open();
    dao = SettingsDao(edb.db);
    repo = SettingsRepository(dao, nowMs: () => 1000);
    consent = LlmConsentStore(repo, nowMs: () => 1793527200000);
    quota = LlmQuotaStore(repo);
  });

  tearDown(() => edb.close());

  test('key names are the documented ones (ask-llm §6, llm-categorise §7)', () {
    expect(LlmConsentSettings.ask.name, 'ask.llm_consent');
    expect(LlmConsentSettings.categorise.name, 'cat.llm_consent');
    expect(LlmQuotaSettings.askQuota.name, 'ask.llm_quota');
    expect(LlmQuotaSettings.catQuota.name, 'cat.llm_quota');
    expect(LlmQuotaSettings.askPaused.name, 'ask.llm_paused_until_sync');
    expect(LlmQuotaSettings.catPaused.name, 'cat.llm_paused_until_sync');
  });

  group('consent', () {
    test('the real provider: clearing categorise consent empties the queue; '
        'ask leaves it', () async {
      final q = LlmCatQueueDao(edb.db);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => edb.db)],
      );
      addTearDown(container.dispose);
      final c = await container.read(llmConsentStoreProvider.future);
      await q.enqueue('synthetic merchant', at: 1);
      await c.clear(LlmFeature.ask);
      expect(await q.count(), 1);
      await c.clear(LlmFeature.categorise);
      expect(await q.count(), 0);
    });

    test('none stored → needsConsent; grant → covered; provider or v change '
        '→ needsConsent again', () async {
      for (final f in LlmFeature.values) {
        expect(await consent.needsConsent(f, 'openai-luna', 1), isTrue);
      }
      final g = await consent.grant(LlmFeature.ask, 'openai-luna', 1);
      expect(g.atMs, 1793527200000);
      expect(
        await consent.needsConsent(LlmFeature.ask, 'openai-luna', 1),
        isFalse,
      );
      expect(
        await consent.needsConsent(LlmFeature.ask, 'gemini-flash-lite', 1),
        isTrue,
      );
      expect(
        await consent.needsConsent(LlmFeature.ask, 'openai-luna', 2),
        isTrue,
      );
      // Features are independent.
      expect(
        await consent.needsConsent(LlmFeature.categorise, 'openai-luna', 1),
        isTrue,
      );
      expect(
        await dao.read('ask.llm_consent'),
        '{"provider":"openai-luna","v":1,"at":1793527200000}',
      );
    });

    test('fail closed: empty or malformed active provider, v < 1, unreadable '
        'stored text', () async {
      await consent.grant(LlmFeature.ask, 'openai-luna', 1);
      expect(await consent.needsConsent(LlmFeature.ask, '', 1), isTrue);
      expect(
        await consent.needsConsent(LlmFeature.ask, 'Openai Luna', 1),
        isTrue,
      );
      expect(
        await consent.needsConsent(LlmFeature.ask, 'openai-luna', 0),
        isTrue,
      );
      await expectLater(
        consent.grant(LlmFeature.ask, 'bad provider', 1),
        throwsArgumentError,
      );
      for (final bad in [
        'nope',
        '{"provider":"openai-luna","v":1}',
        '{"provider":"openai-luna","v":"1","at":1}',
        '{"provider":"openai-luna","v":1,"at":1,"x":1}',
      ]) {
        await dao.write('ask.llm_consent', bad, at: 1);
        expect(
          await consent.needsConsent(LlmFeature.ask, 'openai-luna', 1),
          isTrue,
          reason: bad,
        );
      }
    });

    test('clear (switch off / 409) removes it', () async {
      await consent.grant(LlmFeature.categorise, 'openai-luna', 1);
      await consent.clear(LlmFeature.categorise);
      expect(await consent.read(LlmFeature.categorise), isNull);
      expect(await dao.read('cat.llm_consent'), isNull);
    });
  });

  group('quota snapshot', () {
    final before = DateTime.utc(2026, 11, 30, 21, 59);
    final at = DateTime.utc(2026, 11, 30, 22);
    const q = LlmQuota(
      limit: 5,
      used: 5,
      remaining: 0,
      resetsAt: '2026-11-30T22:00:00Z',
    );

    test('unknown before first contact; exhausted at 0 before resetsAt; '
        'unknown again at resetsAt', () async {
      expect(await quota.current(LlmFeature.ask, before), isNull);
      expect(await quota.exhausted(LlmFeature.ask, before), isFalse);
      await quota.record(LlmFeature.ask, q);
      final s = await quota.current(LlmFeature.ask, before);
      expect(s, LlmQuotaSnapshot(limit: 5, remaining: 0, resetsAt: at));
      expect(await quota.exhausted(LlmFeature.ask, before), isTrue);
      expect(await quota.exhausted(LlmFeature.categorise, before), isFalse);
      expect(await quota.current(LlmFeature.ask, at), isNull);
      expect(await quota.exhausted(LlmFeature.ask, at), isFalse);
    });

    test('a non-UTC or malformed quota is not stored; bad stored text reads '
        'unknown', () async {
      await quota.record(
        LlmFeature.ask,
        const LlmQuota(
          limit: 5,
          used: 1,
          remaining: 4,
          resetsAt: '2026-11-30T22:00:00Z',
        ),
      );
      await quota.record(
        LlmFeature.ask,
        const LlmQuota(
          limit: 5,
          used: 5,
          remaining: 0,
          resetsAt: '2026-11-30T22:00:00',
        ),
      );
      expect((await quota.current(LlmFeature.ask, before))!.remaining, 4);
      await dao.write('ask.llm_quota', '{"limit":5}', at: 1);
      expect(await quota.current(LlmFeature.ask, before), isNull);
    });

    test('pause until sync per feature; resumeAll and clear', () async {
      await quota.pause(LlmFeature.ask);
      expect(await quota.isPaused(LlmFeature.ask), isTrue);
      expect(await quota.isPaused(LlmFeature.categorise), isFalse);
      await quota.resumeAll();
      expect(await quota.isPaused(LlmFeature.ask), isFalse);
      await quota.record(LlmFeature.categorise, q);
      await quota.pause(LlmFeature.categorise);
      await quota.clear(LlmFeature.categorise);
      expect(await dao.read('cat.llm_quota'), isNull);
      expect(await dao.read('cat.llm_paused_until_sync'), isNull);
    });
  });

  test('stored only in the encrypted database: after "Delete everything" '
      '(the DB files go) a fresh database holds none of the keys', () async {
    await consent.grant(LlmFeature.ask, 'openai-luna', 1);
    await consent.grant(LlmFeature.categorise, 'openai-luna', 1);
    await quota.record(
      LlmFeature.ask,
      const LlmQuota(
        limit: 5,
        used: 1,
        remaining: 4,
        resetsAt: '2026-11-30T22:00:00Z',
      ),
    );
    await quota.pause(LlmFeature.ask);
    for (final k in [
      'ask.llm_consent',
      'cat.llm_consent',
      'ask.llm_quota',
      'ask.llm_paused_until_sync',
    ]) {
      expect(await dao.read(k), isNotNull, reason: k);
    }
    // The wipe deletes the database files (T-166); a new world is empty.
    await edb.close();
    edb = await EncryptedDb.open();
    final fresh = SettingsDao(edb.db);
    for (final k in [
      'ask.llm_consent',
      'cat.llm_consent',
      'ask.llm_quota',
      'ask.llm_paused_until_sync',
    ]) {
      expect(await fresh.read(k), isNull, reason: k);
    }
  });
}
