// T-337: remote config parsing, storage, staleness. Synthetic data only.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/config/remote_config.dart';
import 'package:zaghlol/core/config/remote_config_service.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/settings_dao.dart';
import 'package:zaghlol/core/flags/feature_flags.dart';

void main() {
  group('RemoteConfig.fromValues', () {
    test('empty map gives the defaults', () {
      final c = RemoteConfig.fromValues({});
      expect(c.askQuotaFree, 5);
      expect(c.askQuotaGold, 50);
      expect(c.catQuotaFree, 15);
      expect(c.catQuotaGold, 150);
      expect(c.investMinEgpMinor, 10000);
      expect(c.investGoldMinCentigrams, 25);
      expect(c.investGoldKarat, 21);
    });

    test('valid values are typed', () {
      final c = RemoteConfig.fromValues({
        'ask.quota_free': '7',
        'cat.batch_max': '10',
        'ask.invest_min_egp': '200.50',
        'ask.invest_gold_karat': '24',
        'llm.provider': 'p1',
        'unknown.key': 'x',
      });
      expect(c.askQuotaFree, 7);
      expect(c.catBatchMax, 10);
      expect(c.investMinEgpMinor, 20050);
      expect(c.investGoldKarat, 24);
      expect(c.llmProvider, 'p1');
    });

    test('bad or out-of-range values fall back per key', () {
      final c = RemoteConfig.fromValues({
        'ask.quota_free': '-1',
        'ask.quota_gold': 'abc',
        'cat.quota_free': '99999',
        'cat.batch_max': '0',
        'cat.min_confidence': '101',
        'ask.invest_min_egp': '1e3',
        'ask.invest_gold_min_cg': '٢٥',
        'ask.invest_gold_karat': '20',
        'ask.cd_example_rate_bp': '1.5',
        'llm.provider': 'Bad Id!',
      });
      expect(c.askQuotaFree, 5);
      expect(c.askQuotaGold, 50);
      expect(c.catQuotaFree, 15);
      expect(c.catBatchMax, 20);
      expect(c.catMinConfidence, 60);
      expect(c.investMinEgpMinor, 10000);
      expect(c.investGoldMinCentigrams, 25);
      expect(c.investGoldKarat, 21);
      expect(c.cdExampleRateBp, 2000);
      expect(c.llmProvider, '');
    });
  });

  group('RemoteConfigService', () {
    var now = DateTime.utc(2026, 11, 26);
    late AppDatabase db;
    late RemoteConfigService s;

    RemoteConfigService make() =>
        RemoteConfigService(dao: SecureStateDao(db), clock: () => now);

    setUp(() async {
      now = DateTime.utc(2026, 11, 26);
      db = AppDatabase(NativeDatabase.memory());
      s = make();
      await s.load();
    });
    tearDown(() => db.close());

    test('valid block stored, exposed, survives reload', () async {
      final ok = await s.apply(
        version: 3,
        values: {'ask.quota_free': '9'},
        providerName: {'ar': 'س', 'en': 'P'},
      );
      expect(ok, isTrue);
      expect(s.current.askQuotaFree, 9);
      expect(s.version, 3);
      final s2 = make();
      await s2.load();
      expect(s2.current.askQuotaFree, 9);
      expect(s2.current.providerName.en, 'P');
    });

    test('bad shape or older version keeps the previous values', () async {
      await s.apply(version: 3, values: {'ask.quota_free': '9'});
      expect(await s.apply(version: 'x', values: {}), isFalse);
      expect(await s.apply(version: 4, values: {'a': 1}), isFalse);
      expect(
        await s.apply(version: 2, values: {'ask.quota_free': '1'}),
        isFalse,
      );
      expect(s.current.askQuotaFree, 9);
      expect(s.version, 3);
    });

    test('stale after 14 days reads defaults', () async {
      await s.apply(version: 3, values: {'ask.quota_free': '9'});
      now = now.add(const Duration(days: 14));
      expect(s.current.askQuotaFree, 5);
    });

    test('resetCursor: version reads 0 until a block applies; values stay; '
        'the same version is then taken again (FU-425)', () async {
      await s.apply(
        version: 3,
        values: {'llm.provider': 'prov-a'},
        providerName: {'ar': 'أ', 'en': 'A'},
      );
      s.resetCursor();
      expect(s.version, 0);
      expect(s.current.llmProvider, 'prov-a');
      await s.confirm(3);
      expect(
        await s.apply(
          version: 3,
          values: {'llm.provider': 'prov-b'},
          providerName: {'ar': 'ب', 'en': 'B'},
        ),
        isTrue,
      );
      expect(s.version, 3);
      expect(s.current.llmProvider, 'prov-b');
      expect(s.current.providerName.en, 'B');
      // Back to normal: an equal version is ignored again.
      expect(
        await s.apply(version: 3, values: {'llm.provider': 'x1'}),
        isFalse,
      );
    });

    test('provider names go stale with the block (no id, no names)', () async {
      await s.apply(
        version: 3,
        values: {'llm.provider': 'prov-a'},
        providerName: {'ar': 'أ', 'en': 'A'},
      );
      now = now.add(const Duration(days: 15));
      expect(s.current.llmProvider, '');
      expect(s.current.providerName.en, '');
    });

    test('confirm() keeps a held version fresh past 14 days', () async {
      await s.apply(version: 3, values: {'ask.quota_free': '9'});
      now = now.add(const Duration(days: 10));
      await s.confirm(3);
      now = now.add(const Duration(days: 10));
      expect(s.current.askQuotaFree, 9);
      final s2 = make();
      await s2.load();
      expect(s2.current.askQuotaFree, 9);
      now = now.add(const Duration(days: 5));
      expect(s.current.askQuotaFree, 5);
    });

    test('confirm() of another version or with none held is ignored', () async {
      await s.confirm(3);
      expect(s.version, 0);
      await s.apply(version: 3, values: {'ask.quota_free': '9'});
      now = now.add(const Duration(days: 10));
      await s.confirm(2);
      now = now.add(const Duration(days: 5));
      expect(s.current.askQuotaFree, 5);
    });

    test('never synced reads defaults and version 0', () {
      expect(s.current, same(RemoteConfig.defaults));
      expect(s.version, 0);
    });
  });

  test('Delete everything: the config dies with the database file', () async {
    final dir = await Directory.systemTemp.createTemp('zcfg');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/z.db');
    var db = AppDatabase(NativeDatabase(file));
    final s = RemoteConfigService(
      dao: SecureStateDao(db),
      clock: () => DateTime.utc(2026, 11, 26),
    );
    await s.apply(version: 3, values: {'ask.quota_free': '9'});
    await db.close();
    await file.delete(); // what the wipe does to the database files
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final s2 = RemoteConfigService(
      dao: SecureStateDao(db),
      clock: () => DateTime.utc(2026, 11, 26),
    );
    await s2.load();
    expect(s2.version, 0);
    expect(s2.current, same(RemoteConfig.defaults));
  });

  test('FU-414: s1 / s4 thresholds are parsed, range-checked, defaulted', () {
    const d = RemoteConfig.defaults;
    expect([d.s1Pct, d.s4SharePct, d.s4SavingPct], [15, 20, 25]);
    final ok = RemoteConfig.fromValues({
      'ask.s1_pct': '40',
      'ask.s4_share_pct': '30',
      'ask.s4_saving_pct': '50',
    });
    expect([ok.s1Pct, ok.s4SharePct, ok.s4SavingPct], [40, 30, 50]);
    final bad = RemoteConfig.fromValues({
      'ask.s1_pct': '0',
      'ask.s4_share_pct': '101',
      'ask.s4_saving_pct': 'x',
    });
    expect([bad.s1Pct, bad.s4SharePct, bad.s4SavingPct], [15, 20, 25]);
  });

  test('the three LLM flags exist and are unknown-safe', () {
    expect(FeatureFlag.fromKey('ask_llm'), FeatureFlag.askLlm);
    expect(FeatureFlag.fromKey('ask_llm_invest'), FeatureFlag.askLlmInvest);
    expect(FeatureFlag.fromKey('llm_categorise'), FeatureFlag.llmCategorise);
    final off = FeatureFlagsState.neverSynced;
    expect(
      [
        FeatureFlag.askLlm,
        FeatureFlag.askLlmInvest,
        FeatureFlag.llmCategorise,
      ].any(off.isOn),
      isFalse,
    );
  });
}
