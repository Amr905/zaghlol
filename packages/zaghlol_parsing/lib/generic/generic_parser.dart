import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../registry/registry_models.dart';
import 'generic_keywords.dart';

/// Heuristic parser for messages no template reads (parsing-engine §7,
/// FR-PAR-13): unknown financial senders, and known banks whose wording no
/// template covers. Pure, total and linear: no regex with nested
/// quantifiers, no I/O, no logging. The result never carries message text
/// beyond the extracted fields.
///
/// Field extractors work on any wording, Arabic or English, in any order:
/// - amount and currency: a number with a currency marker touching it
///   (symbol, prefixed symbol, ISO code or AR/EN word, before or after);
///   amounts after a balance or limit word are skipped; among the rest the
///   one nearest a transaction cue wins;
/// - direction and event from keyword cues near the amount;
/// - last-4 after a card/account/mask cue;
/// - merchant after `at/to/from/لدى/في/الى/من` up to a stop word;
/// - date (`dd/MM[/yyyy]`, `yyyy-MM-dd`, `09 Nov`), reference after `Ref`.
///
/// Conservative: a field with no cue stays null, nothing is guessed, and the
/// confidence never reaches the auto-accept threshold.
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
  String? institutionCode,
}) {
  final t = folded.text;
  if (_hits(t, declineKeywords, null).isNotEmpty) {
    return const ParseUnrecognized(UnrecognizedReason.genericDeclined);
  }
  if (_hits(t, promoKeywords, null).isNotEmpty &&
      _hits(t, completedTransactionCues, null).isEmpty) {
    return const ParseUnrecognized(UnrecognizedReason.genericPromotion);
  }
  // An OTP message that also carries an amount ("Your OTP for the purchase of
  // EGP 1,250.00 at X is 483920"): the code, not a spend. Needs both the cue
  // and a code that follows "is"/":" in the same sentence as the cue, so a
  // transaction with an "OTP" footer (and e.g. "Balance: 15000") still parses.
  if (_otpWithCode.hasMatch(t)) {
    return const ParseUnrecognized(UnrecognizedReason.genericPromotion);
  }
  final directional = [
    ..._hits(
      t,
      expenseKeywords,
      TemplateDirection.expense,
    ).where((h) => !_addressedToReader(t, h)),
    ..._hits(t, incomeKeywords, TemplateDirection.income),
  ];
  final hits = [...directional, ..._hits(t, amountCueKeywords, null)];
  final allCandidates = _candidates(t, hits);
  // A foreign amount shown beside the charge (`EGP 3,400.00 (EUR 100.00)`,
  // `Original USD 20.00`) is the original amount, never the charge: it leaves
  // the amount ranking and is reported as `originalAmount` (registry FX rule).
  final foreign = allCandidates.where((c) => _isForeignCue(t, c)).toList();
  final charged = allCandidates.where((c) => !_isForeignCue(t, c)).toList();
  final candidates = charged.isEmpty ? allCandidates : charged;
  if (candidates.isEmpty) {
    return const ParseUnrecognized(UnrecognizedReason.genericNoAmount);
  }

  // Amount: the candidate nearest a transaction cue; first on a tie.
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
  Money? originalAmount;
  if (charged.isNotEmpty) {
    for (final f in foreign) {
      if (f.money.currency != best.money.currency) {
        originalAmount = f.money;
        break;
      }
    }
  }
  if (ranked.any((r) => r.$1.money.currency != best.money.currency)) {
    reasons.add(GenericReason.currencyAmbiguous);
  }

  // Direction: the nearest keyword; opposite keywords close together cancel.
  // A credit-card settlement (SMS-AUTO) names its own side and is a transfer
  // between the user's accounts, so the "payment"/"received" keywords that
  // would cancel each other do not decide it.
  final settlement = _settlement(t);
  final expenseDistance = _nearest(
    best,
    directional,
    TemplateDirection.expense,
  );
  final incomeDistance = _nearest(best, directional, TemplateDirection.income);
  TemplateDirection? direction;
  if (settlement != null && _hits(t, _spendOrReversalCues, null).isNotEmpty) {
    // A settlement phrase beside a purchase or reversal cue: never guess.
    reasons.add(GenericReason.directionConflict);
  } else if (settlement != null) {
    direction = settlement;
  } else if (expenseDistance == _far && incomeDistance == _far) {
    reasons.add(GenericReason.directionUnknown);
  } else if (expenseDistance != _far &&
      incomeDistance != _far &&
      (expenseDistance - incomeDistance).abs() <= _conflictChars) {
    reasons.add(GenericReason.directionConflict);
  } else if (expenseDistance < incomeDistance &&
      _hits(t, _reversalCues, null).isNotEmpty) {
    // `payment ... was reversed`: a spend word beside a reversal is unclear.
    reasons.add(GenericReason.directionConflict);
  } else {
    direction = expenseDistance < incomeDistance
        ? TemplateDirection.expense
        : TemplateDirection.income;
  }
  final event = direction == null
      ? null
      : settlement != null
      ? GenericEvent.ccPayment
      : _event(t, best, direction);

  final last4 = _last4(t, globalLast4);
  final merchant = _merchant(folded, body, cleaning);
  if (last4 == null && merchant == null) {
    reasons.add(GenericReason.sparseFields);
  }
  final date = _withClock(t, _messageDate(t, receivedAt));
  final reference = _reference(folded, body);

  final ordered = reasons.toList()..sort((a, b) => a.index.compareTo(b.index));
  var confidence = kGenericMaxConfidencePermille;
  for (final r in ordered) {
    confidence = confidence * r.factorPermille ~/ 1000;
  }

  final scores = <GenericField, int>{
    GenericField.amount: reasons.contains(GenericReason.amountAmbiguous)
        ? 500
        : ranked.first.$2 <= _closeChars
        ? 900
        : 700,
    GenericField.currency: reasons.contains(GenericReason.currencyAmbiguous)
        ? 400
        : best.symbolMarker
        ? 850
        : 950,
    if (direction != null)
      GenericField.direction:
          (direction == TemplateDirection.expense
                  ? expenseDistance
                  : incomeDistance) <=
              _closeChars
          ? 900
          : 750,
    if (last4 != null) GenericField.last4: last4.$2 ? 950 : 850,
    if (merchant != null) GenericField.merchant: merchant.$2 ? 850 : 700,
    if (date != null) GenericField.date: date.$2 ? 900 : 800,
    if (reference != null) GenericField.reference: 850,
  };
  GenericSpan span(int s, int e) =>
      GenericSpan(folded.origin[s], folded.origin[e - 1] + 1);
  final spans = <GenericField, GenericSpan>{
    GenericField.amount: span(best.numStart, best.numEnd),
    GenericField.currency: span(best.curStart, best.curEnd),
    if (last4 != null) GenericField.last4: span(last4.$3, last4.$3 + 4),
    if (merchant != null) GenericField.merchant: span(merchant.$3, merchant.$4),
    if (date != null) GenericField.date: span(date.$3, date.$4),
    if (reference != null) GenericField.reference: reference.$2,
  };

  return ParseGeneric(
    language: language,
    amount: best.money,
    originalAmount: originalAmount,
    direction: direction,
    last4: last4?.$1,
    merchant: merchant?.$1,
    occurredAt: date?.$1 ?? receivedAt,
    dateRead: date != null,
    event: event,
    reference: reference?.$1,
    institutionCode: institutionCode,
    confidencePermille: confidence.clamp(0, kGenericMaxConfidencePermille),
    reasons: ordered,
    fieldConfidence: Map.unmodifiable(scores),
    spans: Map.unmodifiable(spans),
  );
}

