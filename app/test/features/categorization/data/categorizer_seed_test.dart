// T-075: the categorizer on the REAL bundled seed and an encrypted database.
// Acceptance criteria, the SM-04 accuracy report, the performance budget
// and determinism. All input is synthetic.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/catalog/catalog_seed_loader.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/catalog_dao.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
import 'package:zaghlol/features/categorization/domain/merchant_rule.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/financial_fixtures.dart';

class _AssetSource implements CatalogSeedSource {
  @override
  Future<Uint8List> readGzip() async =>
      File('assets/catalog/catalog_seed.json.gz').readAsBytesSync();
  @override
  Future<String> readSignature() async =>
      File('assets/catalog/catalog_seed.json.sig').readAsStringSync();
}

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late DriftRulesRepository rules;
  late Categorizer cat;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await CatalogSeedLoader(
      db: db,
      source: _AssetSource(),
      trustedKeys: bundledSeedKeys(),
      allowDevKeys: true,
      clock: () => DateTime.utc(2026, 11, 11),
    ).loadIfNeeded();
    rules = DriftRulesRepository(MerchantRulesDao(db), CategoriesDao(db));
    cat = Categorizer(driftCategorizerPorts(db, rules));
  });
  tearDown(() => edb.close());

  Future<CategoryDecision> run(String raw, {String? kind, String? value}) {
    final c = cleanMerchant(raw);
    return cat.categorize(
      categorizeInputFor(
        merchantRaw: raw,
        merchantNorm: c.key,
        counterpartyKind: kind,
        counterpartyValue: value,
      ),
    );
  }

  group('acceptance', () {
    test('ELEZABY / EL EZABY / صيدليات العزبي -> El Ezaby (health)', () async {
      for (final raw in ['ELEZABY', 'EL EZABY', 'صيدليات العزبي']) {
        final d = await run(raw);
        expect(d.categoryId, 'sys:health', reason: raw.hashCode.toString());
        expect(d.source, CategorySource.catalog);
        final m = await CatalogDao(db).merchantsByIds({d.catalogMerchantId!});
        expect(m.single.canonical, 'El Ezaby Pharmacy');
        // Not fuzzy: the Arabic and Latin spellings are aliases.
        expect(d.tier, isNot(CategorizeTier.fuzzy));
      }
    });

    test('P2P transfer without a rule needs classification', () async {
      for (final kind in ['ipa', 'phone', 'person']) {
        final d = await run('CARREFOUR', kind: kind, value: 'someone');
        expect(d.categoryId, isNull);
        expect(d.source, CategorySource.none);
      }
    });

    test('P2P with a counterparty rule is user_rule', () async {
      await rules.save(
        kind: RuleMatchKind.counterparty,
        value: 'mum@instapay',
        categoryId: 'sys:family_giving',
      );
      final d = await run('', kind: 'ipa', value: 'mum@instapay');
      expect(d.source, CategorySource.userRule);
      expect(d.categoryId, 'sys:family_giving');
    });

    test('rule on the catalog merchant beats its seeded category', () async {
      final m = (await CatalogDao(db).aliasesEqualTo('carrefour')).single;
      await rules.save(
        kind: RuleMatchKind.catalogMerchant,
        value: '${m.merchantId}',
        categoryId: 'sys:dining',
      );
      final d = await run('CARREFOUR MAADI EG 041');
      expect(d.categoryId, 'sys:dining');
      expect(d.source, CategorySource.userRule);
      expect(d.catalogMerchantId, m.merchantId);
    });

    test('an archived category is never assigned', () async {
      await db.customStatement(
        "UPDATE categories SET is_archived = 1 WHERE id = 'sys:groceries'",
      );
      final d = await run('CARREFOUR');
      expect(d.categoryId, isNull);
      expect(d.catalogMerchantId, isNotNull);
    });

    test('no raw merchant text in exceptions (sentinel)', () async {
      await db.close();
      try {
        await run('T075SENTINEL CARREFOUR');
        fail('expected a database failure');
      } catch (e) {
        expect(e.toString(), isNot(contains('T075SENTINEL')));
      }
      // tearDown closes again; reopen is not needed.
      edb = await EncryptedDb.open();
      db = edb.db;
    });
  });

  group('accuracy report (SM-04 >= 80%)', () {
    test('fixture merchants against the real seed', () async {
      final rows = (jsonDecode(
        File('test/fixtures/categorize/accuracy.json').readAsStringSync(),
      ) as List).cast<Map<String, dynamic>>();
      final tiers = <String, int>{};
      final byLevel = <String, List<int>>{};
      var ok = 0;
      final misses = <String>[];
      for (final r in rows) {
        final raw = r['merchant_raw'] as String;
        final d = await run(
          raw,
          kind: r['counterparty_kind'] as String?,
          value: r['counterparty_value'] as String?,
        );
        final expected = r['expected'] as String?;
        final got = d.categoryId?.replaceFirst('sys:', '');
        final good = got == expected;
        if (good) ok++;
        tiers[d.tier.name] = (tiers[d.tier.name] ?? 0) + 1;
        final l = byLevel.putIfAbsent(r['level'] as String, () => [0, 0]);
        l[1]++;
        if (good) l[0]++;
        if (!good) misses.add('${r['level']}#${rows.indexOf(r)}');
      }
      final rate = ok / rows.length;
      final hard = rows.where((r) => r['level'] == 'hard').length;
      // Counts only: no merchant text in test output.
      // ignore: avoid_print
      print(
        'T-075 accuracy: $ok/${rows.length} = '
        '${(rate * 100).toStringAsFixed(1)}%  hard cases: $hard '
        '(${(hard * 100 / rows.length).toStringAsFixed(0)}%)\n'
        '  tiers: $tiers\n'
        '  by level (right/total): $byLevel\n'
        '  misses: $misses',
      );
      expect(hard / rows.length, greaterThanOrEqualTo(0.2));
      expect(rate, greaterThanOrEqualTo(0.8));
      // Safety: nothing was assigned a category where none was expected
      // (precision of the confident tiers on negatives).
      for (final r in rows.where((r) => r['expected'] == null)) {
        final d = await run(
          r['merchant_raw'] as String,
          kind: r['counterparty_kind'] as String?,
          value: r['counterparty_value'] as String?,
        );
        expect(d.categoryId, isNull, reason: 'negative ${r['level']}');
      }
    });
  });

  group('performance and determinism', () {
    test('per-message time on the seed (host p95)', () async {
      final raws = [
        'CARREFOUR MAADI EG 041',
        'ELEZABY',
        'صيدليات العزبي',
        'CARREFOURR',
        'QWERTY PHARMACY',
        'XJQ 77 TRADING',
      ];
      for (final r in raws) {
        await run(r); // warm up
      }
      final times = <int>[];
      for (var i = 0; i < 120; i++) {
        final sw = Stopwatch()..start();
        await run(raws[i % raws.length]);
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      final p95 = times[(times.length * 0.95).floor()] / 1000;
      // ignore: avoid_print
      print('T-075 host p95 per message: ${p95.toStringAsFixed(2)} ms');
      // Design note: host p95 <= 5 ms; the assert leaves room for CI noise.
      expect(p95, lessThan(25));
    }, tags: 'benchmark');

    test('3000-alias synthetic catalog: fuzzy stays within budget', () async {
      final dao = CatalogDao(db);
      final base = 10000;
      await dao.upsertMerchants([
        for (var i = 0; i < 600; i++)
          CatalogMerchantsCompanion.insert(
            id: Value(base + i),
            canonical: 'Synthetic $i',
            categoryCode: 'shopping',
            version: 1,
          ),
      ]);
      String word(int n) {
        const l = 'bcdfghjklmnpqrstvwxz';
        return '${l[n % 20]}${'aeiou'[n % 5]}${l[(n ~/ 20) % 20]}'
            '${'aeiou'[(n ~/ 5) % 5]}${l[(n ~/ 400) % 20]}${n % 97}x';
      }

      await dao.upsertAliases([
        for (var i = 0; i < 3000; i++)
          (
            merchantId: base + i % 600,
            aliasNorm: '${word(i)} shop',
            match: 'prefix',
          ),
      ]);
      final times = <int>[];
      for (var i = 0; i < 60; i++) {
        final sw = Stopwatch()..start();
        await run('${word(i * 7)} shopp');
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();
      final p95 = times[(times.length * 0.95).floor()] / 1000;
      // ignore: avoid_print
      print('T-075 host p95 with 3600 aliases: ${p95.toStringAsFixed(2)} ms');
      expect(p95, lessThan(25));
    }, tags: 'benchmark');

    test('same input, same decision, repeated', () async {
      final first = await run('CARREFOURR MAADI');
      for (var i = 0; i < 20; i++) {
        expect(await run('CARREFOURR MAADI'), first);
      }
    });
  });
}
