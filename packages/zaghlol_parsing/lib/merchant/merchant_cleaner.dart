/// Merchant cleaning and the normalized merchant key (T-034, FR-PAR-05,
/// parsing-engine §5). Pure and deterministic; never throws.
library;

import '../normalize/text_normalizer.dart';

/// Data tables for cleaning. The bundled registry supplies these in the
/// application layer; [MerchantCleaningConfig.defaults] is the seed set.
/// All entries are matched case-insensitively on the matching fold
/// ([foldKey] of the entry), so Arabic and Latin spellings both work.
class MerchantCleaningConfig {
  const MerchantCleaningConfig({
    required this.countryTokens,
    required this.cityPhrases,
    required this.legalSuffixes,
    required this.noiseTokens,
  });

  /// Seed lists. City phrases may have several words (`NASR CITY`).
  static const MerchantCleaningConfig defaults = MerchantCleaningConfig(
    countryTokens: _countries,
    cityPhrases: [
      ..._citiesA,
      ..._citiesB,
      ..._citiesC,
      ..._citiesD,
      ..._citiesE,
    ],
    legalSuffixes: [..._legalA, ..._legalB],
    noiseTokens: _noise,
  );

  final List<String> countryTokens;
  final List<String> cityPhrases;
  final List<String> legalSuffixes;

  /// Removed wherever they appear (POS, ECOM, ONLINE).
  final List<String> noiseTokens;
}

// Short POS country codes only. Full names (EGYPT, مصر) can be part of a
// merchant name (`بنك مصر`, `NATIONAL BANK OF EGYPT`) and are never stripped.
const List<String> _countries = ['EG', 'EGY', 'ARE', 'UAE'];
const List<String> _citiesA = ['CAIRO', 'GIZA', 'MAADI', 'DOKKI', 'ZAMALEK'];
const List<String> _citiesB = ['NASR CITY', 'NEW CAIRO', 'SHEIKH ZAYED'];
const List<String> _citiesC = ['HELIOPOLIS', 'MOHANDESSIN', 'TAGAMOA'];
const List<String> _citiesD = ['6 OCTOBER', 'ALEXANDRIA', 'MANSOURA', 'TANTA'];
const List<String> _citiesE = ['القاهرة', 'الجيزة', 'المعادي', 'مدينة نصر'];
const List<String> _legalA = ['LLC', 'LTD', 'INC', 'CO', 'CORP', 'SAE'];
const List<String> _legalB = ['S.A.E', 'ش.م.م', 'ذ.م.م'];
const List<String> _noise = ['POS', 'ECOM', 'ONLINE'];

/// Result of [cleanMerchant].
class CleanedMerchant {
  const CleanedMerchant({
    required this.display,
    required this.cleaned,
    required this.key,
  });

  /// Title-cased cleaned text for the UI when no catalog name matches.
  final String display;

  /// Upper-cased (Latin) cleaned text, tokens joined by one space.
  final String cleaned;

  /// `merchant_norm`: see [merchantKey].
  final String key;

  @override
  String toString() => 'CleanedMerchant(display: $display, key: $key)';
}

/// Longest `merchant_norm`, equal to the backend cap
/// (`CatalogText.MaxKeyLength`).
const int merchantKeyMaxLength = 64;

/// Cleans a raw merchant string and derives its key. Empty or blank input
/// yields empty strings (the caller treats that as "no merchant"). Input
/// made only of noise tokens (`POS`) falls back to its own tokens rather
/// than becoming empty.
CleanedMerchant cleanMerchant(
  String raw, {
  MerchantCleaningConfig config = MerchantCleaningConfig.defaults,
}) {
  final tokens = _tokenize(raw);
  if (tokens.isEmpty) {
    return const CleanedMerchant(display: '', cleaned: '', key: '');
  }
  final cleanedTokens = _strip(tokens, config);
  final cleaned = cleanedTokens.join(' ');
  return CleanedMerchant(
    display: cleanedTokens.map(_titleCase).join(' '),
    cleaned: cleaned,
    key: merchantKey(cleaned),
  );
}

