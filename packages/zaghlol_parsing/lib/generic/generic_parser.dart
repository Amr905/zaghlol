import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../registry/registry_models.dart';
import 'generic_keywords.dart';

/// Heuristic parser for messages from sources with no template (parsing-engine
/// §7, FR-PAR-13). Pure, total and linear: no regex with nested quantifiers,
/// no I/O, no logging. The result never carries message text.
///
/// Conservative by design: a currency is taken only when a marker touches the
/// number; a direction only when a keyword names it; a merchant only after a
/// marker word. Anything else stays null. Confidence never reaches the
/// auto-accept threshold.
///
/// [folded] is `foldKeyIndexed(body)`; [body] is the original text (merchant
/// display keeps its spelling). [language] is `ar` or `en`.
ParseResult parseGeneric({
  required String body,
  required FoldedText folded,
  required DateTime receivedAt,
  required String language,
  List<CompiledPattern> globalLast4 = const [],
  MerchantCleaningConfig cleaning = MerchantCleaningConfig.defaults,
}) {
  final t = folded.text;
  if (_hits(t, declineKeywords, null).isNotEmpty) {
    return const ParseUnrecognized(UnrecognizedReason.genericDeclined);
  }
  final candidates = _candidates(t);
  if (candidates.isEmpty) {
    return const ParseUnrecognized(UnrecognizedReason.genericNoAmount);
  }
  final hits = [
    ..._hits(
      t,
      expenseKeywords,
      TemplateDirection.expense,
    ).where((h) => !_addressedToReader(t, h)),
    ..._hits(t, incomeKeywords, TemplateDirection.income),
  ];

  // Amount: the candidate nearest a direction keyword; first on a tie.
  final ranked = [
    for (var i = 0; i < candidates.length; i++)
      (candidates[i], _nearest(candidates[i], hits, null), i),
  ]..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
  final best = ranked.first.$1;
  final reasons = <GenericReason>{};
  for (final other in ranked.skip(1)) {
    if (other.$1.money == best.money) {
      continue;
    }
    // A different amount that no keyword separates from the winner.
    if (ranked.first.$2 == _far || ranked.first.$2 == other.$2) {
      reasons.add(GenericReason.amountAmbiguous);
    }
    break;
  }

  // Two currencies in one message and no way to tell which is the charge
  // (a foreign amount in brackets, `Original USD 20.00`): never silently
  // pick one (D-28), flag it and lower the confidence.
  if (ranked.any((r) => r.$1.money.currency != best.money.currency)) {
    reasons.add(GenericReason.currencyAmbiguous);
  }

  // Direction: the nearest keyword; opposite keywords close together cancel.
  final expenseDistance = _nearest(best, hits, TemplateDirection.expense);
  final incomeDistance = _nearest(best, hits, TemplateDirection.income);
  TemplateDirection? direction;
  if (expenseDistance == _far && incomeDistance == _far) {
    reasons.add(GenericReason.directionUnknown);
  } else if (expenseDistance != _far &&
      incomeDistance != _far &&
      (expenseDistance - incomeDistance).abs() <= _conflictChars) {
    reasons.add(GenericReason.directionConflict);
  } else {
    direction = expenseDistance < incomeDistance
        ? TemplateDirection.expense
        : TemplateDirection.income;
  }

  final last4 = _last4(t, globalLast4);
  final merchant = _merchant(folded, body, cleaning);
  if (last4 == null && merchant == null) {
    reasons.add(GenericReason.sparseFields);
  }

  final ordered = reasons.toList()..sort((a, b) => a.index.compareTo(b.index));
  var confidence = kGenericMaxConfidencePermille;
  for (final r in ordered) {
    confidence = confidence * r.factorPermille ~/ 1000;
  }
  return ParseGeneric(
    language: language,
    amount: best.money,
    direction: direction,
    last4: last4,
    merchant: merchant,
    occurredAt: receivedAt,
    confidencePermille: confidence.clamp(0, kGenericMaxConfidencePermille),
    reasons: ordered,
  );
}

