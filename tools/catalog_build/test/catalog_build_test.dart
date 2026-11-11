// T-030: catalog_build tests. All catalog text is the curated brand list;
// no SMS, no user data.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:catalog_build/catalog_build.dart';
import 'package:test/test.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

const String header =
    'entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight';

const String cat =
    'category,groceries,بقالة,Groceries,cart,#174C4F,needs,1,,,,,,,';

String csvOf(List<String> lines) => '$header\n${lines.join('\n')}\n';

BuiltCatalog build(List<String> lines, {int version = 1}) =>
    buildCatalog(csvOf([cat, ...lines]), version: version);

Set<String> aliasKeys(BuiltCatalog b) => {
  for (final a in b.seed.aliases) a.alias,
};

void main() {
  group('alias keys use the parser rule (FU-062)', () {
    final vectors =
        (jsonDecode(
              File(
                '../../packages/zaghlol_parsing/test/fixtures/'
                'merchant_key_vectors.json',
              ).readAsStringSync(),
            ) as Map<String, Object?>)['vectors']!
            as List<Object?>;

    test('the vector file is the one the parsing package pins', () {
      expect(vectors.length, greaterThan(30));
    });

    for (final v in vectors.cast<Map<String, Object?>>()) {
      final input = v['input']! as String;
      final key = v['key']! as String;
      test('"$input" -> "$key"', () {
        // Quote the input: vector inputs contain commas, quotes and symbols.
        final cell = '"${input.replaceAll('"', '""')}"';
        final line = 'alias,,,,,,,,Zzz Brand,,$cell,exact,,,';
        final merchant = 'merchant,,بيت,,,,,,Zzz Brand,groceries,,exact,,,';
        if (key.length < minAliasKeyLength) {
          // Empty or one-character keys are refused, never stored.
          expect(
            () => build([merchant, line]),
            throwsA(isA<CatalogBuildException>()),
          );
        } else {
          final keys = aliasKeys(build([merchant, line]));
          expect(keys, contains(key));
        }
      });
    }
  });

  group('alias variants (FU-066)', () {
    test('a spaced article gets its attached spelling too', () {
      final b = build(['merchant,,المراعي,,,,,,Al Marai,groceries,,exact,,,']);
      expect(aliasKeys(b), containsAll(['marai', 'almarai']));
    });

    test('only the first two tokens are joined', () {
      expect(aliasVariants('AL RAWSHA MALL'), [
        'AL RAWSHA MALL',
        'ALRAWSHA MALL',
      ]);
      expect(aliasVariants('EL-X'), ['EL-X']);
      expect(aliasVariants('ELITE'), ['ELITE']);
      expect(aliasVariants('Carrefour Maadi'), ['Carrefour Maadi']);
    });

    test('the attached form is not guessed back into a spaced one', () {
      final b = build(['merchant,,نخبة,,,,,,Elite,groceries,,exact,,,']);
      expect(aliasKeys(b), {'elite'});
    });
  });

  group('rules', () {
    test('two merchants may not share an alias key', () {
      expect(
        () => build([
          'merchant,,أ,,,,,,Alpha,groceries,,exact,,,',
          'merchant,,ب,,,,,,Beta,groceries,,exact,,,',
          'alias,,,,,,,,Beta,,ALPHA,exact,,,',
        ]),
        throwsA(isA<CatalogBuildException>()),
      );
    });

    test('an alias row for an unknown merchant is refused', () {
      expect(
        () => build(['alias,,,,,,,,Nobody,,NOBODY,exact,,,']),
        throwsA(isA<CatalogBuildException>()),
      );
    });

    test('a merchant in a missing category is refused', () {
      expect(
        () => build(['merchant,,أ,,,,,,Alpha,nowhere,,exact,,,']),
        throwsA(isA<CatalogBuildException>()),
      );
    });

    test('a bad match mode is refused', () {
      expect(
        () => build(['merchant,,أ,,,,,,Alpha,groceries,,fuzzy,,,']),
        throwsA(isA<CatalogBuildException>()),
      );
    });

    test('ids follow row order and keywords are folded', () {
      final b = build([
        'merchant,,أ,,,,,,Alpha,groceries,,exact,,,',
        'merchant,,ب,,,,,,Beta,groceries,,exact,,,',
        'keyword,,,,,,,,,groceries,,,فاكهة,ar,60',
      ]);
      expect(
        [for (final m in b.seed.merchants) (m.id, m.canonical)],
        [(1, 'Alpha'), (2, 'Beta')],
      );
      expect(b.seed.keywords.single.keyword, 'فاكهه');
    });

    test('the normalized CSV holds keys, not raw aliases', () {
      final b = build([
        'merchant,,العزبي,,,,,,El Ezaby,groceries,,prefix,,,',
        'alias,,,,,,,,El Ezaby,,EL-EZABY #12,prefix,,,',
      ]);
      expect(b.normalizedCsv, contains('ezaby 12'));
      expect(b.normalizedCsv, isNot(contains('EL-EZABY')));
      expect(b.normalizedCsv.startsWith('$header\n'), isTrue);
    });
  });

  group('the committed catalog', () {
    final curated = File('data/catalog_curated.csv').readAsStringSync();
    final built = buildCatalog(curated, version: 1);

    test('14 system categories, AR and EN exactly as spec section 4', () {
      const expected = [
        (
          'groceries',
          'خزين البيت والسوبرماركت',
          'Groceries & Supermarkets',
          'needs',
          '#174C4F',
        ),
        (
          'dining',
          'أكل بره وكافيهات ودليفري',
          'Dining, Cafes & Delivery',
          'wants',
          '#F43F5E',
        ),
        (
          'transport',
          'مواصلات وبنزين وعربية',
          'Transport, Fuel & Rides',
          'needs',
          '#3B82F6',
        ),
        (
          'bills',
          'فواتير وشحن ومرافق',
          'Bills, Telecom & Utilities',
          'needs',
          '#0EA5E9',
        ),
        (
          'housing',
          'إيجار ومصاريف البيت',
          'Housing, Rent & Home',
          'needs',
          '#8B5CF6',
        ),
        (
          'shopping',
          'لبس وشوبينج وإلكترونيات',
          'Shopping, Fashion & Tech',
          'wants',
          '#EC4899',
        ),
        (
          'debt',
          'أقساط وجمعيات وكريدت',
          'BNPL, Installments & Debt',
          'obligations',
          '#F59E0B',
        ),
        (
          'subscriptions',
          'اشتراكات وتطبيقات',
          'Subscriptions & Digital',
          'wants',
          '#6366F1',
        ),
        (
          'health',
          'صحة وأدوية وجيم',
          'Healthcare, Meds & Gym',
          'needs',
          '#10B981',
        ),
        (
          'education',
          'تعليم ومدارس وكورسات',
          'Education, Kids & Courses',
          'needs',
          '#14B8A6',
        ),
        (
          'entertainment',
          'فسح وسفر وخروجات',
          'Entertainment & Travel',
          'wants',
          '#F97316',
        ),
        (
          'family_giving',
          'عيلة وهدايا وصدقات',
          'Family, Charity & Gifts',
          'giving',
          '#A855F7',
        ),
        (
          'savings',
          'تحويش ودهب واستثمار',
          'Savings, Gold & Investing',
          'savings',
          '#60B669',
        ),
        (
          'income',
          'مرتب ودخل وكاش باك',
          'Income, Salary & Refunds',
          'income',
          '#22C55E',
        ),
      ];
      expect([
        for (final c in built.seed.categories)
          (c.code, c.nameAr, c.nameEn, c.bucket, c.color),
      ], expected);
      expect(
        [for (final c in built.seed.categories) c.sort],
        [for (var i = 1; i <= 14; i++) i],
      );
    });

    test('about 150 spec merchants, every one with an alias', () {
      expect(built.seed.merchants.length, inInclusiveRange(120, 200));
      final withAlias = {for (final a in built.seed.aliases) a.merchantId};
      expect(withAlias.length, built.seed.merchants.length);
    });

    test('a rebuild is identical (deterministic signing)', () async {
      final key = jsonDecode(
        File('dev/dev_signing_key.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final signer = SeedSigner(
        kid: key['kid']! as String,
        d: Uint8List.fromList(
          base64Url.decode(base64Url.normalize(key['d']! as String)),
        ),
      );
      final again = buildCatalog(curated, version: 1);
      expect(again.seed.encode(), built.seed.encode());
      expect(
        signer.sign(again.seed.encode()),
        signer.sign(built.seed.encode()),
      );
    });

    test('the committed assets are current (catalog_build --check)', () async {
      final err = StringBuffer();
      final code = await runCatalogBuild(
        [
          '--input', 'data/catalog_curated.csv',
          '--out', '../../app/assets/catalog',
          '--csv-out', 'data/catalog_seed.csv',
          '--key', 'dev/dev_signing_key.json',
          '--check', //
        ],
        StringBuffer(),
        err,
      );
      expect(err.toString(), isEmpty);
      expect(code, 0);
    });

    test('the committed signature verifies, and a flipped byte does not', () {
      final json = Uint8List.fromList(
        gzip.decode(
          File('../../app/assets/catalog/catalog_seed.json.gz')
              .readAsBytesSync(),
        ),
      );
      final sig = File('../../app/assets/catalog/catalog_seed.json.sig')
          .readAsStringSync();
      expect(verifySeedSignature(json, sig, bundledSeedKeys()), 's0000d');
      json[json.length ~/ 2] ^= 1;
      expect(
        () => verifySeedSignature(json, sig, bundledSeedKeys()),
        throwsA(isA<CatalogSeedException>()),
      );
    });

    test('the backend CSV carries only normalized aliases', () {
      final rows = parseCsv(built.normalizedCsv);
      final key = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');
      final aliasRows = rows.where((r) => r['entity'] == 'alias').toList();
      expect(aliasRows, isNotEmpty);
      for (final r in aliasRows) {
        expect(key.hasMatch(r['alias']), isTrue, reason: 'line ${r.line}');
        expect(r['alias'].length, lessThanOrEqualTo(64));
      }
    });
  });
}