/// The `merchant_norm` key (parsing-engine §5). Canonical rule:
/// 1. [foldKey] (digits, tatweel, harakat, alef/ya/ta-marbuta, lowercase).
/// 2. A leading Arabic article `ال` is removed (before transliteration).
/// 3. Arabic letters are transliterated with the Egyptian table below;
///    every character outside `a-z` / `0-9` becomes a space; runs of spaces
///    collapse and the ends are trimmed.
/// 4. At most one leading article is removed: a first token `el` or `al`
///    when another token follows, or an attached `el`/`al` (`elezaby`)
///    when at least four characters follow and the word does not start with
///    a common English stem such as `elect`, `eleven`, `album` (see
///    [_attachedArticleExceptions]). Skipped if step 2 already stripped one.
/// 5. Adjacent single-character tokens are joined (`b t e c h` -> `btech`);
///    all other tokens stay separated by one space.
/// 6. Capped at [merchantKeyMaxLength], then a trailing space is trimmed.
///
/// Output is `[a-z0-9]` words separated by single spaces, which is a valid
/// backend alias (`CatalogText.Normalize`). An empty result (emoji only,
/// unmapped scripts) means "no merchant key"; callers must not match on it.
///
/// The key is applied exactly once per side: to the raw merchant text at
/// parse time and to each catalog alias when the catalog is built. Stored
/// aliases are never re-keyed, so the rule need not be idempotent
/// (`ELELEZABY` -> `elezaby`, which would key to `zaby` if keyed again).
/// tools/catalog_build must call this same algorithm and is tested against
/// `test/fixtures/merchant_key_vectors.json`.
String merchantKey(String text) {
  var folded = foldKey(text);
  var articleStripped = false;
  if (_hasArabicArticle(folded)) {
    folded = folded.substring(2);
    articleStripped = true;
  }
  final spaced = StringBuffer();
  for (final unit in folded.codeUnits) {
    final mapped = _translit[unit];
    if (mapped != null) {
      spaced.write(mapped);
    } else if (_isAsciiAlnum(unit)) {
      spaced.writeCharCode(unit);
    } else {
      spaced.writeCharCode(0x20);
    }
  }
  final tokens = [
    for (final w in spaced.toString().split(' '))
      if (w.isNotEmpty) w,
  ];
  if (tokens.isEmpty) {
    return '';
  }
  if (!articleStripped) {
    final first = tokens.first;
    if ((first == 'el' || first == 'al') && tokens.length > 1) {
      tokens.removeAt(0);
    } else if (_hasAttachedLatinArticle(first)) {
      tokens[0] = first.substring(2);
    }
  }
  final joined = <String>[];
  var previousSingle = false;
  for (final t in tokens) {
    final single = t.length == 1;
    if (single && previousSingle) {
      joined[joined.length - 1] = '${joined.last}$t';
    } else {
      joined.add(t);
    }
    previousSingle = single;
  }
  var key = joined.join(' ');
  if (key.length > merchantKeyMaxLength) {
    key = key.substring(0, merchantKeyMaxLength).trimRight();
  }
  return key;
}

bool _hasArabicArticle(String w) {
  if (w.length <= 2) {
    return false;
  }
  // Only a prefix of the first word: `الاهرام`, not the word `ال`.
  return w.codeUnitAt(0) == 0x0627 &&
      w.codeUnitAt(1) == 0x0644 &&
      w.codeUnitAt(2) != 0x20;
}

/// Common English words that begin with `el` / `al`; an attached article is
/// never stripped from a word starting with one of these stems.
const List<String> _attachedArticleExceptions = [
  ..._stemsEl,
  ..._stemsAlA,
  ..._stemsAlB,
];
const List<String> _stemsEl = ['elec', 'eleg', 'elev', 'elem', 'elit', 'elli'];
const List<String> _stemsAlA = ['albe', 'albu', 'alban', 'alco', 'aler'];
const List<String> _stemsAlB = ['alle', 'allo', 'alph', 'alpi', 'alma', 'almo'];