/// An expense keyword whose object is the reader (`paid you`) says nothing
/// about the reader's own direction.
bool _addressedToReader(String t, _Hit h) {
  final word = t.substring(h.start, h.end);
  final suffixes = addressedToReaderSuffixes[word];
  if (suffixes == null) {
    return false;
  }
  for (final x in suffixes) {
    if (t.startsWith(x, h.end)) {
      final e = h.end + x.length;
      if (x.codeUnitAt(0) != 0x20 ||
          e == t.length ||
          !_isAlnum(t.codeUnitAt(e))) {
        return true;
      }
    }
  }
  return false;
}

/// Opposite keywords closer than this (characters, measured as the
/// difference of their distances to the amount) leave the direction unset.
const int _conflictChars = 20;

/// Distance used when there is no keyword at all.
const int _far = 1 << 30;

/// Characters scanned back for a balance word before a number.
const int _balanceWindow = 28;

final class _Hit {
  const _Hit(this.start, this.end, this.direction);
  final int start;
  final int end;
  final TemplateDirection? direction;
}

final class _Candidate {
  const _Candidate(this.start, this.end, this.money);
  final int start;
  final int end;
  final Money money;
}

bool _isAlnum(int u) =>
    (u >= 0x30 && u <= 0x39) ||
    (u >= 0x61 && u <= 0x7A) ||
    (u >= 0x0600 && u <= 0x06FF);

bool _isAsciiLetter(int u) => u >= 0x61 && u <= 0x7A;

/// Occurrences of [words] in [t]; Latin words only on word boundaries.
List<_Hit> _hits(String t, List<String> words, TemplateDirection? direction) {
  final out = <_Hit>[];
  for (final w in words) {
    final latin = _isAsciiLetter(w.codeUnitAt(0));
    var from = 0;
    while (true) {
      final i = t.indexOf(w, from);
      if (i < 0) {
        break;
      }
      from = i + 1;
      final end = i + w.length;
      if (latin &&
          ((i > 0 && _isAlnum(t.codeUnitAt(i - 1))) ||
              (end < t.length && _isAlnum(t.codeUnitAt(end))))) {
        continue;
      }
      out.add(_Hit(i, end, direction));
    }
  }
  return out;
}

/// Distance in characters from [c] to the nearest keyword of [direction]
/// (any direction when null), or [_far].
int _nearest(_Candidate c, List<_Hit> hits, TemplateDirection? direction) {
  var best = _far;
  for (final h in hits) {
    if (direction != null && h.direction != direction) {
      continue;
    }
    final d = h.end <= c.start
        ? c.start - h.end
        : h.start >= c.end
        ? h.start - c.end
        : 0;
    if (d < best) {
      best = d;
    }
  }
  return best;
}

final RegExp _numberRun = RegExp(r'[0-9][0-9.,]*');

final List<MapEntry<String, String>> _words = (currencyWords.entries.toList()
  ..sort((a, b) => b.key.length.compareTo(a.key.length)));

final class _Marker {
  const _Marker(this.currency, this.start, this.end);
  final Currency currency;
  final int start;
  final int end;
}

