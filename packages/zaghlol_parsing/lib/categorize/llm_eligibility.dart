/// Decides whether an unknown merchant string may leave the phone for
/// automatic categorisation (T-355, FR-LCAT-05, BR-SYNC-04). Pure Dart: no
/// I/O; the word lists are injected ([NameLexicon]).
///
/// Design note. The rule is a conjunction of refusals, evaluated cheapest
/// first, and it fails closed:
/// - the caller states what kind of payment the text came from; anything but
///   a business payment (transfer, ATM/cash, income, unknown) is refused,
///   as is a `person`/`ipa`/`phone`/`own account`/`bank` counterparty and an
///   event category of cash/income/InstaPay, whatever the text says;
/// - the text is folded with the masker's `looseFold` (Arabic-Indic and
///   fullwidth digits, Persian letters, hamza forms, tatweel, harakat,
///   zero-width) and checked for identifiers: at least 4 consecutive digits,
///   at least 6 digits in total (any script, any separators), `@`, `+digit`,
///   e-mail/URL/domain shapes, IBAN shape, reference words next to digits.
///   This is stricter than the server's `ContributionPrivacy` (6 digits with
///   at most 3 separators), so an eligible string always passes it;
/// - person-like text is refused: an honorific with no business word, or
///   every token a given name (connectors such as abou/bin/ابو skipped) with
///   no business word. An empty lexicon refuses everything.
/// When unsure it refuses: a false "eligible" leaks a name, a false "not
/// eligible" only costs a suggestion. Accepted residuals: digits spelled as
/// words, look-alike letters used as digits, misspelled names that are not in
/// the list, a person's name that contains a business word.
/// Results are enums; the text is never returned, logged or put in an error.
library;

import '../chat/llm/loose_text.dart';
import 'types.dart';

/// Why a merchant string may not be sent. Stable names (safe to log).
enum LlmIneligibleReason {
  /// Not a business payment's merchant field (counterparty-sourced).
  notBusinessPayment,
  transfer,
  atmCash,
  income,
  personCounterparty,
  alreadyTried,
  badLength,
  identifier,
  personLike,

  /// The name lists were not loaded: fail closed.
  lexiconMissing,
}

/// What the transaction was, as decided by the caller.
enum LlmPaymentKind {
  /// Card / POS / online / wallet payment to a business (expense or refund).
  businessPayment,
  transfer,
  atmCash,
  income,

  /// Anything the caller could not classify: refused.
  unknown,
}

/// The result of [LlmEligibility.check].
sealed class LlmEligibility {
  const LlmEligibility();

  /// Runs every rule on [merchantNorm] (the string that would be sent).
  /// [triedBefore] answers "already sent or answered for this merchant".
  static LlmEligibility check(
    CategorizeInput input,
    String merchantNorm,
    NameLexicon lexicon, {
    required LlmPaymentKind kind,
    bool Function(String merchantNorm)? triedBefore,
  }) {
    switch (kind) {
      case LlmPaymentKind.businessPayment:
        break;
      case LlmPaymentKind.transfer:
        return const Ineligible(LlmIneligibleReason.transfer);
      case LlmPaymentKind.atmCash:
        return const Ineligible(LlmIneligibleReason.atmCash);
      case LlmPaymentKind.income:
        return const Ineligible(LlmIneligibleReason.income);
      case LlmPaymentKind.unknown:
        return const Ineligible(LlmIneligibleReason.notBusinessPayment);
    }
    final party = input.counterpartyKind;
    if (party == PartyKind.person) {
      return const Ineligible(LlmIneligibleReason.personCounterparty);
    }
    if (party != null && party != PartyKind.merchant) {
      return const Ineligible(LlmIneligibleReason.transfer);
    }
    final event = input.eventCategoryId;
    if (event != null) {
      if (event == 'sys:cash') {
        return const Ineligible(LlmIneligibleReason.atmCash);
      }
      if (event == 'sys:income') {
        return const Ineligible(LlmIneligibleReason.income);
      }
      if (event == 'sys:instapay') {
        return const Ineligible(LlmIneligibleReason.transfer);
      }
    }
    if (lexicon.isEmpty) {
      return const Ineligible(LlmIneligibleReason.lexiconMissing);
    }
    if (merchantNorm.length > maxLength) {
      return const Ineligible(LlmIneligibleReason.badLength);
    }
    final loose = looseFold(merchantNorm).text;
    if (loose.length < minLength) {
      return const Ineligible(LlmIneligibleReason.badLength);
    }
    if (_hasIdentifier(merchantNorm, loose)) {
      return const Ineligible(LlmIneligibleReason.identifier);
    }
    if (_looksLikePerson(loose, lexicon)) {
      return const Ineligible(LlmIneligibleReason.personLike);
    }
    // B94-m9: no counterparty kind from the caller: only a business word
    // makes the text trustworthy (fail closed).
    if (party == null && !_hasBusinessWord(loose, lexicon)) {
      return const Ineligible(LlmIneligibleReason.notBusinessPayment);
    }
    if (triedBefore != null && triedBefore(merchantNorm)) {
      return const Ineligible(LlmIneligibleReason.alreadyTried);
    }
    return const Eligible();
  }