/// `elezaby`, `alrawsha`: attached article with at least four characters
/// left, unless the word starts with a common English stem.
bool _hasAttachedLatinArticle(String w) {
  if (w.length < 6 || !(w.startsWith('el') || w.startsWith('al'))) {
    return false;
  }
  for (final stem in _attachedArticleExceptions) {
    if (w.startsWith(stem)) {
      return false;
    }
  }
  return true;
}

bool _isAsciiAlnum(int u) {
  return (u >= 0x61 && u <= 0x7A) || (u >= 0x30 && u <= 0x39);
}

/// Separators that carry no meaning in a merchant name.
const String _separatorChars = '*_|/\\,،:;';

List<String> _tokenize(String raw) {
  // Matching fold keeps case and Arabic letter variants; the display of
  // Arabic names is therefore the input minus tatweel and harakat.
  final folded = foldForMatching(raw);
  final spaced = StringBuffer();
  for (final unit in folded.runes) {
    final isSeparator = _separatorChars.contains(String.fromCharCode(unit));
    spaced.writeCharCode(isSeparator ? 0x20 : unit);
  }
  final tokens = <String>[];
  for (final part in spaced.toString().split(' ')) {
    final token = _trimEdgePunctuation(part);
    if (token.isNotEmpty) {
      tokens.add(_upperLatin(token));
    }
  }
  return tokens;
}

String _trimEdgePunctuation(String t) {
  var start = 0;
  var end = t.length;
  bool junk(int u) => u == 0x2D || u == 0x2E || u == 0x27 || u == 0x22;
  while (start < end && junk(t.codeUnitAt(start))) {
    start++;
  }
  // A trailing dot is kept for dotted abbreviations such as `S.A.E.`; the
  // legal-suffix match ignores trailing dots.
  while (end > start && t.codeUnitAt(end - 1) == 0x2D) {
    end--;
  }
  return t.substring(start, end);
}

String _upperLatin(String t) {
  final b = StringBuffer();
  for (final u in t.codeUnits) {
    b.writeCharCode((u >= 0x61 && u <= 0x7A) ? u - 0x20 : u);
  }
  return b.toString();
}

List<String> _strip(List<String> input, MerchantCleaningConfig config) {
  String f(String s) => _upperLatin(foldKey(s));
  final noise = config.noiseTokens.map(f).toSet();
  final countries = config.countryTokens.map(f).toSet();
  final legal = config.legalSuffixes.map(f).toSet();
  final cities = <List<String>>[];
  for (final phrase in config.cityPhrases) {
    final words = f(phrase).split(' ');
    if (words.first.isNotEmpty) {
      cities.add(words);
    }
  }
  cities.sort((a, b) => b.length.compareTo(a.length));

  final folded = input.map(f).toList();
  final keep = List<bool>.filled(input.length, true);
  for (var i = 0; i < input.length; i++) {
    if (noise.contains(folded[i])) {
      keep[i] = false;
    }
  }

  // Trailing run: terminal codes, legal suffixes, countries, cities. The
  // first kept token is the merchant name and is never stripped.
  int firstKept() => keep.indexOf(true);
  while (true) {
    var last = input.length - 1;
    while (last >= 0 && !keep[last]) {
      last--;
    }
    if (last <= firstKept()) {
      break;
    }
    final t = folded[last];
    var removed = 1;
    final isLegal = legal.contains(_withoutTrailingDots(t));
    if (_isTerminalCode(t) || isLegal || countries.contains(t)) {
      keep[last] = false;
    } else {
      removed = _matchCity(folded, keep, last, cities, firstKept());
      if (removed == 0) {
        break;
      }
    }
  }
  final out = <String>[];
  for (var i = 0; i < input.length; i++) {
    if (keep[i]) {
      out.add(input[i]);
    }
  }
  return out.isEmpty ? input : out;
}

