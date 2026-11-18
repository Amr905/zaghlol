import 'dart:io';

import 'package:catalog_build/catalog_build.dart';
import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart' show merchantKey;

// FU-260: a `prefix` alias matches any descriptor that starts with its key, so
// a short or generic key over-matches card descriptors. Short keys must be
// `exact`, unless they are a distinctive brand listed here on purpose.
const _distinctiveShortBrands = {
  'kfc',
  'uber',
  'didi',
  'swvl',
  'taqa',
  'ikea',
  'zara',
  'raya',
  'valu',
  'vox',
  'osn',
};

const _maxShortPrefixKeyLength = 4;

const _genericWords = [
  'MISR', 'EGYPT', 'CAFE', 'COFFEE', 'MARKET', 'MALL', 'CITY', 'STORE', //
  'SHOP', 'BANK', 'PHARMACY', 'GROUP', 'CENTER', 'MART', 'SUPER', 'FOOD',
  'HOME', 'PLUS', 'GOLD', 'PAY', 'CASH', 'CARD', 'ONLINE', 'EXPRESS',
  'SERVICES', 'MEDICAL', 'CLINIC', 'HOSPITAL', 'SCHOOL', 'FASHION', 'GAS',
  'STATION', 'TAXI', 'TRAVEL', 'HOTEL', 'RESTAURANT',
  'مصر', 'كافيه', 'كافي', 'ماركت', 'مول', 'سيتي', 'سوبر', 'ستور', 'محل', 'بنك',
  'صيدلية', 'مجموعة', 'سنتر',
];

/// The prefix-mode alias keys of [csv], with the row that produced them.
List<({int line, String key})> prefixKeys(String csv) {
  final rows = parseCsv(csv);
  final defaultMatch = <String, String>{
    for (final r in rows)
      if (r['entity'] == 'merchant')
        r['canonical']: r['match'].isEmpty ? 'exact' : r['match'],
  };
  final out = <({int line, String key})>[];
  for (final r in rows) {
    final String raw;
    final String match;
    switch (r['entity']) {
      case 'merchant':
        raw = r['canonical'];
        match = defaultMatch[raw]!;
      case 'alias':
        raw = r['alias'];
        match = r['match'].isEmpty ? 'exact' : r['match'];
      default:
        continue;
    }
    if (match != 'prefix') continue;
    for (final v in aliasVariants(raw)) {
      out.add((line: r.line, key: merchantKey(v)));
    }
  }
  return out;
}

/// Why [key] is too risky as a prefix key, or null.
String? riskyPrefixKey(String key, Set<String> generic) {
  if (generic.contains(key)) return 'generic word';
  if (key.length <= _maxShortPrefixKeyLength &&
      !_distinctiveShortBrands.contains(key)) {
    return 'prefix key of $_maxShortPrefixKeyLength characters or fewer';
  }
  return null;
}

void main() {
  final generic = {for (final w in _genericWords) merchantKey(w)};
  final csv = File('data/catalog_curated.csv').readAsStringSync();

  test('the curated seed has no risky prefix alias', () {
    final bad = [
      for (final k in prefixKeys(csv))
        if (riskyPrefixKey(k.key, generic) case final why?)
          'line ${k.line}: "${k.key}" ($why); make it exact or qualify it',
    ];
    expect(bad, isEmpty);
  });

  test('the lint rejects short and generic prefix keys (fails without it)', () {
    const header =
        'entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight';
    final short = prefixKeys(
      '$header\nalias,,,,,,,,Some Shop,,ELDAHAN,prefix,,,\n'
      'alias,,,,,,,,Some Shop,,ELDAHAN2,exact,,,\n',
    );
    expect(short.map((k) => k.key), contains(merchantKey('ELDAHAN')));
    expect(riskyPrefixKey('gy', generic), isNotNull);
    expect(riskyPrefixKey('abd', generic), isNotNull);
    expect(riskyPrefixKey(merchantKey('MARKET'), generic), isNotNull);
    expect(riskyPrefixKey(merchantKey('MISR'), generic), isNotNull);
    expect(riskyPrefixKey('uber', generic), isNull);
    expect(riskyPrefixKey('seoudi', generic), isNull);
    // Exact short keys are fine: only prefix mode is listed.
    expect(short.where((k) => k.key == merchantKey('ELDAHAN2')), isEmpty);
  });
}