final class _Run {
  _Run(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
  _Marker? pre;
  _Marker? suf;
}

/// ISO codes that are also common English words: never read as a currency
/// (`paid 50 all`, `100 top up`).
const Set<String> _wordCodes = {
  'all', 'try', 'top', 'pen', 'cup', 'mop', 'sos', 'lak', 'mad', 'bob', 'gel',
  'bam', 'ang', 'ron', //
};

Currency? _isoCode(String lowerCode) => _wordCodes.contains(lowerCode)
    ? null
    : Currency.tryOf(lowerCode.toUpperCase());

/// Currency marker ending right before [at] (spaces allowed between).
_Marker? _markerBefore(String t, int at) {
  var e = at;
  while (e > 0 && t.codeUnitAt(e - 1) == 0x20) {
    e--;
  }
  if (e == 0) {
    return null;
  }
  final symbol = resolveCurrencyMarker(t[e - 1], null);
  if (symbol != null) {
    return _Marker(symbol, e - 1, e);
  }
  for (final w in _words) {
    final s = e - w.key.length;
    if (s >= 0 &&
        t.startsWith(w.key, s) &&
        (s == 0 || !_isAlnum(t.codeUnitAt(s - 1)))) {
      return _Marker(Currency.tryOf(w.value)!, s, e);
    }
  }
  if (e >= 3 && (e == 3 || !_isAlnum(t.codeUnitAt(e - 4)))) {
    final code = t.substring(e - 3, e);
    if (code.codeUnits.every(_isAsciiLetter)) {
      final c = _isoCode(code);
      if (c != null) {
        return _Marker(c, e - 3, e);
      }
    }
  }
  return null;
}

/// Currency marker starting right after [at] (spaces allowed between).
_Marker? _markerAfter(String t, int at) {
  var s = at;
  while (s < t.length && t.codeUnitAt(s) == 0x20) {
    s++;
  }
  if (s >= t.length) {
    return null;
  }
  final symbol = resolveCurrencyMarker(t[s], null);
  if (symbol != null) {
    return _Marker(symbol, s, s + 1);
  }
  for (final w in _words) {
    final e = s + w.key.length;
    if (t.startsWith(w.key, s) &&
        (e == t.length || !_isAlnum(t.codeUnitAt(e)))) {
      return _Marker(Currency.tryOf(w.value)!, s, e);
    }
  }
  final e = s + 3;
  if (e <= t.length && (e == t.length || !_isAlnum(t.codeUnitAt(e)))) {
    final code = t.substring(s, e);
    if (code.codeUnits.every(_isAsciiLetter)) {
      final c = _isoCode(code);
      if (c != null) {
        return _Marker(c, s, e);
      }
    }
  }
  return null;
}

bool _isDigit(String t, int i) =>
    i >= 0 &&
    i < t.length &&
    t.codeUnitAt(i) >= 0x30 &&
    t.codeUnitAt(i) <= 0x39;

/// A run that is part of a date or time (`23/10`, `11:14`, `2026-10-23`).
bool _dateLike(String t, _Run r) {
  final b = r.start - 1;
  final a = r.end;
  bool joiner(int u) => u == 0x2F || u == 0x3A || u == 0x2D;
  return (b >= 1 && joiner(t.codeUnitAt(b)) && _isDigit(t, b - 1)) ||
      (a < t.length - 1 && joiner(t.codeUnitAt(a)) && _isDigit(t, a + 1));
}

List<_Candidate> _candidates(String t) {
  final runs = <_Run>[];
  for (final m in _numberRun.allMatches(t)) {
    var end = m.end;
    var text = m.group(0)!;
    if (RegExp(r'[0-9][.,]$').hasMatch(text)) {
      text = text.substring(0, text.length - 1);
      end -= 1;
    }
    final run = _Run(m.start, end, text);
    if (!_dateLike(t, run)) {
      runs.add(run);
    }
  }
  for (final r in runs) {
    r
      ..pre = _markerBefore(t, r.start)
      ..suf = _markerAfter(t, r.end);
  }
  // A marker between two numbers belongs to the one with no other marker;
  // if both or neither lack one it is used for neither.
  for (var i = 0; i + 1 < runs.length; i++) {
    final m = runs[i];
    final n = runs[i + 1];
    final shared = m.suf;
    if (shared != null && n.pre != null && shared.start == n.pre!.start) {
      if (m.pre != null && n.suf == null) {
        m.suf = null;
      } else if (n.suf != null && m.pre == null) {
        n.pre = null;
      } else {
        m.suf = null;
        n.pre = null;
      }
    }
  }
  final out = <_Candidate>[];
  var previousEnd = 0;
  for (final r in runs) {
    final pre = r.pre;
    final suf = r.suf;
    final start = r.start;
    final windowStart = [
      previousEnd,
      (pre?.start ?? start) - _balanceWindow,
      0,
    ].reduce((a, b) => a > b ? a : b);
    previousEnd = r.end;
    final currency = pre?.currency ?? suf?.currency;
    if (currency == null ||
        (pre != null && suf != null && pre.currency != suf.currency)) {
      continue;
    }
    final window = t.substring(windowStart, pre?.start ?? start);
    if (balanceKeywords.any(window.contains)) {
      continue;
    }
    final parsed = parseAmount(r.text, currency: currency);
    final money = parsed is Ok<Money, ParseFailure> ? parsed.value : null;
    if (money == null || !money.isPositive) {
      continue;
    }
    out.add(_Candidate(pre?.start ?? start, suf?.end ?? r.end, money));
  }
  return out;
}

final RegExp _last4Marked = RegExp(
  r'(?:\*{1,8}|\bx{2,8}|ending(?: in| with)?|(?:card|account|acct)(?: (?:no|number))?|(?:ال)?[مي]نتهي ب|رقم (?:ال)?(?:بطاقه|حساب)|بطاقه|حساب)[ :.#x-]{0,4}([0-9]{4})(?![0-9])(?![.,][0-9])',
);

String? _last4(String t, List<CompiledPattern> declared) {
  for (final p in declared) {
    final d = p.regex.firstMatch(t)?.group(1);
    if (d != null && d.length == 4 && _allDigits(d)) {
      return d;
    }
  }
  return _last4Marked.firstMatch(t)?.group(1);
}

bool _allDigits(String s) => s.codeUnits.every((u) => u >= 0x30 && u <= 0x39);

const int _maxMerchantTokens = 4;

/// No letters, or half or more of the characters are digits (`98765xxxxx`).
bool _mostlyDigits(String c) {
  var digits = 0;
  var letters = 0;
  for (final u in c.codeUnits) {
    if (u >= 0x30 && u <= 0x39) {
      digits++;
    } else if (u > 0x39) {
      letters++;
    }
  }
  return letters == 0 || digits * 2 >= c.length;
}

CleanedMerchant? _merchant(
  FoldedText folded,
  String original,
  MerchantCleaningConfig cleaning,
) {
  final t = folded.text;
  // Tokens split on single spaces (the fold collapses runs).
  final starts = <int>[];
  final raws = <String>[];
  var s = 0;
  for (var i = 0; i <= t.length; i++) {
    if (i == t.length || t.codeUnitAt(i) == 0x20) {
      if (i > s) {
        starts.add(s);
        raws.add(t.substring(s, i));
      }
      s = i + 1;
    }
  }
  bool endsClause(String raw) => RegExp(r'[.,;:!?]$').hasMatch(raw);
  String core(String raw) {
    var a = 0;
    var b = raw.length;
    while (a < b && '([\'"'.contains(raw[a])) {
      a++;
    }
    while (b > a && '.,;:!?)\'"'.contains(raw[b - 1])) {
      b--;
    }
    return raw.substring(a, b);
  }

  for (var i = 0; i < raws.length; i++) {
    if (!merchantMarkers.contains(core(raws[i]))) {
      continue;
    }
    int? spanStart;
    var spanEnd = 0;
    var count = 0;
    for (var j = i + 1; j < raws.length && count < _maxMerchantTokens; j++) {
      final c = core(raws[j]);
      if (c.isEmpty ||
          merchantStopWords.contains(c) ||
          _mostlyDigits(c) ||
          currencyWords.containsKey(c) ||
          resolveCurrencyMarker(c, null) != null) {
        break;
      }
      final cStart = starts[j] + raws[j].indexOf(c);
      spanStart ??= cStart;
      spanEnd = cStart + c.length;
      count++;
      if (endsClause(raws[j])) {
        break;
      }
    }
    if (spanStart == null) {
      continue;
    }
    final firstOriginal = original.codeUnitAt(folded.origin[spanStart]);
    final firstFolded = t.codeUnitAt(spanStart);
    if (_isAsciiLetter(firstFolded) &&
        !(firstOriginal >= 0x41 && firstOriginal <= 0x5A)) {
      continue;
    }
    final display = foldForMatching(
      original.substring(
        folded.origin[spanStart],
        folded.origin[spanEnd - 1] + 1,
      ),
    );
    final cleaned = cleanMerchant(display, config: cleaning);
    if (cleaned.display.isNotEmpty) {
      return cleaned;
    }
  }
  return null;
}
