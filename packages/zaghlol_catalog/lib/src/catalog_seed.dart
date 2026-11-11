// T-030: the catalog seed document and its strict codec.
//
// The seed is the same JSON the backend publishes as a full snapshot
// (OpenAPI `CatalogSnapshot`: `{version, ops[]}`, upserts only, parents
// first: categories, merchants, aliases, keywords), so one apply path serves
// the bundled seed and a downloaded snapshot. The bytes are written in one
// canonical form (fixed member order, no whitespace, UTF-8) and signed as
// they are. Decoding is strict: unknown members, wrong types, out-of-range
// values, dangling references and duplicates are all rejected, and no error
// carries any of the input (error-handling §3).

import 'dart:convert';
import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// Largest decompressed seed accepted (the backend allows 8 MiB snapshots).
const int maxSeedJsonBytes = 8 * 1024 * 1024;

/// Most ops in one seed.
const int maxSeedOps = 200000;

/// The budget buckets of `categories.bucket` (database-schema §2.4).
const Set<String> categoryBuckets = {
  'needs',
  'wants',
  'obligations',
  'savings',
  'income',
  'giving',
};

/// The alias match modes (`catalog_aliases.match`).
const Set<String> aliasMatchModes = {'exact', 'prefix', 'token'};

/// A seed that is malformed or breaks a rule. [code] is constant; [toString]
/// prints only the code.
///
/// Codes: `SEED_TOO_LARGE`, `SEED_NOT_JSON`, `SEED_BAD_SHAPE`,
/// `SEED_BAD_VALUE`, `SEED_BAD_ORDER`, `SEED_DUPLICATE`,
/// `SEED_DANGLING_REF`, `SEED_BAD_SIGNATURE`, `SEED_UNKNOWN_KEY`.
final class CatalogSeedException extends SafeException {
  CatalogSeedException(super.code);

  static const String tooLarge = 'SEED_TOO_LARGE';
  static const String notJson = 'SEED_NOT_JSON';
  static const String badShape = 'SEED_BAD_SHAPE';
  static const String badValue = 'SEED_BAD_VALUE';
  static const String badOrder = 'SEED_BAD_ORDER';
  static const String duplicate = 'SEED_DUPLICATE';
  static const String danglingRef = 'SEED_DANGLING_REF';
  static const String badSignature = 'SEED_BAD_SIGNATURE';
  static const String unknownKey = 'SEED_UNKNOWN_KEY';
}

final RegExp _categoryCode = RegExp(r'^[a-z][a-z0-9_]{1,31}$');
final RegExp _colour = RegExp(r'^#[0-9A-Fa-f]{6}$');
final RegExp _lang = RegExp(r'^[a-z]{2}$');
final RegExp _aliasKey = RegExp(r'^[a-z0-9]+( [a-z0-9]+)*$');

/// Longest alias or keyword (the `merchant_norm` cap).
const int maxKeyLength = 64;

bool _noControls(String s) =>
    !s.runes.any((r) => r < 0x20 || (r >= 0x7f && r <= 0x9f));

bool _text(String s, int min, int max) =>
    s.length >= min && s.length <= max && _noControls(s);

/// Whether [s] is a valid category code (OpenAPI `CategoryCode`).
bool isCategoryCode(String s) => _categoryCode.hasMatch(s);

/// Whether [s] is a valid alias (the canonical merchant key form,
/// parsing-engine §5).
bool isAliasKey(String s) => s.length <= maxKeyLength && _aliasKey.hasMatch(s);

/// Whether [s] is a valid keyword: 1-64 characters, no controls, no outer or
/// double spaces (Arabic allowed). Matches the `catalog_keywords` CHECK.
bool isKeywordNorm(String s) =>
    _text(s, 1, maxKeyLength) &&
    s == s.trim() &&
    !s.contains('  ') &&
    !s.contains(RegExp(r'\s{2,}'));

sealed class SeedOp {
  const SeedOp();

  Map<String, Object?> toJson();
}