  static const int minLength = 2;
  static const int maxLength = 64;

  bool get isEligible => this is Eligible;
}

final class Eligible extends LlmEligibility {
  const Eligible();
}

final class Ineligible extends LlmEligibility {
  const Ineligible(this.reason);
  final LlmIneligibleReason reason;
}

/// Injected word lists (the app loads the assets and passes the file text).
/// Entries are folded with `looseFold` so spelling variants match.
final class NameLexicon {
  NameLexicon({
    required Iterable<String> givenNames,
    required Iterable<String> honorifics,
    required Iterable<String> businessWords,
  }) : _names = {..._foldAll(givenNames), ..._foldAll(_builtinNames)},
       _assetHonorifics = _foldAll(honorifics),
       _honorifics = {..._foldAll(honorifics), ..._foldAll(_builtinHonorifics)},
       _business = _foldAll(businessWords);

  /// From the raw text of the three asset files (one entry per line).
  factory NameLexicon.fromLines({
    required String givenNames,
    required String honorifics,
    required String businessWords,
  }) => NameLexicon(
    givenNames: givenNames.split('\n'),
    honorifics: honorifics.split('\n'),
    businessWords: businessWords.split('\n'),
  );

  final Set<String> _names;
  final Set<String> _assetHonorifics;

  /// The asset list plus the built-in fallback set, so an out-of-date asset
  /// cannot open a gap (B94-M4).
  final Set<String> _honorifics;
  final Set<String> _business;

  /// True when a list that the rule depends on is missing (the built-in
  /// fallbacks do not count: a missing asset must still fail closed).
  bool get isEmpty => _names.isEmpty || _assetHonorifics.isEmpty;

  static Set<String> _foldAll(Iterable<String> src) => {
    for (final s in src)
      if (looseFold(s.trim()).text.isNotEmpty) looseFold(s.trim()).text,
  };
}

final RegExp _invisible = RegExp(r'[\p{Cc}\p{Cf}\p{Mn}\p{Me}]', unicode: true);
final RegExp _anyDigit = RegExp(r'[\p{Nd}\p{No}]', unicode: true);
final RegExp _digitRun4 = RegExp(r'[\p{Nd}\p{No}]{4}', unicode: true);
final RegExp _atSigns = RegExp('[@＠﹫]');
final RegExp _plusDigit = RegExp(r'\+\s*[\p{Nd}\p{No}]', unicode: true);
final RegExp _urlLike = RegExp(r'://|www|[a-z0-9-]+\.[a-z]{2,}');
final RegExp _dotLike = RegExp(
  r'[.:\u066B\u06D4\u2024\u2027\u3002\uFE52\uFF0E\uFF1A\uFF61]',
);
final RegExp _ibanShape = RegExp(r'[a-z]{2}[0-9]{2}[a-z0-9]{10,}');
final RegExp _refWord = RegExp(
  r'(^| )(ref|rrn|txn|trx|id|no|رقم|مرجع|حساب|كارت|بطاقه)( |$)',
);
final RegExp _handleWord = RegExp(r'instapay|انستاباي|انستا باي');
final RegExp _space = RegExp(' +');

