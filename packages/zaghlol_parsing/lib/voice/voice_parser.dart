/// Voice phrase parser (T-109, FR-VOI-02/05, EC-30, EC-31,
/// domain-algorithms §9). Pure and deterministic: no I/O, no clock, never
/// throws. Categorization is a separate step (`categorizeVoiceItems`).
///
/// Pipeline: normalize, tokenize, find amount spans (digits or Egyptian /
/// English number words, with an optional currency), split the phrase into
/// items at the amount boundaries, drop verbs and fillers from the item
/// text. Amounts are exact rationals converted once to integer minor units
/// (half up; only a "third" can be inexact); no `double` anywhere.
library;

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../normalize/text_normalizer.dart';
import 'voice_lexicon.dart';
import 'voice_types.dart';

/// Most tokens read from one phrase (untrusted input cap).
const int _maxTokens = 300;

/// Largest value (in whole units) accepted from speech.
const int _maxUnits = 1000000000000;

/// Parses one spoken (or typed) phrase into items. [defaultCurrency] is the
/// user's primary currency, used when the speaker names none.
VoiceParseResult parseVoicePhrase(
  String input, {
  required Currency defaultCurrency,
}) {
  if (input.length > maxVoiceTextLength) {
    return const VoiceUnrecognized(VoiceUnrecognizedReason.tooLong);
  }
  final tokens = _tokenize(input);
  if (tokens.isEmpty) {
    return const VoiceUnrecognized(VoiceUnrecognizedReason.empty);
  }
  final spans = _findSpans(tokens);
  final items = spans.isEmpty
      ? _amountless(tokens, defaultCurrency)
      : _withSpans(tokens, spans, defaultCurrency);
  if (items.isEmpty) {
    return const VoiceUnrecognized(VoiceUnrecognizedReason.noContent);
  }
  return VoiceParsed(items);
}

// ---------------------------------------------------------------------------
// Tokens

final class _Tok {
  _Tok(this.raw, this.key, this.lex, this.digits);

  final String raw;
  final String key;
  final Lex? lex;

  /// Exact value of a digit token, else null.
  final _Q? digits;

  bool get latin {
    final c = key.codeUnitAt(0);
    return c >= 0x61 && c <= 0x7A;
  }

  bool is_(LexKind k) => lex?.kind == k;
}

final RegExp _tokenRe = RegExp(
  r'\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|[\p{L}\p{M}]+|[$€£₹₺﷼&]|[،,;؛]',
  unicode: true,
);
final RegExp _egpAbbrev = RegExp(
  r'ج\s*\.\s*م\.?|\bL\s*\.\s*E\.?',
  caseSensitive: false,
);

List<_Tok> _tokenize(String input) {
  final text = normalizeText(input).replaceAll(_egpAbbrev, ' جنيه ');
  final out = <_Tok>[];
  for (final m in _tokenRe.allMatches(text)) {
    final raw = m.group(0)!;
    final first = raw.codeUnitAt(0);
    if (first >= 0x30 && first <= 0x39) {
      final q = _digitsToQ(raw);
      if (q != null) out.add(_Tok(raw, raw, null, q));
      continue;
    }
    _addWord(out, raw);
    if (out.length > _maxTokens) break;
  }
  return out;
}

/// Adds [raw], splitting a glued `و` or `ب` in front of a number, currency
/// or fraction word (`وخمسين`, `بتلاتين`). A word that is itself known is
/// never split.
void _addWord(List<_Tok> out, String raw) {
  var rest = raw;
  for (var n = 0; n < 3; n++) {
    final key = foldKey(rest);
    if (key.length >= 3 && lexicon[key] == null) {
      final head = key[0];
      if (head == 'و' || head == 'ب') {
        final tail = foldKey(rest.substring(1));
        final lex = lexicon[tail];
        if (lex != null && _splittable(lex.kind)) {
          out.add(_Tok(head, head, lexicon[head], null));
          rest = rest.substring(1);
          continue;
        }
      }
    }
    break;
  }
  final key = foldKey(rest);
  if (key.isNotEmpty) out.add(_Tok(rest, key, lexicon[key], null));
}

