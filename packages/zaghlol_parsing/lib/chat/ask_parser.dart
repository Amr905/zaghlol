/// Ask Zaghlol question parser (T-110, FR-CHAT-01/03/05). Pure and
/// deterministic: no I/O, never throws, never echoes the question. It
/// scores weighted cues per intent, reads the period, currency, count and
/// the named category / merchant / card, and returns slots. It never
/// produces a figure: an unknown question is [AskUnrecognized] (FR-CHAT-03).
///
/// Cost: one pass over at most [maxAskTokens] words; the cue tables are
/// small and matching is plain token comparison (no regex backtracking).
library;

import '../categorize/jaro_winkler.dart';
import '../normalize/text_normalizer.dart';
import '../voice/voice_lexicon.dart';
import 'ask_grammar.dart';
import 'ask_types.dart';

/// Entities beyond this many per kind are ignored (untrusted size).
const int maxAskEntities = 3000;

final RegExp _wordRe = RegExp(r'[a-z0-9ء-ي]+');

AskParse parseAskQuestion(
  String input, {
  AskEntities entities = AskEntities.none,
}) {
  try {
    return _parse(input, entities);
  } on Object {
    // Never throws on garbage; the question is not echoed.
    return const AskUnrecognized(AskUnrecognizedReason.noIntent);
  }
}