bool _hasIdentifier(String raw, String loose) {
  final t = raw.replaceAll(_invisible, '');
  if (_atSigns.hasMatch(t) || _plusDigit.hasMatch(t)) {
    return true;
  }
  final digits = _anyDigit.allMatches(t).length;
  if (digits >= 6 || _digitRun4.hasMatch(t)) {
    return true;
  }
  var folded = 0;
  for (var i = 0; i < loose.length; i++) {
    final u = loose.codeUnitAt(i);
    if (u >= 0x30 && u <= 0x39) {
      folded++;
    }
  }
  if (folded >= 6 || _digitRun4.hasMatch(loose)) {
    return true;
  }
  if (loose.contains('@') || _handleWord.hasMatch(loose)) {
    return true;
  }
  // Dots survive only in the scrub fold (looseFold drops them).
  if (_dotLike.hasMatch(raw) && _urlLike.hasMatch(scrubFold(raw).text)) {
    return true;
  }
  if (loose.contains('www') || loose.contains('://')) {
    return true;
  }
  final compact = loose.replaceAll(' ', '');
  if (_ibanShape.hasMatch(compact)) {
    return true;
  }
  if (digits > 0 && _refWord.hasMatch(loose)) {
    return true;
  }
  return false;
}

/// Built-in fallback honorifics (folded at use). The asset is the full list.
const List<String> _builtinHonorifics = [
  'dr',
  'doctor',
  'doc',
  'eng',
  'engineer',
  'mr',
  'mrs',
  'ms',
  'miss',
  'mister',
  'madam',
  'madame',
  'mdm',
  'sir',
  'lady',
  'captain',
  'capt',
  'cpt',
  'sheikh',
  'sheik',
  'shaikh',
  'shaykh',
  'hag',
  'haj',
  'hajj',
  'hagg',
  'haga',
  'hajja',
  'hagga',
  'ostaz',
  'ostaza',
  'ustaz',
  'ustaza',
  'ostath',
  'prof',
  'professor',
  'bey',
  'basha',
  'pasha',
  'sitt',
  'دكتور',
  'دكتوره',
  'د',
  'م',
  'مهندس',
  'مهندسه',
  'باشمهندس',
  'حاج',
  'حاجه',
  'شيخ',
  'شيخه',
  'كابتن',
  'مدام',
  'استاذ',
  'استاذه',
  'انسه',
  'ا',
  'بيه',
  'باشا',
  'ست',
  'سيده',
  'استاذ',
  'بروفيسور',
];

/// Built-in extra names: compound second halves and common nicknames.
const List<String> _builtinNames = [
  'rahman',
  'rahim',
  'aziz',
  'fattah',
  'allah',
  'karim',
  'ghani',
  'hamid',
  'mido',
  'bebo',
  'zizo',
  'hamada',
  'toto',
  'koko',
  'fofa',
  'nono',
  'رحمن',
  'رحيم',
  'الله',
  'عزيز',
  'فتاح',
  'ميدو',
  'بيبو',
  'زيزو',
  'حمادة',
  'حماده',
  'توتو',
  'كوكو',
];

/// Prefixes that glue to the next token (Abd + X).
const Set<String> _abdWords = {
  'abd',
  'abdel',
  'abdul',
  'abdal',
  'abdol',
  'abdell',
  'عبد',
  'عبدال',
};

/// Prefixes that make the next token a name (Abou + X).
const Set<String> _kunya = {
  'abou',
  'abu',
  'abo',
  'ibn',
  'bin',
  'ben',
  'om',
  'um',
  'ابو',
  'ابن',
  'بن',
  'ام',
};

const Set<String> _connectors = {'el', 'al', 'ال'};

/// Transfer words: whatever follows must be a business word.
const Set<String> _transferWords = {
  'to',
  'from',
  'transfer',
  'transferred',
  'trf',
  'tf',
  'send',
  'sent',
  'received',
  'paid',
  'ipa',
  'wallet',
  'الي',
  'الى',
  'من',
  'تحويل',
  'حول',
  'ارسال',
  'محفظه',
  'استلام',
  'لحساب',
};

/// Wallet brand phrases (folded tokens).
const List<List<String>> _walletPhrases = [
  ['vodafone', 'cash'],
  ['orange', 'cash'],
  ['etisalat', 'cash'],
  ['we', 'pay'],
  ['فودافون', 'كاش'],
  ['اورانج', 'كاش'],
  ['اورنج', 'كاش'],
  ['اتصالات', 'كاش'],
];

