/// Reference masker (T-328, FR-LLM-18..20, D-92): replaces the user's own
/// accounts, cards, banks/wallets and merchants with placeholders before a
/// question leaves the phone. Pure, deterministic, total: it never throws
/// and never echoes a source name. Any unexpected error returns
/// [MaskUnresolved] (nothing is sent).
library;

import 'loose_text.dart';
import 'mask_models.dart';

final RegExp _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _forgedBracket = RegExp('⟦(PHONE|EMAIL|IPA|NUMBER)⟧|[⟦⟧]');

/// Arabic clitic prefixes that can sit in front of a name or word:
/// و/ف + ب/ل/ك + ال, and لل.
final Set<String> _clitics = () {
  final out = <String>{''};
  for (final conj in ['', 'و', 'ف']) {
    for (final prep in ['', 'ب', 'ل', 'ك']) {
      for (final art in ['', 'ال']) {
        out.add('$conj$prep$art');
      }
    }
    out.add([conj, 'لل'].join());
  }
  return out;
}();

// Card / account words, run through the same fold as the text.
final Set<String> _cardWords = {
  'كارت',
  'كارتي',
  'كارتات',
  'كروت',
  'كرت',
  'كارد',
  'كاردي',
  'بطاقة',
  'بطاقتي', //
  'بطاقات', 'فيزا', 'ماستر', 'ماستركارد', 'ماستركارت', 'ميزة', 'ميزه', //
  'كريديت', 'كريدت', 'كردت', 'كرديت', 'ديبت', 'دبت', 'بريبيد', 'ائتمان', //
  'ائتماني', 'ائتمانية', 'حساب', 'حسابي', 'حسابات', 'حسابك', 'منتهي', //
  'منتهية',
  'ينتهي',
  'تنتهي',
  'تنتهى',
  'آخره',
  'آخرها',
  'آخرو',
  'اخره',
  'اخرها', //
  'اخرو',
  'card',
  'cards',
  'account',
  'accounts',
  'acct',
  'visa',
  'mastercard', //
  'meeza', 'credit', 'debit', 'prepaid', 'ending', 'ends', //
  'digits', 'last4', 'checking', 'savings', 'amex', //
}.map(looseKey).toSet();
const Set<String> _bankWords = {
  'بنك',
  'بنكي',
  'بنوك',
  'bank',
  'banque',
  'محفظه',
  'محفظتي',
  'wallet',
};
const Set<String> _bankIntro = {'بنك', 'bank', 'banque'};
const Set<String> _currencyWords = {
  'جنيه',
  'جنية',
  'ج',
  'جم',
  'egp',
  'le',
  'pound',
  'pounds',
  'جنيهات',
  'دولار',
  'usd',
  'dollar',
  'dollars',
  'يورو',
  'eur',
  'ريال',
  'sar',
  'درهم',
  'aed',
};
// Words that may follow "bank" / «بنك» without naming a bank.
const Set<String> _notBankName = {
  'من',
  'في',
  'ف',
  'الي',
  'اللي',
  'بتاعي',
  'بتاعتي',
  'ده',
  'دي',
  'و',
  'او',
  'عن',
  'على',
  'علي',
  'مع',
  'ال',
  'كام',
  'قد',
  'ايه',
  'فين',
  'ليه',
  'رصيد',
  'تحويل',
  'كشف',
  'مصاريف',
  'عموله',
  'رسوم',
  'فايده',
  'فوايد',
  'قرض',
  'سلفه',
  'ايداع',
  'سحب',
  'ماكينه',
  'فرع',
  'اجازه',
  'اجازات',
  'of',
  'at',
  'in',
  'is',
  'for',
  'to',
  'the',
  'my',
  'and',
  'or',
  'on',
  'with',
  'from',
  'vs',
  'a',
  'an',
  'by',
  'this',
  'that',
  'last',
  'next',
  'statement',
  'transfer',
  'transfers',
  'fees',
  'fee',
  'charges',
  'balance',
  'holiday',
  'holidays',
  'loan',
  'deposit',
  'deposits',
  'withdrawal',
  'withdrawals',
  'interest',
  'branch',
  'atm',
  'how',
  'much',
  'what',
  'did',
  'i',
  'me',
  'was',
  'were',
  'it',
  'if',
  'than',
  'then',
  ...{'card', 'cards', 'account', 'accounts', 'كارت', 'حساب', 'حسابي'},
};