AskParse _parse(String input, AskEntities entities) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const AskUnrecognized(AskUnrecognizedReason.empty);
  }
  if (trimmed.length > maxAskChars) {
    return const AskUnrecognized(AskUnrecognizedReason.tooLong);
  }
  final folded = foldKey(trimmed);
  final toks = <String>[
    for (final m in _wordRe.allMatches(folded)) m.group(0)!,
  ];
  if (toks.isEmpty) return const AskUnrecognized(AskUnrecognizedReason.empty);
  if (toks.length > maxAskTokens) toks.length = maxAskTokens;
  final vars = [for (final t in toks) _variants(t)];
  final n = toks.length;
  final consumed = List<bool>.filled(n, false);

  // -------------------------------------------------------- periods
  final periods = <AskPeriod>[];
  final numberAt = <int, int>{};
  for (var i = 0; i < n; i++) {
    final v = _numberValue(vars[i]);
    if (v != null) numberAt[i] = v;
  }
  var i = 0;
  while (i < n) {
    final r = _periodAt(toks, vars, numberAt, i);
    if (r == null) {
      i++;
      continue;
    }
    periods.add(r.period);
    for (var k = i; k < i + r.length; k++) {
      consumed[k] = true;
    }
    i += r.length;
  }

  // ------------------------------------------------------- currency
  String? currency;
  for (var k = 0; k < n && currency == null; k++) {
    for (final v in vars[k]) {
      final c = currencyWords[v];
      if (c != null) {
        currency = c;
        consumed[k] = true;
        break;
      }
    }
  }
  if (currency == null) {
    if (folded.contains(r'$')) {
      currency = 'USD';
    } else if (folded.contains('€')) {
      currency = 'EUR';
    } else if (folded.contains('£')) {
      currency = 'GBP';
    }
  }

  // ------------------------------------------------------- entities
  final stop = List<bool>.filled(n, false);
  var cardCue = false;
  for (var k = 0; k < n; k++) {
    if (vars[k].any(stopWords.contains)) stop[k] = true;
    if (vars[k].any(cardWords.contains)) {
      cardCue = true;
      stop[k] = true;
    }
  }
  final usable = <int>[
    for (var k = 0; k < n; k++)
      if (!consumed[k] && !stop[k] && !numberAt.containsKey(k)) k,
  ];
  final matchedTok = <int>{};

  final cat = _best(entities.categories, vars, usable, minScore: 800);
  final mer = _best(entities.merchants, vars, usable, minScore: 500);
  final acc = _best(
    entities.accounts,
    vars,
    usable,
    minScore: cardCue ? 500 : 1000,
  );
  String? categoryId;
  var merchantIds = <String>{};
  final accountIds = <String>{...?acc?.ids};
  if (acc != null) matchedTok.addAll(acc.tokens);
  if (mer != null && (cat == null || mer.score >= cat.score)) {
    merchantIds = mer.ids;
    matchedTok.addAll(mer.tokens);
  } else if (cat != null) {
    categoryId = cat.ids.first;
    matchedTok.addAll(cat.tokens);
  }

  final entityTok = <int>{...?cat?.tokens, ...?mer?.tokens};

  // ----------------------------------------------------------- cues
  final scores = <AskIntent, int>{};
  final thanCue = <int>[];
  var spendVerb = false;
  final order = [
    AskIntent.spend,
    ...AskIntent.values.where((x) => x != AskIntent.spend),
  ];
  for (final intent in order) {
    var s = 0;
    for (final cue in intentCues[intent]!) {
      final at = _find(vars, cue.words);
      if (at < 0) continue;
      // "صرفت كام على الفواتير": a word that names a category is not also
      // the cue of another intent once a spend verb is present.
      if (intent != AskIntent.spend &&
          spendVerb &&
          List.generate(
            cue.words.length,
            (k) => at + k,
          ).every(entityTok.contains)) {
        continue;
      }
      s += cue.weight;
      for (var k = 0; k < cue.words.length; k++) {
        consumed[at + k] = true;
      }
      if (intent == AskIntent.comparePeriods && _isThan(cue.words)) {
        thanCue.add(at);
      }
    }
    if (s > 0) scores[intent] = s;
    if (intent == AskIntent.spend && s >= 55) spendVerb = true;
  }

  // ------------------------------------------------------ intent pick
  final spend = scores[AskIntent.spend] ?? 0;
  var compare = scores[AskIntent.comparePeriods] ?? 0;
  if (periods.length >= 2 && spend > 0) compare += spend + 20;
  if (compare > 0 && compare != (scores[AskIntent.comparePeriods] ?? 0)) {
    scores[AskIntent.comparePeriods] = compare;
  }
  // "صرفت اكتر من الشهر اللي فات": a than-cue on a spend question compares.
  if (thanCue.isNotEmpty && spend > 0 && periods.isNotEmpty) {
    scores[AskIntent.comparePeriods] = spend + compare;
  }
  final ranked = scores.entries.toList()
    ..sort((a, b) {
      final c = b.value.compareTo(a.value);
      return c != 0 ? c : a.key.index.compareTo(b.key.index);
    });
  if (ranked.isEmpty || ranked.first.value < minIntentScore) {
    return const AskUnrecognized(AskUnrecognizedReason.noIntent);
  }
  if (ranked.length > 1 &&
      ranked.first.value - ranked[1].value < minIntentMargin) {
    return const AskUnrecognized(AskUnrecognizedReason.ambiguous);
  }
  final intent = ranked.first.key;
  final permille = ranked.first.value * 7 > 1000
      ? 1000
      : ranked.first.value * 7;

  // Something named that matches nothing: the answer would be about
  // something else, so there is none.
  if (intent == AskIntent.spend ||
      intent == AskIntent.comparePeriods ||
      intent == AskIntent.biggestExpense) {
    for (var k = 0; k < n; k++) {
      final isPrep = vars[k].any(targetPrepositions.contains);
      final isCard = vars[k].any(cardWords.contains);
      if (!isPrep && !isCard) continue;
      var j = k + 1;
      while (j < n &&
          (stop[j] || vars[j].any(targetPrepositions.contains)) &&
          !matchedTok.contains(j)) {
        j++;
      }
      if (j < n &&
          !consumed[j] &&
          !matchedTok.contains(j) &&
          !numberAt.containsKey(j) &&
          !stop[j]) {
        return const AskUnrecognized(AskUnrecognizedReason.unknownTarget);
      }
    }
  }

  // "balance of CIB": the name alone binds the account, no cue word needed.
  if (intent == AskIntent.accountBalance && accountIds.isEmpty) {
    final loose = _best(entities.accounts, vars, usable, minScore: 500);
    if (loose != null) {
      accountIds.addAll(loose.ids);
      matchedTok.addAll(loose.tokens);
    }
  }

  // A balance question that names something no account matches never gets
  // the all-accounts figure.
  if (intent == AskIntent.accountBalance && accountIds.isEmpty) {
    for (var j = 0; j < n; j++) {
      if (!consumed[j] &&
          !stop[j] &&
          !matchedTok.contains(j) &&
          !numberAt.containsKey(j) &&
          !vars[j].any(targetPrepositions.contains)) {
        return const AskUnrecognized(AskUnrecognizedReason.unknownTarget);
      }
    }
  }

  // ---------------------------------------------------------- limit
  int? limit;
  if (intent == AskIntent.topMerchants) {
    for (final e in numberAt.entries) {
      if (!consumed[e.key] && e.value >= 1 && e.value <= 50) {
        limit = e.value;
        break;
      }
    }
  }

  // --------------------------------------------------------- period
  AskPeriod? period;
  AskPeriod? compareWith;
  var defaulted = false;
  const monthNow = AskPeriod(AskPeriodKind.month);
  const monthPrev = AskPeriod(AskPeriodKind.month, offset: -1);
  switch (intent) {
    case AskIntent.accountBalance:
    case AskIntent.upcomingDues:
      period = null;
    case AskIntent.budgetRemaining:
      period = const AskPeriod(AskPeriodKind.cycle);
    case AskIntent.comparePeriods:
      if (periods.length >= 2) {
        period = periods[0];
        compareWith = periods[1];
      } else if (periods.length == 1) {
        final p = periods.single;
        if (thanCue.isNotEmpty && p.offset < 0) {
          period = AskPeriod(p.kind);
          compareWith = p;
        } else {
          period = p;
          compareWith = p.previous ?? monthPrev;
        }
      } else {
        period = monthNow;
        compareWith = monthPrev;
        defaulted = true;
      }
    default:
      if (periods.isNotEmpty) {
        period = periods.first;
      } else {
        period = monthNow;
        defaulted = true;
      }
  }

  final usesTarget =
      intent == AskIntent.spend ||
      intent == AskIntent.comparePeriods ||
      intent == AskIntent.biggestExpense;
  final usesAccount =
      usesTarget ||
      intent == AskIntent.accountBalance ||
      intent == AskIntent.topMerchants ||
      intent == AskIntent.savings;

  return AskUnderstood(
    intent,
    AskSlots(
      period: period,
      compareWith: compareWith,
      periodDefaulted: defaulted,
      categoryId: usesTarget ? categoryId : null,
      merchantIds: usesTarget ? merchantIds : const {},
      accountIds: usesAccount ? accountIds : const {},
      currencyCode: currency,
      limit: limit,
    ),
    permille,
  );
}