bool _splittable(LexKind k) => switch (k) {
  LexKind.unit ||
  LexKind.teen ||
  LexKind.tens ||
  LexKind.hundred ||
  LexKind.hundredCompound ||
  LexKind.thousand ||
  LexKind.thousandDual ||
  LexKind.million ||
  LexKind.millionDual ||
  LexKind.fraction ||
  LexKind.currency ||
  LexKind.subunit => true,
  _ => false,
};

// ---------------------------------------------------------------------------
// Exact rationals (ints only)

final class _Q {
  const _Q(this.n, [this.d = 1]);

  final int n;
  final int d;

  _Q operator +(_Q o) => _Q(n * o.d + o.n * d, d * o.d);
  _Q times(int k) => _Q(n * k, d);
  _Q over(int k) => _Q(n, d * k);

  bool get isInt => n % d == 0;
  int get whole => n ~/ d;
}

_Q? _digitsToQ(String raw) {
  final text = raw.replaceAll(',', '');
  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final frac = dot < 0 ? '' : text.substring(dot + 1);
  if (whole.length > 12 || frac.length > 4) return null;
  var d = 1;
  for (var i = 0; i < frac.length; i++) {
    d *= 10;
  }
  return _Q(int.parse(whole + frac), d);
}

// ---------------------------------------------------------------------------
// Number words

final class _Num {
  const _Num(this.v, this.next);
  final int v;
  final int next;
}

bool _joiner(List<_Tok> t, int i) =>
    i < t.length &&
    t[i].is_(LexKind.conj) &&
    (t[i].key == 'و' || t[i].key == 'and');

_Num? _below100(List<_Tok> t, int i) {
  if (i >= t.length) return null;
  final x = t[i];
  switch (x.lex?.kind) {
    case LexKind.tens:
      var v = x.lex!.value;
      var j = i + 1;
      // English "twenty five".
      if (x.latin && j < t.length && t[j].is_(LexKind.unit) && t[j].latin) {
        v += t[j].lex!.value;
        j++;
      }
      return _Num(v, j);
    case LexKind.teen:
      return _Num(x.lex!.value, i + 1);
    case LexKind.unit:
      // Egyptian "خمسة وعشرين".
      if (_joiner(t, i + 1) && i + 2 < t.length && t[i + 2].is_(LexKind.tens)) {
        return _Num(x.lex!.value + t[i + 2].lex!.value, i + 3);
      }
      return _Num(x.lex!.value, i + 1);
    default:
      return null;
  }
}

_Num? _below1000(List<_Tok> t, int i) {
  if (i >= t.length) return null;
  final x = t[i];
  int? h;
  var j = i + 1;
  switch (x.lex?.kind) {
    case LexKind.hundredCompound:
      h = x.lex!.value;
    case LexKind.hundred:
      h = 100;
    case LexKind.unit when i + 1 < t.length && t[i + 1].is_(LexKind.hundred):
      h = x.lex!.value * 100;
      j = i + 2;
    case LexKind.article when i + 1 < t.length && t[i + 1].is_(LexKind.hundred):
      h = 100;
      j = i + 2;
    default:
      return _below100(t, i);
  }
  return _addRest(t, h, j, _below100);
}

/// `v` plus an optional lower part after "و"/"and" (or, for English words,
/// directly after).
_Num _addRest(
  List<_Tok> t,
  int v,
  int j,
  _Num? Function(List<_Tok>, int) lower,
) {
  if (_joiner(t, j)) {
    final r = lower(t, j + 1);
    if (r != null) return _Num(v + r.v, r.next);
  } else if (j < t.length && t[j].latin) {
    final r = lower(t, j);
    if (r != null) return _Num(v + r.v, r.next);
  }
  return _Num(v, j);
}

bool _isThousandWord(_Tok x) =>
    x.is_(LexKind.thousand) ||
    x.is_(LexKind.thousandPlural) ||
    x.is_(LexKind.kSuffix);