const Set<String> _bankConnectors = {'of', 'al', 'el', 'ال', 'de', 'du'};
const Set<String> _englishBankPrefix = {
  'which', 'your', 'our', 'any', 'other', 'same', 'new', 'old', 'each', //
  'every', 'some', 'central', 'savings', 'investment', 'commercial', 'about', //
  'no',
  'all',
  'both',
  'either',
  'whose',
  'their',
  'his',
  'her',
  'its',
  'one', //
  'another', 'first', 'second', 'online', 'mobile', 'digital', 'islamic', //
  'when', 'where', 'who', 'whom', 'because', 'since', 'while', 'so', 'but', //
  'not', 'also', 'just', 'only', 'even', 'now', 'again', 'here', 'there', //
};

/// Start offsets in folded [f] where [v] occurs as a whole name: it ends at a
/// word end and starts at a word start or behind an Arabic clitic prefix.
List<int> _nameHits(String f, String v) {
  final out = <int>[];
  if (v.isEmpty) {
    return out;
  }
  var from = 0;
  while (true) {
    final s = f.indexOf(v, from);
    if (s < 0) {
      break;
    }
    from = s + 1;
    final e = s + v.length;
    if (e < f.length && _isWordChar(f.codeUnitAt(e))) {
      continue;
    }
    var ts = s;
    while (ts > 0 && _isWordChar(f.codeUnitAt(ts - 1))) {
      ts--;
    }
    if (_clitics.contains(f.substring(ts, s))) {
      out.add(s);
    }
  }
  return out;
}

final class _DigitHit {
  const _DigitHit(this.start, this.end, this.digits);

  final int start;
  final int end;
  final String digits;
}

final RegExp _digitGroups = RegExp(r'[0-9]+(?: [0-9]+)*');