// ------------------------------------------------------------ helpers

/// The word itself plus forms without a glued article, preposition or
/// possessive, so `بكارت`, `الكارت` and `رصيدي` meet the cue words.
List<String> _variants(String t) {
  final out = <String>{t};
  void add(String s) {
    if (s.length >= 2) out.add(s);
  }

  var base = t;
  for (final p in const ['وبال', 'بال', 'وال', 'لل', 'ال']) {
    if (t.startsWith(p) && t.length > p.length + 1) {
      base = t.substring(p.length);
      add(base);
      if (p == 'لل') add('ل$base');
      break;
    }
  }
  if (base.length > 3 && 'بولفك'.contains(base[0])) add(base.substring(1));
  if (t.length > 3 && 'بولفك'.contains(t[0])) {
    add(t.substring(1));
    final rest = t.substring(1);
    if (rest.startsWith('ال') && rest.length > 3) add(rest.substring(2));
  }
  for (final v in out.toList()) {
    if (v.length > 4 && v.endsWith('ني')) add(v.substring(0, v.length - 2));
    if (v.length > 3 && v.endsWith('ي')) add(v.substring(0, v.length - 1));
    if (v.length > 4 && v.endsWith('ها')) add(v.substring(0, v.length - 2));
  }
  return out.toList();
}

bool _wordMatch(List<String> variants, String word) {
  if (word.endsWith('*')) {
    final p = word.substring(0, word.length - 1);
    return variants.any((v) => v.startsWith(p));
  }
  return variants.contains(word);
}