/// Marks a city phrase ending at [last] as removed. Returns tokens removed
/// (0 when none). Never touches index [floor] or below.
int _matchCity(
  List<String> folded,
  List<bool> keep,
  int last,
  List<List<String>> cities,
  int floor,
) {
  for (final city in cities) {
    final startIdx = _walkBack(keep, last, city.length);
    if (startIdx == null || startIdx <= floor) {
      continue;
    }
    var ok = true;
    var idx = startIdx;
    for (final word in city) {
      while (!keep[idx]) {
        idx++;
      }
      if (folded[idx] != word) {
        ok = false;
        break;
      }
      idx++;
    }
    if (ok) {
      idx = startIdx;
      for (var n = 0; n < city.length; n++) {
        while (!keep[idx]) {
          idx++;
        }
        keep[idx] = false;
        idx++;
      }
      return city.length;
    }
  }
  return 0;
}

int? _walkBack(List<bool> keep, int last, int count) {
  var idx = last;
  var seen = 0;
  while (idx >= 0) {
    if (keep[idx]) {
      seen++;
      if (seen == count) {
        return idx;
      }
    }
    idx--;
  }
  return null;
}

String _withoutTrailingDots(String t) {
  var end = t.length;
  while (end > 0 && t.codeUnitAt(end - 1) == 0x2E) {
    end--;
  }
  return end == 0 ? t : t.substring(0, end);
}

bool _isTerminalCode(String t) {
  var s = t;
  if (s.startsWith('#')) {
    s = s.substring(1);
    return s.isNotEmpty && s.codeUnits.every(_isDigit);
  }
  return s.length >= 3 && s.codeUnits.every(_isDigit);
}

bool _isDigit(int u) => u >= 0x30 && u <= 0x39;

String _titleCase(String token) {
  if (token.codeUnits.any((u) => u > 0x7F)) {
    return token;
  }
  // Only letters change; digits and symbols stay readable (`7-Eleven`).
  final b = StringBuffer();
  var atWordStart = true;
  for (final u in token.codeUnits) {
    final isUpper = u >= 0x41 && u <= 0x5A;
    final isLower = u >= 0x61 && u <= 0x7A;
    if (isUpper || isLower) {
      final upper = isLower ? u - 0x20 : u;
      final lower = isUpper ? u + 0x20 : u;
      b.writeCharCode(atWordStart ? upper : lower);
      atWordStart = false;
    } else {
      b.writeCharCode(u);
      atWordStart = u == 0x2D || u == 0x26;
    }
  }
  return b.toString();
}

/// Egyptian-friendly Arabic to Latin table, applied after [foldKey]
/// (so only the folded alef, yeh and heh forms appear).
const Map<int, String> _translit = {
  0x0627: 'a', // ا
  0x0628: 'b', // ب
  0x062A: 't', // ت
  0x062B: 's', // ث
  0x062C: 'g', // ج
  0x062D: 'h', // ح
  0x062E: 'kh', // خ
  0x062F: 'd', // د
  0x0630: 'z', // ذ
  0x0631: 'r', // ر
  0x0632: 'z', // ز
  0x0633: 's', // س
  0x0634: 'sh', // ش
  0x0635: 's', // ص
  0x0636: 'd', // ض
  0x0637: 't', // ط
  0x0638: 'z', // ظ
  0x0639: 'a', // ع
  0x063A: 'gh', // غ
  0x0641: 'f', // ف
  0x0642: 'k', // ق
  0x0643: 'k', // ك
  0x0644: 'l', // ل
  0x0645: 'm', // م
  0x0646: 'n', // ن
  0x0647: 'h', // ه
  0x0648: 'w', // و
  0x064A: 'y', // ي
  0x0621: '', // ء
  0x0624: 'w', // ؤ
  0x0626: 'y', // ئ
};