_Num? _belowMillion(List<_Tok> t, int i) {
  if (i >= t.length) return null;
  final x = t[i];
  if (x.is_(LexKind.thousand)) {
    return _addRest(t, 1000, i + 1, _below1000);
  }
  if (x.is_(LexKind.thousandDual)) {
    return _addRest(t, 2000, i + 1, _below1000);
  }
  final p = _below1000(t, i);
  if (p != null && p.next < t.length && _isThousandWord(t[p.next])) {
    return _addRest(t, p.v * 1000, p.next + 1, _below1000);
  }
  return p;
}

_Num? _wordsNumber(List<_Tok> t, int i) {
  if (i >= t.length) return null;
  final x = t[i];
  if (x.is_(LexKind.million)) return _addRest(t, 1000000, i + 1, _belowMillion);
  if (x.is_(LexKind.millionDual)) {
    return _addRest(t, 2000000, i + 1, _belowMillion);
  }
  final p = _belowMillion(t, i);
  if (p != null && p.next < t.length && t[p.next].is_(LexKind.million)) {
    return _addRest(t, p.v * 1000000, p.next + 1, _belowMillion);
  }
  return p;
}

// ---------------------------------------------------------------------------
// Amount spans

final class _Span {
  _Span({
    required this.start,
    required this.end,
    required this.value,
    required this.currency,
    required this.ambiguous,
    required this.prefixed,
    required this.words,
    required this.fraction,
  });

  final int start;
  final int end;
  final _Q value;
  final String? currency;
  final bool ambiguous;
  final bool prefixed;
  final bool words;
  final bool fraction;

  /// A small count that is probably a quantity, not a price.
  bool get small => value.isInt && value.whole <= 10;
}

List<_Span> _findSpans(List<_Tok> t) {
  final spans = <_Span>[];
  var i = 0;
  while (i < t.length) {
    final s = _spanAt(t, i);
    if (s == null) {
      i++;
    } else {
      spans.add(s);
      i = s.end;
    }
  }
  return _demoteQuantities(t, spans);
}

/// A bare small number that is not preceded by "and", has no currency, and
/// shares the phrase with a priced amount (currency word or `ب`) is a
/// quantity ("اشتريت اتنين قهوة بخمسين جنيه"), not an amount.
List<_Span> _demoteQuantities(List<_Tok> t, List<_Span> spans) {
  final anchored = spans.where((s) => s.currency != null || s.prefixed).length;
  if (anchored == 0) return spans;
  return [
    for (final s in spans)
      if (s.small &&
          s.currency == null &&
          !s.prefixed &&
          !s.ambiguous &&
          (s.start == 0 || !t[s.start - 1].is_(LexKind.conj)))
        ...const <_Span>[]
      else
        s,
  ];
}

bool _isCurrencyToken(_Tok x) => x.is_(LexKind.currency);

/// A currency written before the number: a symbol or an ISO code.
bool _currencyBefore(_Tok x) =>
    _isCurrencyToken(x) && (x.latin || x.key.length == 1) && x.key != 'ج';