final RegExp _maskedToken = RegExp(r'^[a-z]?x{2,}$|x{3,}|[*•#_]');
final RegExp _letter = RegExp(r'^\p{L}$', unicode: true);

bool _isBusinessToken(String t, NameLexicon lx) =>
    lx._business.contains(t) || lx._business.contains(_stripAl(t));

bool _hasBusinessWord(String loose, NameLexicon lx) {
  for (final t in loose.split(_space)) {
    if (t.isNotEmpty && _isBusinessToken(t, lx)) {
      return true;
    }
  }
  return false;
}

bool _looksLikePerson(String loose, NameLexicon lx) {
  final tokens = loose.split(_space).where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) {
    return true;
  }
  // Masked or initial forms: `A***`, `A.`, single letters, x-masking.
  for (final t in tokens) {
    if (_maskedToken.hasMatch(t) || _letter.hasMatch(t)) {
      return true;
    }
  }
  final isBiz = [for (final t in tokens) _isBusinessToken(t, lx)];
  final business = isBiz.contains(true);
  // Transfer words and wallet brands: anything after them that is not a
  // business word is refused.
  for (var i = 0; i < tokens.length; i++) {
    var after = -1;
    if (_transferWords.contains(tokens[i])) {
      after = i + 1;
    } else {
      for (final p in _walletPhrases) {
        if (i + p.length <= tokens.length &&
            [for (var k = 0; k < p.length; k++) tokens[i + k]].join(' ') ==
                p.join(' ')) {
          after = i + p.length;
        }
      }
    }
    if (after >= 0) {
      for (var j = after; j < tokens.length; j++) {
        if (!isBiz[j]) {
          return true;
        }
      }
    }
  }
  // Honorifics: refuse without a business word; with one, refuse when the
  // token that follows the honorific is not a business word (`صيدلية د. أحمد`).
  var honorific = false;
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (_attachedHonorific(t, lx)) {
      return true;
    }
    if (_isHonorific(t, lx)) {
      honorific = true;
      var j = i + 1;
      while (j < tokens.length &&
          (_connectors.contains(tokens[j]) || _isHonorific(tokens[j], lx))) {
        j++;
      }
      if (j < tokens.length && !isBiz[j]) {
        return true;
      }
    }
  }
  if (honorific && !business) {
    return true;
  }
  if (business) {
    return false;
  }
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (_abdWords.contains(t) || _isName(t, lx)) {
      return true;
    }
    if (_kunya.contains(t) && i + 1 < tokens.length) {
      return true;
    }
  }
  return false;
}

bool _isHonorific(String t, NameLexicon lx) {
  final s = _stripAl(t);
  if (lx._honorifics.contains(t) || lx._honorifics.contains(s)) {
    return true;
  }
  // Feminine forms: دكتورة -> دكتوره (folded) -> دكتور.
  return s.length > 3 &&
      s.endsWith('ه') &&
      lx._honorifics.contains(s.substring(0, s.length - 1));
}

String _stripAl(String t) {
  if (t.length > 3 && t.startsWith('ال')) {
    return t.substring(2);
  }
  return t;
}

bool _isName(String t, NameLexicon lx) {
  if (lx._names.contains(t)) {
    return true;
  }
  if ((t.startsWith('عبد') && t.length > 4) ||
      (t.length > 5 &&
          (t.startsWith('abdel') ||
              t.startsWith('abdul') ||
              t.startsWith('abdal')))) {
    return true;
  }
  final s = _stripAl(t);
  if (s != t && lx._names.contains(s)) {
    return true;
  }
  for (final p in const ['el', 'al']) {
    if (t.length > p.length + 2 &&
        t.startsWith(p) &&
        lx._names.contains(t.substring(p.length))) {
      return true;
    }
  }
  return false;
}

/// "Dr.Mona" folds to "drmona": a Latin honorific glued to a name.
bool _attachedHonorific(String t, NameLexicon lx) {
  final max = t.length - 2 < 12 ? t.length - 2 : 12;
  for (var n = 2; n <= max; n++) {
    if (lx._honorifics.contains(t.substring(0, n)) &&
        _isName(t.substring(n), lx)) {
      return true;
    }
  }
  return false;
}