/// Last-4 candidates in folded text: a 4-digit token, or 2 to 4 adjacent
/// digit groups (`43 21`, `4 3 2 1`; `-` and `.` are already folded away or
/// into a space) that together make exactly 4 digits, within 3 words of a
/// card/account word. An amount (a currency word follows) is left alone
/// unless it equals one of the user's last-4s.
List<_DigitHit> _digitHits(
  String f,
  List<_Tok> tokens,
  List<bool> cardish,
  Map<String, List<MaskAccount>> lastFours,
  bool Function(int, int) inProtected,
) {
  final out = <_DigitHit>[];
  int tokenAt(int pos) {
    var lo = 0;
    var hi = tokens.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (pos < tokens[mid].start) {
        hi = mid - 1;
      } else if (pos >= tokens[mid].end) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  bool near(int ti, int tj) {
    for (var j = ti - 3; j <= tj + 3; j++) {
      if ((j < ti || j > tj) && j >= 0 && j < tokens.length && cardish[j]) {
        return true;
      }
    }
    return false;
  }

  for (final run in _digitGroups.allMatches(f)) {
    final groups = <List<int>>[
      for (final g in RegExp('[0-9]+').allMatches(run.group(0)!))
        [run.start + g.start, run.start + g.end],
    ];
    for (var a = 0; a < groups.length; a++) {
      var total = 0;
      for (var b = a; b < groups.length; b++) {
        total += groups[b][1] - groups[b][0];
        if (total > 4) {
          break;
        }
        if (total < 4) {
          continue;
        }
        final start = groups[a][0];
        final end = groups[b][1];
        if (a == b && _decimalNeighbour(f, start, end)) {
          break;
        }
        final ti = tokenAt(start);
        final tj = tokenAt(end - 1);
        if (ti < 0 || tj < 0 || !near(ti, tj) || inProtected(start, end)) {
          break;
        }
        final digits = f.substring(start, end).replaceAll(' ', '');
        final next = tj + 1 < tokens.length ? tokens[tj + 1].text : '';
        if (!lastFours.containsKey(digits) && _currencyWords.contains(next)) {
          break; // an amount: «كارت 4321 جنيه» with no such card
        }
        out.add(_DigitHit(start, end, digits));
        break;
      }
    }
  }
  return out;
}

bool _hasWord(String token, Set<String> words) {
  if (words.contains(token)) {
    return true;
  }
  for (final p in _clitics) {
    if (p.isNotEmpty &&
        token.length > p.length &&
        token.startsWith(p) &&
        words.contains(token.substring(p.length))) {
      return true;
    }
  }
  return false;
}

final class _Entity {
  const _Entity(this.kind, this.key, {this.account, this.institutionId});

  final MaskKind kind;
  final String key;
  final MaskAccount? account;
  final String? institutionId;
}

final class _Cand {
  _Cand(this.start, this.end, this.entity, {this.ordinary = false});

  int start;
  final int end;
  final _Entity entity;
  final bool ordinary;
}

final class _Tok {
  const _Tok(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

abstract final class ReferenceMasker {
  /// Masks [text] (already through `ClientScrub`). Returns a [MaskResult] or
  /// a [MaskUnresolved]; never throws.
  static MaskOutcome mask(String text, MaskSources sources) {
    try {
      return _mask(text, sources);
    } on Object {
      return const MaskUnresolved(MaskUnresolvedReason.failed, []);
    }
  }

  static MaskOutcome _mask(String input, MaskSources sources) {
    final accounts = List<MaskAccount>.of(sources.accounts);
    final institutions = List<MaskInstitution>.of(sources.institutions);
    final merchants = List<MaskMerchant>.of(sources.merchants);

    // Typed brackets other than our scrub tokens cannot reach the output.
    final text = input.replaceAllMapped(
      _forgedBracket,
      (m) => m.group(1) != null ? m.group(0)! : '',
    );
    final folded = looseFold(text);
    final f = folded.text;

    // Positions of scrub tokens in the folded text: fold the tokens too.
    final protectedFolded = <List<int>>[];
    for (final m in RegExp('⟦[a-z]+⟧').allMatches(f)) {
      protectedFolded.add([m.start, m.end]);
    }

    final tokens = <_Tok>[
      for (final m in _wordRun.allMatches(f)) _Tok(m.start, m.end, m.group(0)!),
    ];
    final cardish = [for (final t in tokens) _hasWord(t.text, _cardWords)];
    final bankish = [for (final t in tokens) _hasWord(t.text, _bankWords)];

    bool inProtected(int s, int e) =>
        protectedFolded.any((p) => s < p[1] && p[0] < e);

    bool nearBankWord(int s, int e) {
      var first = -1;
      var last = -1;
      for (var i = 0; i < tokens.length; i++) {
        if (tokens[i].end > s && tokens[i].start < e) {
          first = first < 0 ? i : first;
          last = i;
        }
      }
      if (first < 0) {
        return false;
      }
      for (var d = 1; d <= 2; d++) {
        final a = first - d;
        final b = last + d;
        if (a >= 0 && (cardish[a] || bankish[a])) {
          return true;
        }
        if (b < tokens.length && (cardish[b] || bankish[b])) {
          return true;
        }
      }
      return false;
    }

    final cands = <_Cand>[];

    void addName(String name, _Entity entity, {bool ordinary = false}) {
      final key = looseKey(name);
      if (key.length < 2) {
        return;
      }
      final variants = <String>{key};
      var stripped = false;
      if (key.startsWith('ال') && key.length - 2 >= 3) {
        variants.add(key.substring(2));
        stripped = true;
      }
      for (final v in variants) {
        final isStrippedVariant = stripped && v != key;
        for (final s in _nameHits(f, v)) {
          final e = s + v.length;
          var ts = s;
          while (ts > 0 && _isWordChar(f.codeUnitAt(ts - 1))) {
            ts--;
          }
          final prefix = f.substring(ts, s);
          var start = s;
          if (isStrippedVariant) {
            if (prefix.endsWith('ال')) {
              start = s - 2;
            } else if (prefix.endsWith('لل')) {
              start = s - 1;
            }
          }
          if (inProtected(start, e)) {
            continue;
          }
          if (ordinary && !nearBankWord(start, e)) {
            continue;
          }
          cands.add(_Cand(start, e, entity, ordinary: ordinary));
        }
      }
    }

    for (final a in accounts) {
      final entity = _Entity(MaskKind.account, 'a:${a.id}', account: a);
      for (final n in [a.label, ?a.nickname, ...a.extraNames]) {
        addName(n, entity);
      }
    }
    for (final i in institutions) {
      final entity = _Entity(MaskKind.bank, 'b:${i.id}', institutionId: i.id);
      for (final al in i.aliases) {
        addName(al.text, entity, ordinary: al.ordinaryWord);
      }
    }
    for (final m in merchants) {
      final entity = _Entity(MaskKind.merchant, 'm:${m.id}');
      for (final n in m.names) {
        addName(n, entity);
      }
    }

    // 4-digit tokens next to a card/account word.
    final lastFours = <String, List<MaskAccount>>{};
    for (final a in accounts) {
      final l = a.last4;
      if (l != null && l.length == 4) {
        lastFours.putIfAbsent(l, () => []).add(a);
      }
    }
    final digitCands = _digitHits(f, tokens, cardish, lastFours, inProtected);

    // Longest first, non-overlapping.
    final spans = <_Span>[];
    final byStart = <_Cand>[...cands];
    byStart.sort((a, b) {
      final c = (b.end - b.start).compareTo(a.end - a.start);
      return c != 0 ? c : a.start.compareTo(b.start);
    });
    final taken = <List<int>>[];
    bool free(int s, int e) => !taken.any((t) => s < t[1] && t[0] < e);
    final groups = <String, _Span>{};
    for (final c in byStart) {
      final k = '${c.start}:${c.end}';
      final existing = groups[k];
      if (existing != null) {
        existing.entities.add(c.entity);
        continue;
      }
      if (!free(c.start, c.end)) {
        continue;
      }
      taken.add([c.start, c.end]);
      final span = _Span(c.start, c.end)..entities.add(c.entity);
      groups[k] = span;
      spans.add(span);
    }
    for (final h in digitCands) {
      if (!free(h.start, h.end)) {
        continue;
      }
      taken.add([h.start, h.end]);
      spans.add(_Span(h.start, h.end)..digits = h.digits);
    }
    spans.sort((a, b) => a.start.compareTo(b.start));

    // «بنك X» / "bank X" / "bank of X" / "X bank" with X unknown.
    bool unknownName(String word) =>
        !(word.length < 2 ||
            _notBankName.contains(word) ||
            _hasWord(word, _cardWords) ||
            _hasWord(word, _bankWords) ||
            _currencyWords.contains(word) ||
            RegExp(r'^[0-9]+$').hasMatch(word) ||
            word.startsWith('ال') && _notBankName.contains(word.substring(2)));
    for (var i = 0; i < tokens.length; i++) {
      if (!_hasWord(tokens[i].text, _bankIntro)) {
        continue;
      }
      if (!free(tokens[i].start, tokens[i].end)) {
        continue; // the word is part of a masked name («بنك مصر»)
      }
      var j = i + 1;
      if (j < tokens.length && _bankConnectors.contains(tokens[j].text)) {
        j++;
      }
      if (j < tokens.length) {
        final n = tokens[j];
        if (free(n.start, n.end) && unknownName(n.text)) {
          return MaskUnresolved(MaskUnresolvedReason.unknownBank, accounts);
        }
      }
      // English "X bank".
      if (i > 0 && tokens[i].text == 'bank') {
        final p = tokens[i - 1];
        if (free(p.start, p.end) &&
            unknownName(p.text) &&
            !_englishBankPrefix.contains(p.text)) {
          return MaskUnresolved(MaskUnresolvedReason.unknownBank, accounts);
        }
      }
    }

    // Resolve and number.
    final counters = {for (final k in MaskKind.values) k: 0};
    final byEntity = <String, String>{};
    final map = <String, MaskTarget>{};
    final tokenList = <MaskedToken>[];
    final reps = <SpanReplacement>[];
    for (final s in spans) {
      final MaskKind kind;
      final String key;
      final MaskTarget target;
      if (s.digits != null) {
        final hits = lastFours[s.digits] ?? const [];
        if (hits.isEmpty) {
          return MaskUnresolved(
            MaskUnresolvedReason.noSuchCard,
            _cardsOrAll(accounts),
          );
        }
        if (hits.length > 1) {
          return MaskUnresolved(MaskUnresolvedReason.ambiguousCard, hits);
        }
        kind = MaskKind.card;
        key = 'card:${hits.first.id}';
        target = MaskTarget(kind: kind, accountIds: [hits.first.id]);
      } else {
        final best = MaskKind.values.firstWhere(
          (k) => s.entities.any((e) => e.kind == k),
        );
        final ents = {
          for (final e in s.entities)
            if (e.kind == best) e.key: e,
        }.values.toList();
        if (ents.length > 1) {
          return MaskUnresolved(MaskUnresolvedReason.ambiguousName, [
            for (final e in ents) ?e.account,
          ]);
        }
        final e = ents.first;
        kind = best;
        key = e.key;
        switch (kind) {
          case MaskKind.account:
            target = MaskTarget(kind: kind, accountIds: [e.account!.id]);
          case MaskKind.bank:
            final mine = [
              for (final a in accounts)
                if (a.institutionId == e.institutionId) a,
            ];
            if (mine.isEmpty) {
              return MaskUnresolved(
                MaskUnresolvedReason.bankWithoutAccount,
                accounts,
              );
            }
            target = MaskTarget(
              kind: kind,
              accountIds: [for (final a in mine) a.id],
              institutionId: e.institutionId,
            );
          case MaskKind.merchant:
            target = MaskTarget(kind: kind, merchantId: e.key.substring(2));
          case MaskKind.card:
            return const MaskUnresolved(MaskUnresolvedReason.failed, []);
        }
      }
      var placeholder = byEntity[key];
      if (placeholder == null) {
        final n = counters[kind]! + 1;
        counters[kind] = n;
        placeholder = '⟦${kind.name.toUpperCase()}_$n⟧';
        byEntity[key] = placeholder;
        map[placeholder] = target;
        tokenList.add(MaskedToken(kind, placeholder));
      }
      reps.add(SpanReplacement(s.start, s.end, placeholder));
    }

    final sent = applyReplacements(text, folded, reps);
    if (_leaks(sent, accounts, institutions, merchants)) {
      return const MaskUnresolved(MaskUnresolvedReason.failed, []);
    }
    return MaskResult(sentText: sent, map: MaskMap(map), tokens: tokenList);
  }

  /// Safety net: true when [sent] still holds a user account name, nickname,
  /// non-ordinary bank alias, merchant name, or a known last-4 next to a
  /// card word (same folding as the masker). Internal; exposed for tests.
  static bool leaksForTest(String sent, MaskSources sources) => _leaks(
    sent,
    List.of(sources.accounts),
    List.of(sources.institutions),
    List.of(sources.merchants),
  );
}

final RegExp _placeholderText = RegExp('⟦[A-Za-z]+(?:_[0-9]+)?⟧');

bool _leaks(
  String sent,
  List<MaskAccount> accounts,
  List<MaskInstitution> institutions,
  List<MaskMerchant> merchants,
) {
  final f = looseFold(sent.replaceAll(_placeholderText, ' ')).text;
  bool hasName(String name) {
    final key = looseKey(name);
    if (key.length < 2) {
      return false;
    }
    if (_nameHits(f, key).isNotEmpty) {
      return true;
    }
    return key.startsWith('ال') &&
        key.length - 2 >= 3 &&
        _nameHits(f, key.substring(2)).isNotEmpty;
  }

  for (final a in accounts) {
    if ([a.label, ?a.nickname, ...a.extraNames].any(hasName)) {
      return true;
    }
  }
  for (final i in institutions) {
    if (i.aliases.any((al) => !al.ordinaryWord && hasName(al.text))) {
      return true;
    }
  }
  for (final m in merchants) {
    if (m.names.any(hasName)) {
      return true;
    }
  }
  final lastFours = <String, List<MaskAccount>>{};
  for (final a in accounts) {
    final l = a.last4;
    if (l != null && l.length == 4) {
      lastFours.putIfAbsent(l, () => []).add(a);
    }
  }
  if (lastFours.isNotEmpty) {
    final tokens = <_Tok>[
      for (final m in _wordRun.allMatches(f)) _Tok(m.start, m.end, m.group(0)!),
    ];
    final cardish = [for (final t in tokens) _hasWord(t.text, _cardWords)];
    final hits = _digitHits(f, tokens, cardish, lastFours, (_, _) => false);
    if (hits.any((h) => lastFours.containsKey(h.digits))) {
      return true;
    }
  }
  return false;
}

final class _Span {
  _Span(this.start, this.end);

  final int start;
  final int end;
  final List<_Entity> entities = [];
  String? digits;
}

List<MaskAccount> _cardsOrAll(List<MaskAccount> accounts) {
  final cards = [
    for (final a in accounts)
      if (a.type.isCard) a,
  ];
  return cards.isEmpty ? accounts : cards;
}

bool _isWordChar(int u) {
  if (u >= 0x30 && u <= 0x39) {
    return true;
  }
  if (u >= 0x61 && u <= 0x7A) {
    return true;
  }
  if (u < 0x80) {
    return false;
  }
  return _letter.hasMatch(String.fromCharCode(u));
}

final RegExp _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// `12,4321` / `4321,50`: part of a larger number, not a last-4.
bool _decimalNeighbour(String f, int s, int e) {
  bool digit(int i) =>
      i >= 0 &&
      i < f.length &&
      f.codeUnitAt(i) >= 0x30 &&
      f.codeUnitAt(i) <= 0x39;
  bool sep(int i) => i >= 0 && i < f.length && (f[i] == ',' || f[i] == '٫');
  return (sep(s - 1) && digit(s - 2)) || (sep(e) && digit(e + 1));
}