final class SeedCategory extends SeedOp {
  const SeedCategory({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.icon,
    required this.color,
    required this.bucket,
    required this.sort,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final String icon;
  final String color;
  final String bucket;
  final int sort;

  @override
  Map<String, Object?> toJson() => {
    't': 'category',
    'op': 'upsert',
    'code': code,
    'nameAr': nameAr,
    'nameEn': nameEn,
    'icon': icon,
    'color': color,
    'bucket': bucket,
    'sort': sort,
  };
}

final class SeedMerchant extends SeedOp {
  const SeedMerchant({
    required this.id,
    required this.canonical,
    required this.nameAr,
    required this.category,
  });

  final int id;
  final String canonical;
  final String nameAr;
  final String category;

  @override
  Map<String, Object?> toJson() => {
    't': 'merchant',
    'op': 'upsert',
    'id': id,
    'canonical': canonical,
    'nameAr': nameAr,
    'category': category,
  };
}

final class SeedAlias extends SeedOp {
  const SeedAlias({
    required this.merchantId,
    required this.alias,
    required this.match,
  });

  final int merchantId;
  final String alias;
  final String match;

  @override
  Map<String, Object?> toJson() => {
    't': 'alias',
    'op': 'upsert',
    'merchantId': merchantId,
    'alias': alias,
    'match': match,
  };
}

final class SeedKeyword extends SeedOp {
  const SeedKeyword({
    required this.keyword,
    required this.lang,
    required this.category,
    required this.weight,
  });

  final String keyword;
  final String lang;
  final String category;
  final int weight;

  @override
  Map<String, Object?> toJson() => {
    't': 'keyword',
    'op': 'upsert',
    'keyword': keyword,
    'lang': lang,
    'category': category,
    'weight': weight,
  };
}

/// A validated seed. Construct it with [CatalogSeed.decode] or
/// [CatalogSeed.validated]; [ops] are in canonical order.
final class CatalogSeed {
  CatalogSeed._(this.version, this.ops);

  final int version;
  final List<SeedOp> ops;

  Iterable<SeedCategory> get categories => ops.whereType<SeedCategory>();
  Iterable<SeedMerchant> get merchants => ops.whereType<SeedMerchant>();
  Iterable<SeedAlias> get aliases => ops.whereType<SeedAlias>();
  Iterable<SeedKeyword> get keywords => ops.whereType<SeedKeyword>();

  /// Validates [ops] (same rules as [decode]) and wraps them. Throws
  /// [CatalogSeedException].
  factory CatalogSeed.validated({
    required int version,
    required List<SeedOp> ops,
  }) {
    if (version < 1 || version > 0x7fffffff) {
      throw CatalogSeedException(CatalogSeedException.badValue);
    }
    if (ops.length > maxSeedOps) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    final categories = <String>{};
    final merchants = <int>{};
    final aliases = <(int, String)>{};
    final keywords = <(String, String)>{};
    var rank = 0;
    for (final op in ops) {
      final r = switch (op) {
        SeedCategory() => 0,
        SeedMerchant() => 1,
        SeedAlias() => 2,
        SeedKeyword() => 3,
      };
      if (r < rank) throw CatalogSeedException(CatalogSeedException.badOrder);
      rank = r;
      switch (op) {
        case SeedCategory():
          if (!isCategoryCode(op.code) ||
              !_text(op.nameAr, 1, 80) ||
              !_text(op.nameEn, 1, 80) ||
              !_text(op.icon, 0, 64) ||
              !_colour.hasMatch(op.color) ||
              !categoryBuckets.contains(op.bucket) ||
              op.sort < 0 ||
              op.sort > 1000) {
            throw CatalogSeedException(CatalogSeedException.badValue);
          }
          if (!categories.add(op.code)) {
            throw CatalogSeedException(CatalogSeedException.duplicate);
          }
        case SeedMerchant():
          if (op.id < 1 ||
              op.id > 0x7fffffff ||
              !_text(op.canonical, 1, 120) ||
              !_text(op.nameAr, 1, 120) ||
              !isCategoryCode(op.category)) {
            throw CatalogSeedException(CatalogSeedException.badValue);
          }
          if (!categories.contains(op.category)) {
            throw CatalogSeedException(CatalogSeedException.danglingRef);
          }
          if (!merchants.add(op.id)) {
            throw CatalogSeedException(CatalogSeedException.duplicate);
          }
        case SeedAlias():
          if (!isAliasKey(op.alias) || !aliasMatchModes.contains(op.match)) {
            throw CatalogSeedException(CatalogSeedException.badValue);
          }
          if (!merchants.contains(op.merchantId)) {
            throw CatalogSeedException(CatalogSeedException.danglingRef);
          }
          if (!aliases.add((op.merchantId, op.alias))) {
            throw CatalogSeedException(CatalogSeedException.duplicate);
          }
        case SeedKeyword():
          if (!isKeywordNorm(op.keyword) ||
              !_lang.hasMatch(op.lang) ||
              !isCategoryCode(op.category) ||
              op.weight < 0 ||
              op.weight > 100) {
            throw CatalogSeedException(CatalogSeedException.badValue);
          }
          if (!categories.contains(op.category)) {
            throw CatalogSeedException(CatalogSeedException.danglingRef);
          }
          if (!keywords.add((op.lang, op.keyword))) {
            throw CatalogSeedException(CatalogSeedException.duplicate);
          }
      }
    }
    return CatalogSeed._(version, List.unmodifiable(ops));
  }

  /// The canonical JSON bytes (the bytes that are signed).
  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': version,
        'ops': [for (final o in ops) o.toJson()],
      }),
    ),
  );

  /// Strict decode of [bytes]. Throws [CatalogSeedException] only.
  static CatalogSeed decode(Uint8List bytes) {
    if (bytes.length > maxSeedJsonBytes) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw CatalogSeedException(CatalogSeedException.notJson);
    }
    final map = _object(root, const {'version', 'ops'});
    final version = map['version'];
    final rawOps = map['ops'];
    if (version is! int || rawOps is! List<Object?>) {
      throw CatalogSeedException(CatalogSeedException.badShape);
    }
    if (rawOps.length > maxSeedOps) {
      throw CatalogSeedException(CatalogSeedException.tooLarge);
    }
    return CatalogSeed.validated(
      version: version,
      ops: [for (final o in rawOps) _op(o)],
    );
  }
}