/// First index where [words] match consecutive tokens, or -1.
int _find(List<List<String>> vars, List<String> words) {
  if (words.isEmpty) return -1;
  for (var i = 0; i + words.length <= vars.length; i++) {
    var ok = true;
    for (var k = 0; k < words.length; k++) {
      if (!_wordMatch(vars[i + k], words[k])) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

final Set<String> _thanPhrases = {
  for (final p in [
    'اكتر من',
    'اقل من',
    'more than',
    'less than',
    'than last',
    'زياده عن',
  ])
    foldKey(p),
};

bool _isThan(List<String> words) => _thanPhrases.contains(words.join(' '));

/// A small number from digits or a spoken number word, else null.
int? _numberValue(List<String> variants) {
  for (final v in variants) {
    if (v.isNotEmpty && v.length <= 4 && RegExp(r'^[0-9]+$').hasMatch(v)) {
      return int.parse(v);
    }
    final lex = lexicon[v];
    if (lex != null &&
        (lex.kind == LexKind.unit ||
            lex.kind == LexKind.teen ||
            lex.kind == LexKind.tens)) {
      return lex.value;
    }
  }
  return null;
}

typedef _Span = ({AskPeriod period, int length});

AskPeriodKind? _unitOf(List<String> variants) {
  for (final v in variants) {
    final k = periodUnits[v];
    if (k != null) return k;
  }
  return null;
}

int _unitDays(AskPeriodKind k) => switch (k) {
  AskPeriodKind.day => 1,
  AskPeriodKind.week => 7,
  AskPeriodKind.month => 30,
  AskPeriodKind.year => 365,
  _ => 1,
};

final Map<String, AskPeriod> _phrasePeriods = {
  foldKey('من اول الشهر'): const AskPeriod(AskPeriodKind.month),
  foldKey('من اول السنه'): const AskPeriod(AskPeriodKind.year),
  foldKey('من اول الاسبوع'): const AskPeriod(AskPeriodKind.week),
  foldKey('since payday'): const AskPeriod(AskPeriodKind.cycle),
  foldKey('من اخر مرتب'): const AskPeriod(AskPeriodKind.cycle),
  foldKey('من يوم المرتب'): const AskPeriod(AskPeriodKind.cycle),
  foldKey('بعد المرتب'): const AskPeriod(AskPeriodKind.cycle),
  for (final p in [
    'من الاول',
    'من البدايه',
    'كل الوقت',
    'all time',
    'since the beginning',
    'لحد دلوقتي',
    'ever',
  ])
    foldKey(p): const AskPeriod(AskPeriodKind.allTime),
};

final List<({List<String> words, AskPeriod period})> _phraseList = [
  for (final e in _phrasePeriods.entries)
    (words: e.key.split(' '), period: e.value),
]..sort((a, b) => b.words.length.compareTo(a.words.length));

const Set<String> _nextWords = {'جاي', 'القادم', 'قادم', 'next', 'جايه', 'جاى'};

bool _isNext(List<String> v) => v.any(_nextWords.contains);

_Span? _periodAt(
  List<String> toks,
  List<List<String>> vars,
  Map<int, int> numberAt,
  int i,
) {
  final n = toks.length;
  // Multi-word phrases first.
  for (final p in _phraseList) {
    if (i + p.words.length > n) continue;
    var ok = true;
    for (var k = 0; k < p.words.length; k++) {
      if (!_wordMatch(vars[i + k], p.words[k])) {
        ok = false;
        break;
      }
    }
    if (ok) return (period: p.period, length: p.words.length);
  }
  // Single words: today, yesterday.
  for (final v in vars[i]) {
    final w = periodWords[v];
    if (w != null) {
      return (period: AskPeriod(w.kind, offset: w.offset), length: 1);
    }
  }
  // "اول امبارح": the day before yesterday.
  if (toks[i] == foldKey('اول') && i + 1 < n) {
    for (final v in vars[i + 1]) {
      if (v == foldKey('امبارح')) {
        return (
          period: const AskPeriod(AskPeriodKind.day, offset: -2),
          length: 2,
        );
      }
    }
  }
  // Dual words: two days / weeks / months.
  for (final v in vars[i]) {
    final d = dualUnits[v];
    if (d != null) {
      final days = (2 * _unitDays(d)).clamp(1, 366);
      return (
        period: AskPeriod(AskPeriodKind.lastDays, count: days),
        length: 1,
      );
    }
  }
  // Month names, with an optional year; a preceding `شهر` joins the span.
  for (final v in vars[i]) {
    final m = monthNames[v];
    if (m == null) continue;
    if (v == 'may') {
      final prev = i > 0 ? toks[i - 1] : '';
      if (!const {'in', 'of', 'during', 'for', 'last', 'this'}.contains(prev)) {
        continue;
      }
    }
    int? year;
    var len = 1;
    if (i + 1 < n && numberAt[i + 1] != null) {
      final y = numberAt[i + 1]!;
      if (toks[i + 1].length == 4 && y >= 2000 && y <= 2100) {
        year = y;
        len = 2;
      }
    }
    return (
      period: AskPeriod(AskPeriodKind.monthOfYear, month: m, year: year),
      length: len,
    );
  }
  // "last N <unit>" / "اخر N <unit>" and "last <unit>".
  if (vars[i].any(lastCountWords.contains)) {
    var j = i + 1;
    int? count;
    if (j < n && numberAt[j] != null) {
      count = numberAt[j];
      j++;
    }
    if (j < n) {
      final unit = _unitOf(vars[j]);
      if (unit != null) {
        if (count != null) {
          if (unit == AskPeriodKind.cycle) {
            return null;
          }
          final days = (count * _unitDays(unit)).clamp(1, 366);
          return (
            period: AskPeriod(AskPeriodKind.lastDays, count: days),
            length: j - i + 1,
          );
        }
        // "last month": the previous one.
        return (period: AskPeriod(unit, offset: -1), length: 2);
      }
    }
    return null;
  }
  // "this <unit>", "next <unit>".
  if (i + 1 < n &&
      (toks[i] == 'this' || toks[i] == 'current' || toks[i] == 'next')) {
    final u = _unitOf(vars[i + 1]);
    if (u != null) {
      return (
        period: AskPeriod(u, offset: toks[i] == 'next' ? 1 : 0),
        length: 2,
      );
    }
  }
  final unit = _unitOf(vars[i]);
  if (unit != null) {
    // "شهر يناير": the month name carries the period.
    if (unit == AskPeriodKind.month &&
        i + 1 < n &&
        vars[i + 1].any(monthNames.containsKey)) {
      return null;
    }
    if (i > 0) {
      final prev = toks[i - 1];
      if (prev == 'this' || prev == 'current') {
        return (period: AskPeriod(unit), length: 1);
      }
      if (prev == 'next') {
        return (period: AskPeriod(unit, offset: 1), length: 1);
      }
      if (prev == 'last' || prev == 'previous' || prev == 'past') {
        // Handled by the "last" branch at i - 1 when it is a period start.
        return (period: AskPeriod(unit, offset: -1), length: 1);
      }
    }
    for (var j = i + 1; j < n && j <= i + 3; j++) {
      if (_unitOf(vars[j]) != null) break;
      if (vars[j].any(lastWords.contains)) {
        return (period: AskPeriod(unit, offset: -1), length: j - i + 1);
      }
      if (vars[j].any(thisWords.contains)) {
        return (period: AskPeriod(unit), length: j - i + 1);
      }
      if (_isNext(vars[j])) {
        return (period: AskPeriod(unit, offset: 1), length: j - i + 1);
      }
    }
    if (unit != AskPeriodKind.day && toks[i].length > 1) {
      // A bare "الشهر" / "السنة": the current one.
      return (period: AskPeriod(unit), length: 1);
    }
  }
  return null;
}

typedef _Match = ({Set<String> ids, int score, Set<int> tokens});

/// The best-scoring entities (all ties kept) at or above [minScore].
_Match? _best(
  List<AskEntity> list,
  List<List<String>> vars,
  List<int> usable, {
  required int minScore,
}) {
  if (list.isEmpty || usable.isEmpty) return null;
  var top = 0;
  final ids = <String>[];
  final toksOf = <String, Set<int>>{};
  final capped = list.length > maxAskEntities
      ? list.sublist(0, maxAskEntities)
      : list;
  for (final e in capped) {
    var best = 0;
    var bestToks = <int>{};
    for (final name in e.names) {
      final nt = [
        for (final m in _wordRe.allMatches(foldKey(name))) m.group(0)!,
      ].where((w) => !_genericName.contains(w)).toList();
      if (nt.isEmpty || nt.length > 12) continue;
      var hit = 0;
      final used = <int>{};
      for (final w in nt) {
        final at = _tokenFor(w, vars, usable);
        if (at >= 0) {
          hit++;
          used.add(at);
        }
      }
      if (hit == 0) continue;
      if (!e.partial && hit < nt.length) continue;
      final s = hit * 1000 ~/ nt.length;
      if (s > best) {
        best = s;
        bestToks = used;
      }
    }
    if (best < minScore) continue;
    if (best > top) {
      top = best;
      ids
        ..clear()
        ..add(e.id);
      toksOf
        ..clear()
        ..[e.id] = bestToks;
    } else if (best == top) {
      ids.add(e.id);
      toksOf[e.id] = bestToks;
    }
  }
  if (ids.isEmpty) return null;
  return (
    ids: ids.toSet(),
    score: top,
    tokens: {for (final s in toksOf.values) ...s},
  );
}

const Set<String> _genericName = {
  'card',
  'كارت',
  'حساب',
  'account',
  'bank',
  'بنك',
};

/// The usable token index that equals [w] (any variant) or is close to it.
int _tokenFor(String w, List<List<String>> vars, List<int> usable) {
  for (final k in usable) {
    if (vars[k].contains(w)) return k;
  }
  if (w.length >= 5) {
    for (final k in usable) {
      for (final v in vars[k]) {
        if (v.length >= 5 &&
            v.codeUnitAt(0) == w.codeUnitAt(0) &&
            jaroWinklerScore(v, w) >= 920000) {
          return k;
        }
      }
    }
  }
  return -1;
}