_Span? _spanAt(List<_Tok> t, int i) {
  final x = t[i];
  final start = i;
  var j = i;
  var prefixed = false;
  String? cur;
  var ambiguous = false;

  if (x.key == 'ب' && i + 1 < t.length && _startsNumber(t[i + 1])) {
    prefixed = true;
    j = i + 1;
  } else if (_currencyBefore(x) &&
      i + 1 < t.length &&
      (t[i + 1].digits != null || _startsNumber(t[i + 1]))) {
    cur = x.lex!.code;
    ambiguous = x.lex!.ambiguous;
    j = i + 1;
  }
  final first = t[j];

  _Q? value;
  var end = j;
  var words = false;
  var fraction = false;

  if (first.digits != null) {
    var q = first.digits!;
    end = j + 1;
    if (end < t.length && _isThousandWord(t[end])) {
      q = q.times(1000);
      end++;
    } else if (end < t.length && t[end].is_(LexKind.million)) {
      q = q.times(1000000);
      end++;
    }
    value = q;
  } else if (first.is_(LexKind.fraction) && j + 1 < t.length) {
    // "ربع جنيه", "نص ميت", "ربع ألف".
    final nx = t[j + 1];
    final f = _Q(first.lex!.value, first.lex!.den);
    if (_isCurrencyToken(nx)) {
      value = f;
      end = j + 1;
      words = true;
      fraction = true;
    } else if (nx.is_(LexKind.hundred) || nx.is_(LexKind.thousand)) {
      value = f.times(nx.lex!.value);
      end = j + 2;
      words = true;
      fraction = true;
    }
  } else if (first.is_(LexKind.currency) && cur == null && !prefixed) {
    // Bare currency word: "جنيه ونص" is 1.5, "جنيهين" is 2.
    value = _Q(first.lex!.value);
    end = j; // the currency token is consumed below
    words = true;
  } else {
    final n = _wordsNumber(t, j);
    if (n != null) {
      value = _Q(n.v);
      end = n.next;
      words = true;
    }
  }
  if (value == null) return null;

  var sawCurrency = cur != null;
  // Currency after the number.
  if (cur == null && end < t.length && _isCurrencyToken(t[end])) {
    final c = t[end];
    cur = c.lex!.code;
    ambiguous = c.lex!.ambiguous;
    end++;
    if (c.lex!.sterling &&
        end < t.length &&
        t[end].key == foldKey('استرليني')) {
      cur = 'GBP';
      end++;
    }
    sawCurrency = true;
  }

  // Piasters: "خمسين قرش", "جنيه وخمسين قرش".
  if (!sawCurrency && end < t.length && t[end].is_(LexKind.subunit)) {
    value = value.over(100);
    cur = 'EGP';
    end++;
    return _finish(
      start,
      end,
      value,
      cur,
      ambiguous,
      prefixed,
      words,
      fraction,
    );
  }
  if (sawCurrency && cur == 'EGP' && _joiner(t, end)) {
    final sub = _subunitAfter(t, end + 1);
    if (sub != null) {
      value = value + sub.$1;
      end = sub.$2;
      fraction = true;
      return _finish(
        start,
        end,
        value,
        cur,
        ambiguous,
        prefixed,
        words,
        fraction,
      );
    }
  }

  // Fraction tail: "ميت ونص", "ألف وربع", "جنيه ونص".
  if (_joiner(t, end) &&
      end + 1 < t.length &&
      t[end + 1].is_(LexKind.fraction)) {
    final f = t[end + 1];
    final after = end + 2;
    final measure = after < t.length && t[after].is_(LexKind.measure);
    if (!measure) {
      final unit = sawCurrency ? 1 : _fractionUnit(value);
      value = value + _Q(f.lex!.value, f.lex!.den).times(unit);
      end = after;
      fraction = true;
      // "ألف ونص جنيه": the currency follows the fraction.
      if (!sawCurrency && end < t.length && _isCurrencyToken(t[end])) {
        cur = t[end].lex!.code;
        ambiguous = t[end].lex!.ambiguous;
        end++;
      }
    }
  }
  return _finish(start, end, value, cur, ambiguous, prefixed, words, fraction);
}

/// The unit a spoken fraction applies to: "ألف ونص" is 1500, "ميت ونص" is
/// 150, "عشرة ونص" is 10.5.
int _fractionUnit(_Q v) {
  if (!v.isInt) return 1;
  final w = v.whole;
  if (w >= 1000 && w % 1000 == 0) return 1000;
  if (w >= 100 && w % 100 == 0) return 100;
  return 1;
}

(_Q, int)? _subunitAfter(List<_Tok> t, int i) {
  if (i >= t.length) return null;
  if (t[i].is_(LexKind.subunit)) {
    return (_Q(t[i].lex!.value, 100), i + 1);
  }
  _Q? n;
  var j = i;
  if (t[i].digits != null) {
    n = t[i].digits;
    j = i + 1;
  } else {
    final w = _wordsNumber(t, i);
    if (w != null) {
      n = _Q(w.v);
      j = w.next;
    }
  }
  if (n != null && j < t.length && t[j].is_(LexKind.subunit)) {
    return (n.over(100), j + 1);
  }
  return null;
}