Map<String, Object?> _object(Object? value, Set<String> allowed) {
  if (value is! Map<String, Object?>) {
    throw CatalogSeedException(CatalogSeedException.badShape);
  }
  if (value.length != allowed.length || !value.keys.every(allowed.contains)) {
    throw CatalogSeedException(CatalogSeedException.unknownKey);
  }
  return value;
}

SeedOp _op(Object? raw) {
  if (raw is! Map<String, Object?>) {
    throw CatalogSeedException(CatalogSeedException.badShape);
  }
  if (raw['op'] != 'upsert') {
    // The seed holds upserts only (tombstones are for deltas).
    throw CatalogSeedException(CatalogSeedException.badShape);
  }
  String s(Map<String, Object?> m, String k) {
    final v = m[k];
    if (v is! String) throw CatalogSeedException(CatalogSeedException.badShape);
    return v;
  }

  int i(Map<String, Object?> m, String k) {
    final v = m[k];
    if (v is! int) throw CatalogSeedException(CatalogSeedException.badShape);
    return v;
  }

  switch (raw['t']) {
    case 'category':
      final m = _object(raw, const {
        't', 'op', 'code', 'nameAr', 'nameEn', 'icon', 'color', 'bucket',
        'sort', //
      });
      return SeedCategory(
        code: s(m, 'code'),
        nameAr: s(m, 'nameAr'),
        nameEn: s(m, 'nameEn'),
        icon: s(m, 'icon'),
        color: s(m, 'color'),
        bucket: s(m, 'bucket'),
        sort: i(m, 'sort'),
      );
    case 'merchant':
      final m = _object(raw, const {
        't', 'op', 'id', 'canonical', 'nameAr', 'category', //
      });
      return SeedMerchant(
        id: i(m, 'id'),
        canonical: s(m, 'canonical'),
        nameAr: s(m, 'nameAr'),
        category: s(m, 'category'),
      );
    case 'alias':
      final m = _object(raw, const {'t', 'op', 'merchantId', 'alias', 'match'});
      return SeedAlias(
        merchantId: i(m, 'merchantId'),
        alias: s(m, 'alias'),
        match: s(m, 'match'),
      );
    case 'keyword':
      final m = _object(raw, const {
        't', 'op', 'keyword', 'lang', 'category', 'weight', //
      });
      return SeedKeyword(
        keyword: s(m, 'keyword'),
        lang: s(m, 'lang'),
        category: s(m, 'category'),
        weight: i(m, 'weight'),
      );
    default:
      throw CatalogSeedException(CatalogSeedException.badShape);
  }
}
