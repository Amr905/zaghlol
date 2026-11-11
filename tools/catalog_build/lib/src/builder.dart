// T-030: curated CSV -> validated seed + the normalized backend CSV.
//
// Curated rows use the backend's columns. Differences from the backend CSV:
// an `alias` cell may be raw text (`AL BORG`, `Apple.com/Bill`); the builder
// turns it into the canonical merchant key with the same `merchantKey` the
// parser uses (parsing-engine §5, FU-062), adds the attached-article
// variants (FU-066) and the merchant's own name, and writes the result as
// the normalized CSV the backend imports (T-125). A merchant row's `match`
// is the match mode of the alias derived from its own name (default exact).
//
// Merchant ids are the 1-based order of the merchant rows. The backend
// allocates ids in the same order when the normalized CSV is imported into
// an empty draft, so app and backend agree; rows must only ever be appended.

import 'package:zaghlol_catalog/zaghlol_catalog.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'alias_variants.dart';
import 'csv.dart';

/// A curated catalog that breaks a rule. The message names a line or two
/// catalog names (catalog data, never user data).
final class CatalogBuildException implements Exception {
  CatalogBuildException(this.message);
  final String message;
  @override
  String toString() => 'CatalogBuildException: $message';
}

/// The result of a build.
final class BuiltCatalog {
  BuiltCatalog(this.seed, this.normalizedCsv);

  final CatalogSeed seed;

  /// The backend import file (LF line endings, trailing newline).
  final String normalizedCsv;
}

/// Shortest key a derived alias may have (a 1-character key matches too much).
const int minAliasKeyLength = 2;

BuiltCatalog buildCatalog(String curatedCsv, {required int version}) {
  final List<CsvRow> rows;
  try {
    rows = parseCsv(curatedCsv);
  } on CsvFormatException catch (e) {
    throw CatalogBuildException(e.message);
  }

  Never fail(CsvRow row, String why) =>
      throw CatalogBuildException('line ${row.line}: $why');

  int intOf(CsvRow row, String column) =>
      int.tryParse(row[column]) ?? fail(row, '$column is not an integer');

  final categories = <SeedCategory>[];
  final merchants = <SeedMerchant>[];
  final defaultMatch = <String, String>{}; // canonical -> match
  final extraAliases = <String, List<(String, String, int)>>{};
  final keywords = <SeedKeyword>[];
  final idOf = <String, int>{};

  for (final row in rows) {
    switch (row['entity']) {
      case 'category':
        categories.add(
          SeedCategory(
            code: row['code'],
            nameAr: row['nameAr'],
            nameEn: row['nameEn'],
            icon: row['icon'],
            color: row['color'],
            bucket: row['bucket'],
            sort: intOf(row, 'sort'),
          ),
        );
      case 'merchant':
        final canonical = row['canonical'];
        if (idOf.containsKey(canonical)) fail(row, 'duplicate merchant');
        final id = merchants.length + 1;
        idOf[canonical] = id;
        defaultMatch[canonical] = row['match'].isEmpty ? 'exact' : row['match'];
        merchants.add(
          SeedMerchant(
            id: id,
            canonical: canonical,
            nameAr: row['nameAr'],
            category: row['category'],
          ),
        );
      case 'alias':
        (extraAliases[row['canonical']] ??= []).add((
          row['alias'],
          row['match'].isEmpty ? 'exact' : row['match'],
          row.line,
        ));
      case 'keyword':
        keywords.add(
          SeedKeyword(
            keyword: _foldKeyword(row['keyword']),
            lang: row['lang'],
            category: row['category'],
            weight: intOf(row, 'weight'),
          ),
        );
      default:
        fail(row, 'unknown entity');
    }
  }
  for (final owner in extraAliases.keys) {
    if (!idOf.containsKey(owner)) {
      throw CatalogBuildException(
        'alias row for unknown merchant "$owner" (line '
        '${extraAliases[owner]!.first.$3})',
      );
    }
  }

  // Aliases: the merchant's own name first, then its alias rows; each with
  // its attached-article variants. First spelling wins a duplicate key.
  final owners = <String, SeedMerchant>{}; // alias key -> merchant
  final aliases = <SeedAlias>[];
  for (final m in merchants) {
    final sources = <(String, String)>[
      (m.canonical, defaultMatch[m.canonical]!),
      for (final (raw, match, _)
          in extraAliases[m.canonical] ?? const <(String, String, int)>[])
        (raw, match),
    ];
    final own = <String, String>{}; // key -> match, insertion ordered
    for (final (raw, match) in sources) {
      for (final variant in aliasVariants(raw)) {
        final key = merchantKey(variant);
        if (key.length < minAliasKeyLength) {
          throw CatalogBuildException(
            'merchant "${m.canonical}": alias "$raw" has no usable key',
          );
        }
        own.putIfAbsent(key, () => match);
      }
    }
    for (final key in own.keys.toList()..sort()) {
      final other = owners[key];
      if (other != null) {
        throw CatalogBuildException(
          'alias key "$key" belongs to both "${other.canonical}" and '
          '"${m.canonical}"',
        );
      }
      owners[key] = m;
      aliases.add(SeedAlias(merchantId: m.id, alias: key, match: own[key]!));
    }
  }

  categories.sort((a, b) => a.sort.compareTo(b.sort));
  keywords.sort((a, b) {
    final l = a.lang.compareTo(b.lang);
    return l != 0 ? l : a.keyword.compareTo(b.keyword);
  });

  final CatalogSeed seed;
  try {
    seed = CatalogSeed.validated(
      version: version,
      ops: [...categories, ...merchants, ...aliases, ...keywords],
    );
  } on CatalogSeedException catch (e) {
    throw CatalogBuildException('seed rejected: ${e.code}');
  }
  return BuiltCatalog(seed, _normalizedCsv(seed));
}

/// Keywords are stored folded (`foldKey`: digits, tatweel, harakat, alef,
/// ya, ta-marbuta, ASCII lowercase) with single spaces, so the categorizer
/// compares folded text with them.
String _foldKeyword(String raw) =>
    foldKey(raw).trim().replaceAll(RegExp(r'\s+'), ' ');

String _normalizedCsv(CatalogSeed seed) {
  final out = StringBuffer()..writeln(csvLine(seedColumns));
  final nameOf = {for (final m in seed.merchants) m.id: m.canonical};
  List<String> row(Map<String, String> cells) => [
    for (final c in seedColumns) cells[c] ?? '',
  ];
  for (final c in seed.categories) {
    out.writeln(
      csvLine(
        row({
          'entity': 'category',
          'code': c.code,
          'nameAr': c.nameAr,
          'nameEn': c.nameEn,
          'icon': c.icon,
          'color': c.color,
          'bucket': c.bucket,
          'sort': '${c.sort}',
        }),
      ),
    );
  }
  for (final m in seed.merchants) {
    out.writeln(
      csvLine(
        row({
          'entity': 'merchant',
          'canonical': m.canonical,
          'nameAr': m.nameAr,
          'category': m.category,
        }),
      ),
    );
  }
  for (final a in seed.aliases) {
    out.writeln(
      csvLine(
        row({
          'entity': 'alias',
          'canonical': nameOf[a.merchantId]!,
          'alias': a.alias,
          'match': a.match,
        }),
      ),
    );
  }
  for (final k in seed.keywords) {
    out.writeln(
      csvLine(
        row({
          'entity': 'keyword',
          'keyword': k.keyword,
          'lang': k.lang,
          'category': k.category,
          'weight': '${k.weight}',
        }),
      ),
    );
  }
  return out.toString();
}