bool _startsNumber(_Tok x) {
  if (x.digits != null) return true;
  return switch (x.lex?.kind) {
    LexKind.unit ||
    LexKind.teen ||
    LexKind.tens ||
    LexKind.hundred ||
    LexKind.hundredCompound ||
    LexKind.thousand ||
    LexKind.thousandDual ||
    LexKind.million ||
    LexKind.millionDual ||
    LexKind.fraction ||
    LexKind.article ||
    LexKind.currency => true,
    _ => false,
  };
}

_Span? _finish(
  int start,
  int end,
  _Q value,
  String? cur,
  bool ambiguous,
  bool prefixed,
  bool words,
  bool fraction,
) {
  if (value.n <= 0 && value.d > 0) {
    // Zero is still a span (flagged invalid later).
  }
  return _Span(
    start: start,
    end: end,
    value: value,
    currency: cur,
    ambiguous: ambiguous,
    prefixed: prefixed,
    words: words,
    fraction: fraction,
  );
}

// ---------------------------------------------------------------------------
// Items

bool _noise(_Tok x) =>
    x.is_(LexKind.verb) ||
    x.is_(LexKind.stop) ||
    x.is_(LexKind.currency) ||
    x.is_(LexKind.subunit) ||
    x.is_(LexKind.kSuffix) ||
    x.key == 'ب' ||
    x.key == 'ثم';

bool _conj(_Tok x) => x.is_(LexKind.conj);

/// Words of [t] between [from] and [to] without verbs, fillers and edge
/// conjunctions. With [stripLeadingWa], a glued `و` in front of the first
/// word is removed ("وقهوة").
List<_Tok> _words(
  List<_Tok> t,
  int from,
  int to, {
  bool stripLeadingWa = false,
}) {
  final out = <_Tok>[];
  for (var i = from; i < to; i++) {
    if (!_noise(t[i])) out.add(t[i]);
  }
  while (out.isNotEmpty && _conj(out.first)) {
    out.removeAt(0);
  }
  while (out.isNotEmpty && _conj(out.last)) {
    out.removeLast();
  }
  if (stripLeadingWa && out.isNotEmpty) {
    final f = out.first;
    if (!f.latin &&
        f.digits == null &&
        f.key.length >= 4 &&
        f.key.startsWith('و') &&
        f.lex == null &&
        !waWords.contains(f.key)) {
      out[0] = _Tok(f.raw.substring(1), f.key.substring(1), null, null);
    }
  }
  return out;
}

String _display(List<_Tok> w) => w.map((x) => x.raw).join(' ');

String _matchText(List<_Tok> w) {
  final parts = <String>[];
  for (final x in w) {
    parts.add(x.raw);
    if (x.latin || x.digits != null || x.lex != null) continue;
    // Glued prefixes: و (and), لل / ل (to the), ب (with).
    final key = x.key;
    if (key.length >= 4 && key.startsWith('و') && !waWords.contains(key)) {
      parts.add(x.raw.substring(1));
    } else if (key.length >= 5 && key.startsWith('لل')) {
      parts.add(x.raw.substring(2));
    } else if (key.length >= 5 && (key[0] == 'ل' || key[0] == 'ب')) {
      parts.add(x.raw.substring(1));
    }
  }
  return parts.join(' ');
}

List<VoiceItem> _amountless(List<_Tok> slice, Currency cur) {
  final t = _splitGluedWa(slice);
  const from = 0;
  final to = t.length;
  final items = <VoiceItem>[];
  var chunkStart = from;
  void flush(int end) {
    final w = _words(t, chunkStart, end);
    if (w.isNotEmpty) {
      items.add(_item(null, w, null, false, false, false, false, cur));
    }
  }

  for (var i = from; i < to; i++) {
    if (_conj(t[i])) {
      flush(i);
      chunkStart = i + 1;
    }
  }
  flush(to);
  return items;
}