final RegExp _foreignLead = RegExp(
  r'(?:\b(?:original|foreign)\w*[:\s]*|الاصلي[:\s]*)$',
);

/// True only after an explicit `original` / `foreign` / `الاصلي` cue. Brackets
/// and `equivalent` / `approx` / `يعادل` often mark the converted amount, so
/// they stay ambiguous (D-28).
bool _isForeignCue(String t, _Candidate c) {
  final from = c.start < 24 ? 0 : c.start - 24;
  return _foreignLead.hasMatch(t.substring(from, c.start));
}

/// A cue this close (characters) to the amount counts as adjacent.
const int _closeChars = 24;

/// The event whose keyword sits nearest the amount, within the window.
/// Refund only for income, purchase and withdrawal only for expense.
/// SMS-AUTO: the side of a credit-card settlement the message describes, or
/// null when it is not one (or names both sides). A card word is required;
/// the received side needs a "payment received/credited/posted" cue and no
/// debit word, the paying side a "card payment/bill" cue and a debit word.
TemplateDirection? _settlement(String t) {
  if (_hits(t, cardWords, null).isEmpty) return null;
  final debit = _hits(t, cardSettlementDebitWords, null).isNotEmpty;
  final received =
      !debit &&
      (_hits(t, cardSettlementReceivedCues, null).isNotEmpty ||
          _paymentNearReceivedVerb(t));
  final paid = debit && _hits(t, cardSettlementPaidCues, null).isNotEmpty;
  if (received == paid) return null;
  return received ? TemplateDirection.income : TemplateDirection.expense;
}

