// SMS-improve: auto-categorization on the REAL bundled seed. Table-driven:
// merchant text as SMS carry it -> expected system category. Synthetic input.

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

const Map<String, List<String>> _cases = {
  'subscriptions': [
    'ANTHROPIC SAN FRANCISCO US',
    'CLAUDE.AI SUBSCRIPTION',
    'UDEMY ONLINE',
    'NETFLIX.COM',
    'SPOTIFY P1234',
    'OPENAI *CHATGPT SUBSCR',
    'DISNEY PLUS',
    'GITHUB INC',
    'ADOBE SYSTEMS',
    'CANVA PTY',
  ],
  'dining': ['TALABAT', 'TALABAT EGYPT CAIRO EG', 'MCDONALDS MAADI EG 12'],
  'groceries': ['BREADFAST', 'INSTASHOP', 'CARREFOUR MAADI EG 041'],
  'bills': [
    'VODAFONE EGYPT',
    'ORANGE EGYPT',
    'ETISALAT MISR',
    'WE EGYPT',
    'TELECOM EGYPT RECHARGE',
    'ELECTRICITY BILL',
  ],
  'transport': [
    'MISR PETROLEUM',
    'WATANEYA PETROL',
    'SHELL STATION 22',
    'FUEL STATION EL TAGAMOA',
    'UBER TRIP',
  ],
};

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

  Future<CategoryDecision> run(String raw) {
    final c = cleanMerchant(raw);
    return cat.categorize(
      categorizeInputFor(merchantRaw: raw, merchantNorm: c.key),
    );
  }

  for (final e in _cases.entries) {
    group('auto category ${e.key}', () {
      for (final raw in e.value) {
        test(raw, () async {
          final d = await run(raw);
          expect(d.categoryId, 'sys:${e.key}');
          expect(d.source, isNot(CategorySource.none));
        });
      }
    });
  }

  test('a user rule still beats the seeded category', () async {
    await rules.save(
      kind: RuleMatchKind.counterparty,
      value: 'netflix-shared',
      categoryId: 'sys:family_giving',
    );
    final d = await cat.categorize(
      categorizeInputFor(
        merchantRaw: 'NETFLIX.COM',
        merchantNorm: cleanMerchant('NETFLIX.COM').key,
        counterpartyKind: 'name',
        counterpartyValue: 'netflix-shared',
      ),
    );
    expect(d.source, CategorySource.userRule);
  });
}