List<VoiceItem> _withSpans(List<_Tok> t, List<_Span> spans, Currency def) {
  final leading = _words(t, 0, spans.first.start);
  final textFirst = leading.isNotEmpty;
  final spoken = {
    for (final s in spans)
      if (s.currency != null) s.currency!,
  };
  final items = <VoiceItem>[];
  for (var k = 0; k < spans.length; k++) {
    final s = spans[k];
    final List<_Tok> w;
    if (textFirst) {
      final from = k == 0 ? 0 : spans[k - 1].end;
      w = _words(t, from, s.start, stripLeadingWa: k > 0);
    } else {
      final to = k + 1 < spans.length ? spans[k + 1].start : t.length;
      w = _words(t, s.end, to, stripLeadingWa: true);
    }
    // A phrase naming one currency for one item and none for another.
    final unspokenAmongSpoken =
        s.currency == null && spoken.any((c) => c != def.code);
    items.add(
      _item(
        s,
        w,
        s.currency,
        s.words,
        s.fraction,
        s.ambiguous,
        unspokenAmongSpoken,
        def,
      ),
    );
  }
  if (textFirst) {
    final tail = spans.last.end;
    // `_words` strips the edge; trailing chunks split at conjunctions.
    items.addAll(_amountless(t.sublist(tail), def));
  }
  return items;
}

VoiceItem _item(
  _Span? s,
  List<_Tok> w,
  String? code,
  bool words,
  bool fraction,
  bool ambiguous,
  bool unspokenAmongSpoken,
  Currency def,
) {
  final issues = <VoiceIssue>{};
  Money? money;
  var spoken = false;
  var conf = 0;
  if (s == null) {
    issues.add(VoiceIssue.missingAmount);
  } else {
    final cur = (code == null ? null : Currency.tryOf(code)) ?? def;
    spoken = code != null && Currency.tryOf(code) != null;
    money = _toMoney(s.value, cur);
    if (money == null) {
      issues.add(VoiceIssue.invalidAmount);
    } else {
      conf = fraction ? 900 : (words ? 950 : 1000);
    }
    if (ambiguous || (unspokenAmongSpoken && code == null)) {
      issues.add(VoiceIssue.ambiguousCurrency);
    }
  }
  if (w.isEmpty) issues.add(VoiceIssue.missingItemText);
  if (conf > 0) {
    if (w.isEmpty) conf -= 300;
    if (issues.contains(VoiceIssue.ambiguousCurrency)) conf -= 200;
  }
  return VoiceItem(
    amount: money,
    text: _display(w),
    matchText: _matchText(w),
    currencySpoken: spoken,
    issues: issues,
    confidencePermille: conf < 0 ? 0 : conf,
  );
}

/// Exact value to minor units; a non-terminating fraction rounds half up.
/// Null when zero, negative, too large or out of the Money range.
Money? _toMoney(_Q v, Currency c) {
  if (v.n <= 0 || v.d <= 0) return null;
  if (v.n ~/ v.d >= _maxUnits) return null;
  var scale = 1;
  for (var i = 0; i < c.exponent; i++) {
    scale *= 10;
  }
  final num = v.n * scale;
  final minor = (num * 2 + v.d) ~/ (v.d * 2);
  if (minor <= 0) return null;
  return Money.tryMinor(c, minor);
}

/// For text with no amount, a glued `و` in front of a word ("وتاكسي") is an
/// item boundary: returns a copy with it split into `و` and the word.
List<_Tok> _splitGluedWa(List<_Tok> t) {
  if (!t.any(_gluedWa)) return t;
  final out = <_Tok>[];
  for (final x in t) {
    if (_gluedWa(x)) {
      out.add(_Tok('و', 'و', lexicon['و'], null));
      out.add(_Tok(x.raw.substring(1), x.key.substring(1), null, null));
    } else {
      out.add(x);
    }
  }
  return out;
}

bool _gluedWa(_Tok x) =>
    !x.latin &&
    x.digits == null &&
    x.lex == null &&
    x.key.length >= 4 &&
    x.key.startsWith('و') &&
    !waWords.contains(x.key);
