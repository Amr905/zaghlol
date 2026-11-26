/// Reference masker (T-278, FR-LLM-18..20, D-92): replaces the user's own
/// accounts, cards, banks/wallets and merchants with placeholders before a
/// question leaves the phone. Pure, deterministic, total: it never throws
/// and never echoes a source name. Any unexpected error returns
/// [MaskUnresolved] (nothing is sent).
library;

import 'loose_text.dart';
import 'mask_models.dart';

final RegExp _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);
final RegExp _fourDigits = RegExp(r'(?<![0-9])[0-9]{4}(?![0-9])');
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

// Folded forms (ة -> ه, أ -> ا, ى -> ي).
const Set<String> _cardWords = {
  'كارت',
  'كارتي',
  'كارتات',
  'كروت',
  'كرت',
  'كارد',
  'بطاقه',
  'بطاقتي',
  'بطاقات',
  'فيزا',
  'ماستر',
  'ماستركارد',
  'ميزه',
  'حساب',
  'حسابي',
  'حسابات',
  'حسابك',
  'منتهي',
  'منتهيه',
  'ينتهي',
  'تنتهي',
  'card',
  'cards',
  'account',
  'accounts',
  'acct',
  'visa',
  'mastercard',
  'ending',
  'ends',
  'debit',
  'checking',
  'savings',
};
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

    int tokenAt(int pos) {
      for (var i = 0; i < tokens.length; i++) {
        if (pos >= tokens[i].start && pos < tokens[i].end) {
          return i;
        }
      }
      return -1;
    }

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
          // Start boundary: a word start, or a clitic prefix in front.
          var ts = s;
          while (ts > 0 && _isWordChar(f.codeUnitAt(ts - 1))) {
            ts--;
          }
          final prefix = f.substring(ts, s);
          if (!_clitics.contains(prefix)) {
            continue;
          }
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
    final digitCands = <int, String>{};
    for (final m in _fourDigits.allMatches(f)) {
      if (_decimalNeighbour(f, m.start, m.end)) {
        continue;
      }
      final ti = tokenAt(m.start);
      if (ti < 0) {
        continue;
      }
      var near = false;
      for (var d = -3; d <= 3; d++) {
        final j = ti + d;
        if (d != 0 && j >= 0 && j < tokens.length && cardish[j]) {
          near = true;
        }
      }
      if (!near) {
        continue;
      }
      final digits = m.group(0)!;
      final next = ti + 1 < tokens.length ? tokens[ti + 1].text : '';
      if (!lastFours.containsKey(digits) && _currencyWords.contains(next)) {
        continue; // an amount: «كارت 4321 جنيه» with no such card
      }
      if (inProtected(m.start, m.end)) {
        continue;
      }
      digitCands[m.start] = digits;
    }

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
    for (final e in digitCands.entries) {
      if (!free(e.key, e.key + 4)) {
        continue;
      }
      taken.add([e.key, e.key + 4]);
      spans.add(_Span(e.key, e.key + 4)..digits = e.value);
    }
    spans.sort((a, b) => a.start.compareTo(b.start));

    // «بنك X» / "bank X" with X unknown.
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (!_hasWord(tokens[i].text, _bankIntro)) {
        continue;
      }
      if (!free(tokens[i].start, tokens[i].end)) {
        continue; // the word is part of a masked name («بنك مصر»)
      }
      final n = tokens[i + 1];
      if (!free(n.start, n.end)) {
        continue;
      }
      final word = n.text;
      if (word.length < 2 ||
          _notBankName.contains(word) ||
          _hasWord(word, _cardWords) ||
          _hasWord(word, _bankWords) ||
          _currencyWords.contains(word) ||
          RegExp(r'^[0-9]+$').hasMatch(word) ||
          word.startsWith('ال') && _notBankName.contains(word.substring(2))) {
        continue;
      }
      return MaskUnresolved(MaskUnresolvedReason.unknownBank, accounts);
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

    return MaskResult(
      sentText: applyReplacements(text, folded, reps),
      map: MaskMap(map),
      tokens: tokenList,
    );
  }
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
