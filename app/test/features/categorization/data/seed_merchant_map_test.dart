// T-059: the seeded Egyptian merchant map on the REAL bundled seed. Counts,
// alias uniqueness and 30 synthetic merchant strings as they appear on
// card/wallet SMS. No real SMS text; the strings are brand names only.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/catalog/catalog_seed_loader.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/categories_dao.dart';
import 'package:zaghlol/core/db/daos/merchant_rules_dao.dart'
    show MerchantRulesDao;
import 'package:zaghlol/features/categorization/data/categorizer_ports.dart';
import 'package:zaghlol/features/categorization/data/rules_repository.dart';
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

/// Raw merchant string -> expected category code.
const Map<String, String> samples = {
  'CARREFOUR MAADI EG 041': 'groceries',
  'SPINNEYS NEW CAIRO': 'groceries',
  'SEOUDI MARKET': 'groceries',
  'KHEIR ZAMAN MAADI': 'groceries',
  'METRO MARKETS HELIOPOLIS': 'groceries',
  'TALABAT*ORDER': 'dining',
  'ELMENUS': 'dining',
  'MCDONALDS NASR CITY': 'dining',
  'COOK DOOR 6 OCT': 'dining',
  'PIZZA HUT EGYPT': 'dining',
  'CHILI S EG': 'dining',
  'UBER TRIP CAIRO': 'transport',
  'CAREEM RIDE': 'transport',
  'CHILLOUT MAADI': 'transport',
  'WATANIYA 123': 'transport',
  'TOTALENERGIES EG': 'transport',
  'VODAFONE EG': 'bills',
  'ORANGE EGYPT': 'bills',
  'FAWRY PAY': 'bills',
  'NORTH CAIRO ELECTRICITY': 'bills',
  'NETFLIX.COM': 'subscriptions',
  'SPOTIFY AB': 'subscriptions',
  'EL EZABY PHARMACY 17': 'health',
  'SEIF PHARMACIES': 'health',
  'VEZEETA.COM': 'health',
  'DEFACTO CFC': 'shopping',
  'B.TECH SHOP': 'shopping',
  'DECATHLON EGYPT': 'shopping',
  'VALU EG': 'debt',
  'VOX CINEMA CITY STARS': 'entertainment',
};

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late Categorizer cat;

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await CatalogSeedLoader(
      db: db,
      source: _AssetSource(),
      trustedKeys: bundledSeedKeys(),
      allowDevKeys: true,
      clock: () => DateTime.utc(2026, 11, 18),
    ).loadIfNeeded();
    cat = Categorizer(
      driftCategorizerPorts(
        db,
        DriftRulesRepository(MerchantRulesDao(db), CategoriesDao(db)),
      ),
    );
  });
  tearDown(() => edb.close());

  Map<String, Object?> seedJson() {
    final bytes = gzip.decode(
      File('assets/catalog/catalog_seed.json.gz').readAsBytesSync(),
    );
    return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  }

  test('the seed holds at least 600 merchants, each with an alias', () {
    final ops = (seedJson()['ops']! as List).cast<Map<String, Object?>>();
    final merchants = ops.where((o) => o['t'] == 'merchant').toList();
    expect(merchants.length, greaterThanOrEqualTo(600));
    final withAlias = {
      for (final o in ops.where((o) => o['t'] == 'alias')) o['merchantId'],
    };
    for (final m in merchants) {
      expect(withAlias, contains(m['id']), reason: '${m['canonical']}');
    }
  });

  test('no alias belongs to two merchants (so to two categories)', () {
    final ops = (seedJson()['ops']! as List).cast<Map<String, Object?>>();
    final owner = <String, Object?>{};
    for (final o in ops.where((o) => o['t'] == 'alias')) {
      final key = o['alias']! as String;
      final prev = owner[key];
      expect(
        prev == null || prev == o['merchantId'],
        isTrue,
        reason: 'alias "$key" owned by merchants $prev and ${o['merchantId']}',
      );
      owner[key] = o['merchantId'];
    }
  });

  for (final e in samples.entries) {
    test('"${e.key}" -> ${e.value}', () async {
      final c = cleanMerchant(e.key);
      final d = await cat.categorize(
        categorizeInputFor(merchantRaw: e.key, merchantNorm: c.key),
      );
      expect(d.categoryId, 'sys:${e.value}');
      expect(d.source, CategorySource.catalog);
    });
  }
}
