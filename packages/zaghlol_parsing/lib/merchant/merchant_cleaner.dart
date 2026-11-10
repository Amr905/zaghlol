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
    countryTokens: ['EG', 'EGY', 'EGYPT', 'ARE', 'UAE', 'SAU', 'KSA', 'مصر'],
    cityPhrases: [
      'CAIRO',
      'GIZA',
      'MAADI',
      'NASR CITY',
      'HELIOPOLIS',
      'MOHANDESSIN',
      'DOKKI',
      'ZAMALEK',
      'NEW CAIRO',
      'TAGAMOA',
      'SHEIKH ZAYED',
      '6 OCTOBER',
      'ALEXANDRIA',
      'ALEX',
      'MANSOURA',
      'TANTA',
      'SHARM EL SHEIKH',
      'HURGHADA',
      'القاهرة',
      'الجيزة',
      'المعادي',
      'مدينة نصر',
      'الاسكندرية',
    ],
    legalSuffixes: [
      'LLC',
      'LTD',
      'INC',
      'CO',
      'CORP',
      'SAE',
      'S.A.E',
      'S.A.E.',
      'ش.م.م',
      'ذ.م.م',
    ],
    noiseTokens: ['POS', 'ECOM', 'ONLINE'],
  );

  final List<String> countryTokens;
  final List<String> cityPhrases;
  final List<String> legalSuffixes;

  /// Removed wherever they appear (POS, ECOM, ONLINE).
  final List<String> noiseTokens;
}

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

/// Cleans a raw merchant string and derives its key. Empty or all-noise
/// input yields empty strings (the caller treats that as "no merchant").
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

/// The `merchant_norm` key. Rules:
/// 1. [foldKey] (digits, tatweel, harakat, alef/ya/ta-marbuta, lowercase).
/// 2. Leading article removed: Arabic `ال`, or Latin `el`/`al` either as a
///    separate word or attached when at least four letters follow.
/// 3. Arabic letters transliterated with the Egyptian table below.
/// 4. Everything that is not `a-z` or `0-9` dropped, so spaces are gone.
///
/// Output is printable ASCII, lowercase, at most [merchantKeyMaxLength]
/// characters, and a fixed point of the backend `CatalogText.Normalize`.
///
/// Known difference from the backend: it keeps spaces and articles in
/// stored aliases (`koshary el tahrir`). Catalog aliases must be generated
/// with this function (tools/catalog_build) or exact lookup will miss.
String merchantKey(String text) {
  final folded = foldKey(text);
  final words = folded.split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return '';
  }
  final first = words.first;
  if (first == 'el' || first == 'al') {
    if (words.length > 1) {
      words.removeAt(0);
    }
  } else if (_hasArabicArticle(first)) {
    words[0] = first.substring(2);
  } else if ((first.startsWith('el') || first.startsWith('al')) &&
      _letterCount(first) - 2 >= 4 &&
      _isLatinWord(first)) {
    words[0] = first.substring(2);
  }
  final out = StringBuffer();
  for (final unit in words.join('').runes) {
    final mapped = _translit[unit];
    if (mapped != null) {
      out.write(mapped);
    } else if ((unit >= 0x61 && unit <= 0x7A) ||
        (unit >= 0x30 && unit <= 0x39)) {
      out.writeCharCode(unit);
    }
  }
  final key = out.toString();
  return key.length > merchantKeyMaxLength
      ? key.substring(0, merchantKeyMaxLength)
      : key;
}

bool _hasArabicArticle(String w) =>
    w.length > 2 && w.codeUnitAt(0) == 0x0627 && w.codeUnitAt(1) == 0x0644;

bool _isLatinWord(String w) => w.codeUnits.every((u) => u < 0x80);

int _letterCount(String w) => w.codeUnits
    .where((u) => (u >= 0x61 && u <= 0x7A) || u > 0x7F)
    .length;

List<String> _tokenize(String raw) {
  // Matching fold keeps case and Arabic letter variants; the display of
  // Arabic names is therefore the input minus tatweel and harakat.
  final folded = foldForMatching(raw);
  final spaced = StringBuffer();
  for (final unit in folded.runes) {
    // Separators that carry no meaning in a merchant name.
    if (unit == 0x2A /* * */ ||
        unit == 0x5F /* _ */ ||
        unit == 0x7C /* | */ ||
        unit == 0x2F /* / */ ||
        unit == 0x5C /* \ */ ||
        unit == 0x2C /* , */ ||
        unit == 0x060C /* ، */ ||
        unit == 0x3A /* : */ ||
        unit == 0x3B /* ; */) {
      spaced.writeCharCode(0x20);
    } else {
      spaced.writeCharCode(unit);
    }
  }
  return spaced
      .toString()
      .split(' ')
      .map(_trimEdgePunctuation)
      .where((t) => t.isNotEmpty)
      .map(_upperLatin)
      .toList();
}

String _trimEdgePunctuation(String t) {
  var start = 0;
  var end = t.length;
  bool junk(int u) => u == 0x2D || u == 0x2E || u == 0x27 || u == 0x22;
  while (start < end && junk(t.codeUnitAt(start))) {
    start++;
  }
  // A trailing dot is kept for dotted abbreviations such as `S.A.E.`; the
  // legal-suffix table lists both forms.
  while (end > start && (t.codeUnitAt(end - 1) == 0x2D)) {
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
  final cities = config.cityPhrases
      .map((p) => f(p).split(' '))
      .where((p) => p.isNotEmpty && p.first.isNotEmpty)
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));

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
    if (_isTerminalCode(t) ||
        legal.contains(_withoutTrailingDots(t)) ||
        countries.contains(t)) {
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
  // Keep tokens that carry digits or symbols readable: only letters change.
  final b = StringBuffer();
  var atWordStart = true;
  for (final u in token.codeUnits) {
    final isUpper = u >= 0x41 && u <= 0x5A;
    final isLower = u >= 0x61 && u <= 0x7A;
    if (isUpper || isLower) {
      b.writeCharCode(
        atWordStart ? (isLower ? u - 0x20 : u) : (isUpper ? u + 0x20 : u),
      );
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