/// `Payment of EGP 5,000 received on your card`: a payment word with a
/// received/credited/posted verb right after it (no thanks-only wording).
bool _paymentNearReceivedVerb(String t) {
  final verbs = _hits(t, cardSettlementReceivedVerbs, null).where(
    (v) => !t.startsWith('thank', v.start) && !t.startsWith('شكرا', v.start),
  );
  for (final p in _hits(t, _paymentWords, null)) {
    if (verbs.any((v) => v.start >= p.end && v.start - p.end <= 40)) {
      return true;
    }
  }
  return false;
}

final List<String> _paymentWords = ['payment', 'repayment', 'سداد', 'دفعه'];

final List<String> _reversalCues = ['reversed', 'reversal'];

final List<String> _spendOrReversalCues = const [
  'purchase',
  'purchased',
  'was used',
  'has been used',
  'used for',
  'spent',
  'withdrawal',
  'reversed',
  'reversal',
  'refund',
  'refunded',
  'شراء',
  'مشتريات',
  'استرداد',
  'مرتجع',
].map(foldKey).toList();

GenericEvent? _event(String t, _Candidate c, TemplateDirection direction) {
  GenericEvent? best;
  var bestDistance = genericEventWindow + 1;
  for (final (event, words) in eventKeywords) {
    if (direction == TemplateDirection.income &&
        (event == GenericEvent.purchase || event == GenericEvent.withdrawal)) {
      continue;
    }
    if (direction == TemplateDirection.expense &&
        event == GenericEvent.refund) {
      continue;
    }
    final d = _nearest(c, _hits(t, words, null), null);
    if (d < bestDistance) {
      best = event;
      bestDistance = d;
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Dates.

const Map<String, int> _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  'يناير': 1, 'فبراير': 2, 'مارس': 3, 'ابريل': 4, 'مايو': 5, 'يونيو': 6,
  'يوليو': 7, 'اغسطس': 8, 'سبتمبر': 9, 'اكتوبر': 10, 'نوفمبر': 11,
  'ديسمبر': 12,
};

// `d/M[/yyyy|/yy]` (also `-` and `.` with a year), and `yyyy-MM-dd`.
final RegExp _otpWithCode = RegExp(
  r'(?:^|[^a-z])(?:[o0]tp|one[- ]?time[- ]?(?:pass(?:word|code)|pin|code))'
  r'(?:[^.!?;\n]|\.(?=[0-9])){0,80}?'
  r'(?<!ref|reference|ref no|no|number)(?:\bis|[:=#]) ?[0-9]{4,8}'
  r'(?:$|[^0-9.,]|[.,]$|[.,][^0-9])',
);
final RegExp _numericDate = RegExp(
  r'(?<![0-9/.:-])(?:(20[0-9]{2})-([0-9]{1,2})-([0-9]{1,2})|([0-9]{1,2})/([0-9]{1,2})(?:/(20[0-9]{2}|[0-9]{2}))?|([0-9]{1,2})([.-])([0-9]{1,2})\8(20[0-9]{2}))(?![0-9/:])',
);

// `09 Nov[ 2026]`, `09-Nov-2026`, `Nov 09[, 2026]`, `٩ نوفمبر`.
const String _monthWord =
    '(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
    'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|'
    r'dec(?:ember)?)\.?(?![a-z])';

final RegExp _namedDate = RegExp(
  r'(?<![0-9a-z])(?:([0-9]{1,2})[ -]' +
      _monthWord +
      r'(?:[ ,-]{1,2}(20[0-9]{2}))?|' +
      _monthWord +
      r' ([0-9]{1,2})(?:, ?(20[0-9]{2}))?|([0-9]{1,2}) (يناير|فبراير|مارس|ابريل|مايو|يونيو|يوليو|اغسطس|سبتمبر|اكتوبر|نوفمبر|ديسمبر)(?: (20[0-9]{2}))?)(?![0-9a-z])',
);

/// The first date in the message, at the receipt's time of day, with
/// whether it carried a year and its folded span. Null when there is none,
/// it is not a calendar date, it is after the receipt day or more than a
/// year before it.
(DateTime, bool, int, int)? _messageDate(String t, DateTime receivedAt) {
  (DateTime, bool, int, int)? best;
  void consider(int day, int month, int year, int start, int end) {
    if (best != null && best!.$3 <= start) {
      return;
    }
    final d = _calendar(day, month, year, receivedAt);
    if (d != null) {
      best = (d, year != 0, start, end);
    }
  }

  for (final n in _numericDate.allMatches(t)) {
    if (best != null && best!.$3 <= n.start) {
      break;
    }
    if (n.group(1) != null) {
      consider(
        int.parse(n.group(3)!),
        int.parse(n.group(2)!),
        int.parse(n.group(1)!),
        n.start,
        n.end,
      );
    } else if (n.group(4) != null) {
      final y = n.group(6);
      consider(
        int.parse(n.group(4)!),
        int.parse(n.group(5)!),
        y == null ? 0 : (y.length == 2 ? 2000 + int.parse(y) : int.parse(y)),
        n.start,
        n.end,
      );
    } else {
      consider(
        int.parse(n.group(7)!),
        int.parse(n.group(9)!),
        int.parse(n.group(10)!),
        n.start,
        n.end,
      );
    }
  }
  for (final m in _namedDate.allMatches(t)) {
    if (best != null && best!.$3 <= m.start) {
      break;
    }
    final String dayText;
    final String? monthText;
    final String? year;
    if (m.group(1) != null) {
      (dayText, monthText, year) = (m.group(1)!, m.group(2), m.group(3));
    } else if (m.group(4) != null) {
      (dayText, monthText, year) = (m.group(5)!, m.group(4), m.group(6));
    } else {
      (dayText, monthText, year) = (m.group(7)!, m.group(8), m.group(9));
    }
    final key = monthText == null
        ? null
        : monthText.codeUnitAt(0) < 0x80
        ? monthText.substring(0, 3)
        : monthText;
    final month = _months[key];
    // `may` is also a verb (`EGP 5 may apply`): only with a year.
    if (month == null || (key == 'may' && year == null)) {
      continue;
    }
    consider(
      int.parse(dayText),
      month,
      year == null ? 0 : int.parse(year),
      m.start,
      m.end,
    );
  }
  return best;
}

final RegExp _clockAfterDate = RegExp(
  r'^[ ,]{1,2}([01]?[0-9]|2[0-3]):([0-5][0-9])(?::([0-5][0-9]))?(?![0-9])',
);

/// A time of day written right after the date (`17-05-2026 22:32`) replaces
/// the receipt's time of day; otherwise the date stays as it is.
(DateTime, bool, int, int)? _withClock(
  String t,
  (DateTime, bool, int, int)? date,
) {
  if (date == null) {
    return null;
  }
  final m = _clockAfterDate.firstMatch(t.substring(date.$4));
  if (m == null) {
    return date;
  }
  final d = date.$1;
  final withClock = DateTime.utc(
    d.year,
    d.month,
    d.day,
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    m.group(3) == null ? 0 : int.parse(m.group(3)!),
  );
  return (withClock, date.$2, date.$3, date.$4);
}

/// [year] 0 means "nearest past occurrence".
DateTime? _calendar(int day, int month, int year, DateTime receivedAt) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  final today = DateTime.utc(receivedAt.year, receivedAt.month, receivedAt.day);
  var y = year == 0 ? today.year : year;
  var d = DateTime.utc(y, month, day);
  if (year == 0 && d.isAfter(today)) {
    y -= 1;
    d = DateTime.utc(y, month, day);
  }
  if (d.month != month || d.day != day) {
    return null;
  }
  if (d.isAfter(today) || today.difference(d).inDays > 366) {
    return null;
  }
  return DateTime.utc(
    y,
    month,
    day,
    receivedAt.hour,
    receivedAt.minute,
    receivedAt.second,
  );
}

// ---------------------------------------------------------------------------
// Reference.

final RegExp _referenceCue = RegExp(
  r'(?:(?<![a-z])(?:ref(?:erence)?|trx|txn|transaction|auth(?:ori[sz]ation)?)(?![a-z])(?: ?(?:no|number|id|code|#)(?![a-z]))?\.?|(?:(?:رقم )?المرجع|مرجعي?)|رقم العمليه|رقم المعامله)[ :#.-]{0,3}([a-z0-9][a-z0-9-]{3,29})(?![a-z0-9-])',
);

/// A reference after a cue, as written in [original], with its span. It
/// must hold a digit (a word after `Ref` is not a reference).
(String, GenericSpan)? _reference(FoldedText folded, String original) {
  for (final m in _referenceCue.allMatches(folded.text)) {
    final g = m.group(1)!;
    if (!g.codeUnits.any((u) => u >= 0x30 && u <= 0x39)) {
      continue;
    }
    final s = m.end - g.length;
    final a = folded.origin[s];
    final b = folded.origin[m.end - 1] + 1;
    return (normalizeText(original.substring(a, b)), GenericSpan(a, b));
  }
  return null;
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
  const _Candidate(
    this.start,
    this.end,
    this.money, {
    required this.numStart,
    required this.numEnd,
    required this.curStart,
    required this.curEnd,
    required this.symbolMarker,
  });
  final int start;
  final int end;
  final Money money;
  final int numStart;
  final int numEnd;
  final int curStart;
  final int curEnd;

  /// The currency came from a symbol (`$`, `£`), not a code or a word.
  final bool symbolMarker;
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
  const _Marker(this.currency, this.start, this.end, {this.symbol = false});
  final Currency currency;
  final int start;
  final int end;
  final bool symbol;
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

/// A symbol at [i] of [t], with its letter prefix (`a$`, `us$`, `e£`).
/// Null for an unknown prefix: `C$` or `R$` is never read as USD.
_Marker? _symbolAt(String t, int i) {
  final ch = t[i];
  final bare = resolveCurrencyMarker(ch, null);
  if (bare == null) {
    return null;
  }
  var p = i;
  while (p > 0 && i - p < 3 && _isAsciiLetter(t.codeUnitAt(p - 1))) {
    p--;
  }
  if (p == i) {
    return _Marker(bare, i, i + 1, symbol: true);
  }
  // Letters touch the symbol: only a whole listed prefix counts.
  if (p > 0 && _isAsciiLetter(t.codeUnitAt(p - 1))) {
    return null;
  }
  final code = prefixedSymbols[t.substring(p, i + 1)];
  final c = code == null ? null : Currency.tryOf(code);
  return c == null ? null : _Marker(c, p, i + 1, symbol: true);
}

/// Currency marker ending right before [at] (spaces allowed between).
_Marker? _markerBefore(String t, int at) {
  var e = at;
  while (e > 0 && t.codeUnitAt(e - 1) == 0x20) {
    e--;
  }
  if (e == 0) {
    return null;
  }
  if (resolveCurrencyMarker(t[e - 1], null) != null) {
    return _symbolAt(t, e - 1);
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
  // A symbol after the number has no prefix to read (`12 $`); a letter
  // prefix right after the number (`12 a$`) is not a bare symbol.
  for (final entry in prefixedSymbols.entries) {
    if (t.startsWith(entry.key, s)) {
      final c = Currency.tryOf(entry.value);
      return c == null
          ? null
          : _Marker(c, s, s + entry.key.length, symbol: true);
    }
  }
  final symbol = resolveCurrencyMarker(t[s], null);
  if (symbol != null) {
    return _Marker(symbol, s, s + 1, symbol: true);
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

/// Digits right after a card mask (`**4010`, `xx4010`) are a card number,
/// never an amount, and take no currency marker from the amount next to it.
bool _masked(String t, int start) {
  if (start == 0) {
    return false;
  }
  final b = t.codeUnitAt(start - 1);
  if (b == 0x2A) {
    return true;
  }
  return b == 0x78 &&
      start >= 2 &&
      (t.codeUnitAt(start - 2) == 0x78 || t.codeUnitAt(start - 2) == 0x2A);
}

/// A whole-word balance cue (`bal`, `avl`) in [window].
bool _hasBalanceWord(String window) {
  for (final w in balanceWholeWords) {
    var from = 0;
    while (true) {
      final i = window.indexOf(w, from);
      if (i < 0) {
        break;
      }
      from = i + 1;
      final end = i + w.length;
      if ((i == 0 || !_isAlnum(window.codeUnitAt(i - 1))) &&
          (end == window.length || !_isAlnum(window.codeUnitAt(end)))) {
        return true;
      }
    }
  }
  return false;
}

final RegExp _trailingSeparator = RegExp(r'[0-9][.,]$');

/// Start of the clause holding [at]: after the last `. `, `; `, `! `, `? `
/// or line break before it (a dot inside a number does not end a clause).
int _clauseStart(String t, int at) {
  for (var i = at - 1; i > 0; i--) {
    final u = t.codeUnitAt(i);
    if (u == 0x0A) {
      return i + 1;
    }
    if (u == 0x20) {
      final p = t.codeUnitAt(i - 1);
      if (p == 0x2E || p == 0x3B || p == 0x21 || p == 0x3F || p == 0x061F) {
        return i + 1;
      }
    }
  }
  return 0;
}

/// A balance word earlier in the amount's clause with no transaction cue
/// between it and the amount (`Your available balance on account ending
/// 8120 is EGP 3,200.50`).
bool _balanceClause(String t, int at, List<_Hit> cues) {
  final from = _clauseStart(t, at);
  final clause = t.substring(from, at);
  var last = -1;
  for (final w in balanceKeywords) {
    final i = clause.lastIndexOf(w);
    if (i > last) {
      last = i;
    }
  }
  if (last < 0) {
    return false;
  }
  final b = from + last;
  return !cues.any((h) => h.start > b && h.end <= at);
}

List<_Candidate> _candidates(String t, List<_Hit> cues) {
  final runs = <_Run>[];
  for (final m in _numberRun.allMatches(t)) {
    var end = m.end;
    var text = m.group(0)!;
    if (_trailingSeparator.hasMatch(text)) {
      text = text.substring(0, text.length - 1);
      end -= 1;
    }
    final run = _Run(m.start, end, text);
    if (!_dateLike(t, run) && !_masked(t, m.start)) {
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
    final marker = pre ?? suf;
    if (marker == null ||
        (pre != null && suf != null && pre.currency != suf.currency)) {
      continue;
    }
    final window = t.substring(windowStart, pre?.start ?? start);
    final at = pre?.start ?? start;
    if (balanceKeywords.any(window.contains) ||
        _hasBalanceWord(window) ||
        _balanceClause(t, at, cues)) {
      continue;
    }
    final parsed = parseAmount(r.text, currency: marker.currency);
    final money = parsed is Ok<Money, ParseFailure> ? parsed.value : null;
    if (money == null || !money.isPositive) {
      continue;
    }
    out.add(
      _Candidate(
        pre?.start ?? start,
        suf?.end ?? r.end,
        money,
        numStart: r.start,
        numEnd: r.end,
        curStart: marker.start,
        curEnd: marker.end,
        symbolMarker: marker.symbol,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// Last-4.

final RegExp _last4Marked = RegExp(
  r'(?:\*{1,8}|\bx{2,8}|ending(?: in| with)?|(?:card|account|acct|a/c)(?: (?:no|number))?|(?:ال)?[ميت]نتهيه?(?: رقمها| رقمه)? (?:ب ?(?:رقم )?|برقم )|رقم (?:ال)?(?:بطاقه|حساب)|بطاقه|بطاقتك|حساب|حسابك|حسابكم|كارت)(?: رقم)?[ :.#x*-]{0,4}([0-9]{4})(?![0-9])(?![.,][0-9])',
);

/// The last-4, whether a word (`card`, `ending`, `بطاقه`) named it rather
/// than a mask alone, and its folded start.
(String, bool, int)? _last4(String t, List<CompiledPattern> declared) {
  for (final p in declared) {
    final m = p.regex.firstMatch(t);
    final d = m?.group(1);
    if (m != null && d != null && d.length == 4 && _allDigits(d)) {
      final at = t.indexOf(d, m.start);
      if (at >= 0) {
        return (d, true, at);
      }
    }
  }
  final m = _last4Marked.firstMatch(t);
  if (m == null) {
    return null;
  }
  final d = m.group(1)!;
  final first = t.codeUnitAt(m.start);
  final masked = first == 0x2A || first == 0x78;
  return (d, !masked, m.end - 4);
}

bool _allDigits(String s) => s.codeUnits.every((u) => u >= 0x30 && u <= 0x39);

// ---------------------------------------------------------------------------
// Merchant.

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

final RegExp _clauseEnd = RegExp(r'[.,;:!?]$');

/// Direction and event keywords of one word (`شراء`, `بقيمه`, `debited`):
/// they end a merchant span and never start one.
final Set<String> _transactionWords = {
  for (final w in [
    ...expenseKeywords,
    ...incomeKeywords,
    ...amountCueKeywords,
    for (final (_, words) in eventKeywords) ...words,
  ])
    if (!w.contains(' ')) w,
};

/// `علي` folds from both the preposition `على` and the name `علي` (Ali): it
/// is a name when the original is written with a final `ي`.
bool _nameAli(String c, FoldedText folded, String original, int start) {
  if (c != 'علي') {
    return false;
  }
  final last = folded.origin[start + 2];
  return last < original.length && original.codeUnitAt(last) == 0x064A;
}

/// The merchant, whether a strong marker (`at`, `لدى`) introduced it, and
/// its folded span.
(CleanedMerchant, bool, int, int)? _merchant(
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
  bool endsClause(String raw) => _clauseEnd.hasMatch(raw);
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
    final marker = core(raws[i]);
    if (!merchantMarkers.contains(marker)) {
      continue;
    }
    // `Merchant: X` and `at X` only; a marker that ends a clause (`to.`)
    // introduces nothing, except a label with a colon.
    if (endsClause(raws[i]) && !raws[i].endsWith(':')) {
      continue;
    }
    int? spanStart;
    var spanEnd = 0;
    var count = 0;
    for (var j = i + 1; j < raws.length && count < _maxMerchantTokens; j++) {
      final c = core(raws[j]);
      if (c.isEmpty ||
          (merchantStopWords.contains(c) &&
              !_nameAli(c, folded, original, starts[j])) ||
          _transactionWords.contains(c) ||
          _mostlyDigits(c) ||
          c.contains('@') ||
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
      return (
        cleaned,
        strongMerchantMarkers.contains(marker),
        spanStart,
        spanEnd,
      );
    }
  }
  return null;
}
