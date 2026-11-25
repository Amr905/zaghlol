import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../pipeline/parsing_pipeline.dart' show resolveOccurredAt;
import '../registry/registry_models.dart';

/// Confidence of a receipt amount found next to a total label (never
/// auto-accepted; the confirmation screen always shows it anyway).
const int _receiptConfidencePermille = 600;

/// Confidence when the label and the amount were matched by column position.
const int _columnConfidencePermille = 550;

/// Confidence of the last-resort guess (largest plausible amount).
const int _fallbackConfidencePermille = 400;

/// Template id of a receipt read through a total label.
const String receiptLabelTemplateId = 'ocr.receipt.generic';

/// Template id of a receipt read by the last-resort guess.
const String receiptFallbackTemplateId = 'ocr.receipt.fallback';

/// Words that label the amount to pay on a till receipt, English and Arabic
/// (already folded: `الإجمالي` is `الاجمالي`, `ة` is `ه`). A bare `total`
/// after `sub` is the subtotal and is skipped by the look-behinds. Linear:
/// no nested quantifiers.
final RegExp _totalLabel = RegExp(
  r'(?<![a-z])(?<!sub)(?<!sub )(?:grand total|total due|amount due|net total|total amount|total price|net amount|total|net(?! sales)|amount)(?![a-z])'
  r'|الاجمالي النهائي|الاجمالي|اجمالي|المبلغ المستحق|المستحق|المطلوب سداده|المطلوب|قيمه الفاتوره|صافي المبلغ|الصافي|صافي|المجموع',
);

/// Lines that are never the total: subtotal, tax, discount, tender, change,
/// item counts. `incl. VAT` after a total is removed first.
final RegExp _skipLine = RegExp(
  r'(?<![a-z])(?:sub ?total|vat|tax|discount|disc|paid|cash|change|tendered|tender|received|returned|refund|savings?|saved|balance|remaining|outstanding|card|visa|mastercard|change due|items?|qty|quantity|net sales|service|approved|approval|authori[sz]ation)(?![a-z])'
  r'|المجموع الفرعي|قبل الخصم|ضريبه|خصم|المدفوع|مدفوع|الباقي|نقدي|نقدا|عدد|الكميه|المستلم|المرتجع|مرتجع|توفير|وفرت|الرصيد|المتبقي|متبقي|فيزا|بطاقه',
);
final RegExp _inclTax = RegExp(
  r'(?:incl\w*\.?|inc\.?|with|including|شامل(?: ال)?)\s*(?:vat|tax|ضريبه)',
);

/// Words of a table header row (`Item Qty U P Total`).
final RegExp _headerWord = RegExp(
  r'(?<![a-z])(?:qty|quantity|item|items|u ?p|unit price|unit|price|desc|description)(?![a-z])|الصنف|الكميه|السعر|البيان',
);

/// Labels of the amounts a total is cross-checked against (T-267).
final RegExp _netLabel = RegExp(
  r'net sales|(?<![a-z])sub ?total(?![a-z])|المجموع الفرعي|قبل الضريبه',
);
final RegExp _taxLabel = RegExp(r'(?<![a-z])(?:vat|tax)(?![a-z])|ضريبه');
final RegExp _serviceLabel = RegExp(r'(?<![a-z])service(?![a-z])|خدمه');
final RegExp _cardLabel = RegExp(
  r'(?<![a-z])(?:visa|mastercard|card|credit|debit)(?![a-z])|فيزا|بطاقه|ماستر',
);
final RegExp _cashLabel = RegExp(
  r'(?<![a-z])(?:cash|paid|tendered|received)(?![a-z])|نقدي|نقدا|المدفوع|مدفوع|المستلم',
);
final RegExp _mergedCells = RegExp(
  r'(?<![0-9.,])([0-9]+\.[0-9]{2})([0-9]+\.[0-9]{2})(?![0-9])',
);
final RegExp _discountLabel = RegExp(
  r'(?<![a-z])(?:discount|disc)(?![a-z])|خصم',
);

/// Digits that are not an amount: right after a mask (`****4321`,
/// `XXXX 4321`), right before one (`45XX`) or after `Card No` / `رقم البطاقة`.
final RegExp _maskBefore = RegExp(r'(?:^|[^a-z])(?:x{2,}|[*•]+)[\s\-]*$');
final RegExp _maskAfter = RegExp(r'^\s*(?:x{2}|[*•])');
final RegExp _cardNoBefore = RegExp(
  r'(?:(?:card|بطاقه)\s*(?:no|number|num|رقم)\.?|رقم\s*(?:ال)?بطاقه)\s*#?:?\s*$',
);
final RegExp _meridiem = RegExp(r'^\s*([ap])\.?m\b');

final RegExp _phoneLine = RegExp(
  r'(?<![a-z])(?:tel|phone|mob|mobile|fax|hotline|whats ?app)(?![a-z])|هاتف|تليفون|موبايل|محمول',
);

/// Merchant lines that are not a name: a city alone, a branch, a seller or
/// customer field, delivery/address fields, table headers. Folded text.
final RegExp _notMerchantWords = RegExp(
  r'^(?:فرع|branch)(?![a-z\u0621-\u064A])'
  r'|(?<![a-z])(?:cashier|seller|customer|delivery|address|item|items|qty|quantity|price|branch|salesman|served by)(?![a-z])'
  r'|بائع|عميل|كاشير|مستلم|توصيل|دليفري|عنوان|صنف|كميه|سعر',
);
const Set<String> _cityKeys = {
  'القاهره',
  'الجيزه',
  'الاسكندريه',
  'اسكندريه',
  'القليوبيه',
  'الشرقيه',
  'الدقهليه',
  'الغربيه',
  'المنوفيه',
  'البحيره',
  'طنطا',
  'المنصوره',
  'اسيوط',
  'الاقصر',
  'اسوان',
  'بورسعيد',
  'السويس',
  'الاسماعيليه',
  'الفيوم',
  'سوهاج',
  'cairo',
  'giza',
  'alexandria',
  'alex',
};
final RegExp _nonLetters = RegExp(r'[^a-z\u0621-\u064A]');
final RegExp _priceLike = RegExp(r'[0-9]+[.,][0-9]{2}');
final RegExp _longDigits = RegExp(r'[0-9]{4,}');
final RegExp _valueCell = RegExp(
  r'^[\s\-+]*(?:[0-9][0-9,]*)?(?:\.[0-9]+)?[\s\-+]*$',
);

final RegExp _numberToken = RegExp(
  r'(?<![0-9.,])[0-9][0-9,]*(?:\.[0-9]{1,3})?(?![0-9])',
);
final RegExp _currencyToken = RegExp(
  r'(?<![a-z])(egp|usd|eur|gbp|sar|aed|kwd|qar)(?![a-z])'
  r'|(?<![a-z])l\.?e(?![a-z])\.?|جم|جنيه|ج\.م|(?<![ء-ي])ج(?![ء-ي])|\$|€|£',
);
final RegExp _dmy = RegExp(
  r'(?<![0-9])(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?![0-9])',
);
final RegExp _ymd = RegExp(r'(?<![0-9])(\d{4})-(\d{1,2})-(\d{1,2})(?![0-9])');
final RegExp _time = RegExp(r'(?<![0-9])(\d{1,2}):(\d{2})(?![0-9:])');
final RegExp _alnum = RegExp(r'[a-z0-9\u0621-\u064A]');
final RegExp _letters = RegExp(r'[a-zء-ي]');
final RegExp _qtyBefore = RegExp(
  r'(?:(?:^|[^a-z])[x×]|qty|quantity|الكميه|كميه|#|no\.?|number|ref|order|table|رقم)\s*:?\s*$',
);
final RegExp _qtyAfter = RegExp(r'^\s*[x×](?![a-z])');
final RegExp _percentAfter = RegExp(r'^\s*[%٪]');

/// Words that make a first line a heading, not a merchant name.
const Set<String> _headingWords = {
  'receipt',
  'invoice',
  'tax',
  'cashier',
  'welcome',
  'فاتوره',
  'ايصال',
  'اهلا',
  'مرحبا',
  'ضريبه',
};

/// What a receipt shows besides its amount: used to prefill manual entry
/// when no total could be read.
final class ReceiptHints {
  const ReceiptHints({this.merchant, this.date});
  final CleanedMerchant? merchant;
  final DateTime? date;
}

/// Merchant and date of a receipt, without an amount. Total; never throws.
ReceiptHints readReceiptHints({
  required String text,
  required String folded,
  MerchantCleaningConfig cleaning = MerchantCleaningConfig.defaults,
}) => ReceiptHints(
  merchant: _readMerchant(text, cleaning),
  date: _readDate(folded),
);

final class _Cand {
  const _Cand(this.start, this.end, this.money, this.strong, this.decimal);
  final int start;
  final int end;
  final Money money;
  final bool strong;

  /// The token had a decimal point (OCR may have dropped it from `436.00`).
  final bool decimal;
}

final class _Line {
  _Line(this.s, this.cands, this.isSkip, this.labels);
  final String s;
  final List<_Cand> cands;
  final bool isSkip;
  final List<RegExpMatch> labels;

  bool get hasLetters => _letters.hasMatch(_stripCurrency(s));

  /// Only an amount (and maybe a currency): a value cell.
  bool get isNum =>
      !hasLetters &&
      (cands.isNotEmpty ||
          (s.contains(RegExp(r'[0-9]')) && _valueCell.hasMatch(s)));

  /// Only words: a label cell.
  bool get isLab => cands.isEmpty && hasLetters;
}

String _stripCurrency(String s) => s.replaceAll(_currencyToken, ' ');

/// Reads a till receipt from OCR text: the total amount, the first
/// plausible heading as merchant, the first date and time. [folded] is the
/// folded text (`foldKey`); [text] keeps the original lines for the merchant.
/// Anything not found stays null; the result is never auto-accepted.
ParseResult parseReceiptText({
  required String text,
  required String folded,
  required DateTime receivedAt,
  required String language,
  MerchantCleaningConfig cleaning = MerchantCleaningConfig.defaults,
}) {
  final marker = _currencyToken.firstMatch(folded)?.group(0);
  final currency =
      (marker == null
          ? null
          : resolveCurrencyMarker(_markerKey(marker), null)) ??
      Currency.of('EGP');

  final lines = <_Line>[
    for (final raw in _joinSplitLabels(foldKeyLines(text).split('\n')))
      if (raw.trim().isNotEmpty) _buildLine(raw.trim(), currency),
  ];

  _markHeaderCells(lines);
  final picked = _pickTotal(lines);
  final Money amount;
  var confidence = _receiptConfidencePermille;
  var templateId = receiptLabelTemplateId;
  if (picked == null) {
    final guess = _fallbackAmount(lines);
    if (guess == null) {
      return const ParseUnrecognized(UnrecognizedReason.genericNoAmount);
    }
    amount = guess;
    confidence = _fallbackConfidencePermille;
    templateId = receiptFallbackTemplateId;
  } else {
    amount = picked.money;
    confidence = picked.confidence;
    if (picked.guess) {
      confidence = _fallbackConfidencePermille;
      templateId = receiptFallbackTemplateId;
    }
  }

  final date = _readDate(folded);
  final time = _time.firstMatch(folded);
  final wall = time == null
      ? null
      : _wall(
          int.parse(time.group(1)!),
          int.parse(time.group(2)!),
          _meridiem.firstMatch(folded.substring(time.end))?.group(1),
        );
  final (occurredAt, source) = resolveOccurredAt(date, wall, receivedAt);

  return ParseParsed(
    institutionCode: 'ocr_receipt',
    templateId: templateId,
    templateVersion: 1,
    language: language,
    event: TemplateEvent.cardPurchase,
    direction: TemplateDirection.expense,
    fields: ParsedFields(
      amount: amount,
      originalAmount: null,
      balance: null,
      available: null,
      balanceIsAvailableLimit: false,
      last4: null,
      merchant: _readMerchant(text, cleaning),
      counterparty: null,
      ref: null,
      date: date,
      time: wall,
      occurredAt: occurredAt,
      occurredAtSource: source,
    ),
    confidencePermille: confidence,
    reasons: const [],
  );
}

CleanedMerchant? _readMerchant(String text, MerchantCleaningConfig cleaning) {
  for (final raw in text.split('\n').take(6)) {
    final line = raw.trim();
    final key = foldKey(line);
    if (!_letters.hasMatch(key) ||
        _headingWords.any(key.contains) ||
        _totalLabel.hasMatch(key) ||
        _skipLine.hasMatch(key) ||
        _phoneLine.hasMatch(key) ||
        key.endsWith(':') ||
        _notMerchantWords.hasMatch(key) ||
        _priceLike.hasMatch(key) ||
        _longDigits.hasMatch(key) ||
        _cityKeys.contains(key.replaceAll(_nonLetters, ''))) {
      continue;
    }
    final cleaned = cleanMerchant(line, config: cleaning);
    if (cleaned.key.isNotEmpty) {
      return cleaned;
    }
  }
  return null;
}

/// `Amount` and `Due ...` on two lines read as one `Amount Due ...` line.
List<String> _joinSplitLabels(List<String> raw) {
  final out = <String>[];
  for (final r in raw) {
    final t = r.trim();
    if (out.isNotEmpty &&
        out.last.trim() == 'amount' &&
        (t == 'due' || t.startsWith('due '))) {
      out[out.length - 1] = 'amount $t';
    } else {
      out.add(r);
    }
  }
  return out;
}

_Line _buildLine(String input, Currency currency) {
  final s = input.replaceAllMapped(_mergedCells, (m) => '${m[1]} ${m[2]}');
  final isPhone = _phoneLine.hasMatch(s);
  final isSkip = _skipLine.hasMatch(s.replaceAll(_inclTax, ' '));
  final spans = <(int, int)>[
    for (final m in _dmy.allMatches(s)) (m.start, m.end),
    for (final m in _ymd.allMatches(s)) (m.start, m.end),
    for (final m in _time.allMatches(s)) (m.start, m.end),
  ];
  final cands = <_Cand>[];
  if (!isPhone) {
    for (final m in _numberToken.allMatches(s)) {
      final tok = m.group(0)!;
      if (spans.any((p) => m.start < p.$2 && m.end > p.$1)) {
        continue;
      }
      final hasPoint = tok.contains('.');
      final digits = tok.replaceAll(',', '');
      if (!hasPoint &&
          (digits.length >= 6 || (digits.length > 1 && digits[0] == '0'))) {
        continue;
      }
      final before = s.substring(0, m.start);
      final after = s.substring(m.end);
      if (_maskBefore.hasMatch(before) ||
          _maskAfter.hasMatch(after) ||
          _cardNoBefore.hasMatch(before) ||
          _percentAfter.hasMatch(after) ||
          _qtyAfter.hasMatch(after) ||
          _qtyBefore.hasMatch(before) ||
          (m.start > 0 &&
              s[m.start - 1] == '-' &&
              (hasPoint
                  ? (m.start == 1 || !_alnum.hasMatch(s[m.start - 2]))
                  : true)) ||
          (!hasPoint && after.isNotEmpty && after[0] == '-')) {
        continue;
      }
      final money = parseAmount(tok, currency: currency).valueOrNull;
      if (money == null || !money.isPositive) {
        continue;
      }
      final near = s.substring(
        m.start - 8 < 0 ? 0 : m.start - 8,
        m.end + 8 > s.length ? s.length : m.end + 8,
      );
      final strong =
          RegExp(r'\.[0-9]{2}$').hasMatch(tok) || _currencyToken.hasMatch(near);
      cands.add(_Cand(m.start, m.end, money, strong, hasPoint));
    }
  }
  if (isSkip) {
    final seg = _splitSegments(s, cands);
    if (seg != null) {
      return _Line(s, seg.$2, false, seg.$1);
    }
  }
  final labels = isSkip
      ? const <RegExpMatch>[]
      : _totalLabel.allMatches(s).toList(growable: false);
  if (labels.isNotEmpty && cands.isEmpty && _isHeader(s)) {
    return _Line(s, cands, true, const []);
  }
  return _Line(s, cands, isSkip, labels);
}

/// A table header row: a total word next to column words (`U P Total`).
bool _isHeader(String s) =>
    _headerWord.hasMatch(s.replaceAll(_totalLabel, ' '));

/// A lone `Total` cell whose neighbours in the same run of label-only lines
/// are column headers (`Item`, `Qty`, `U P`) is a header cell, not a label.
void _markHeaderCells(List<_Line> lines) {
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.labels.isEmpty || !l.isLab || l.isSkip) {
      continue;
    }
    var header = false;
    for (var d = 1; d <= 3 && !header; d++) {
      for (final j in [i - d, i + d]) {
        if (j < 0 || j >= lines.length) {
          continue;
        }
        var contiguous = true;
        for (var k = j < i ? j : i + 1; k <= (j < i ? i - 1 : j); k++) {
          contiguous = contiguous && lines[k].isLab;
        }
        if (contiguous && _headerWord.hasMatch(lines[j].s)) {
          header = true;
        }
      }
    }
    if (header) {
      lines[i] = _Line(l.s, l.cands, true, const []);
    }
  }
}

/// A row with several label-value pairs (`total: 573.00 discount .00`, or
/// RTL `.00 discount 573.00 :total`): each label owns the segment after it
/// (label-first rows) or before it (amount-first rows). The total label
/// counts only when its own segment holds an amount, so a skip word elsewhere
/// on the row doesn't hide it, and `total tax 5.00` stays a skip row.
(List<RegExpMatch>, List<_Cand>)? _splitSegments(String s, List<_Cand> cands) {
  final skips = _skipLine
      .allMatches(s.replaceAllMapped(_inclTax, (m) => ' ' * m.group(0)!.length))
      .toList(growable: false);
  final totals = [
    for (final t in _totalLabel.allMatches(s))
      if (!skips.any((k) => t.start < k.end && t.end > k.start)) t,
  ];
  if (totals.isEmpty) {
    return null;
  }
  final all = <(int, int, bool)>[
    for (final t in totals) (t.start, t.end, true),
    for (final k in skips) (k.start, k.end, false),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final amountFirst = s.substring(0, all.first.$1).contains(RegExp(r'[0-9]'));
  final keptLabels = <RegExpMatch>[];
  final keptCands = <_Cand>[];
  for (var k = 0; k < all.length; k++) {
    if (!all[k].$3) {
      continue;
    }
    final from = amountFirst ? (k == 0 ? 0 : all[k - 1].$2) : all[k].$1;
    final to = amountFirst
        ? all[k].$2
        : (k + 1 < all.length ? all[k + 1].$1 : s.length);
    final own = cands.where((c) => c.start >= from && c.end <= to).toList();
    if (own.isEmpty) {
      continue;
    }
    keptLabels.add(totals.firstWhere((t) => t.start == all[k].$1));
    keptCands.addAll(own);
  }
  return keptLabels.isEmpty ? null : (keptLabels, keptCands);
}

_Cand? _pick(Iterable<_Cand> cands, {bool strongOnly = false}) {
  _Cand? first;
  for (final c in cands) {
    first ??= c;
    if (c.strong) {
      return c;
    }
  }
  return strongOnly ? null : first;
}

/// The amount for [label] on line [i]: after it, before it, on one of the
/// next two value-only lines, then by column position.
(Money, int, bool)? _amountFor(
  List<_Line> lines,
  int i,
  RegExpMatch label, {
  bool loose = true,
  bool strongOnly = false,
}) {
  final line = lines[i];
  final after = _pick(
    line.cands.where((c) => c.start >= label.end && c.start - label.end <= 40),
    strongOnly: strongOnly,
  );
  if (after != null) {
    return (after.money, _receiptConfidencePermille, after.decimal);
  }
  final before = _pick(
    line.cands.where((c) => c.end <= label.start).toList().reversed,
    strongOnly: strongOnly,
  );
  if (before != null) {
    return (before.money, _receiptConfidencePermille, before.decimal);
  }
  final block = _columnAmount(lines, i, strict: true, strongOnly: strongOnly);
  if (block != null) {
    return block;
  }
  for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
    final next = lines[j];
    if (next.isSkip || next.labels.isNotEmpty || !next.isNum) {
      break;
    }
    final c = _pick(next.cands, strongOnly: strongOnly);
    if (c != null) {
      return (c.money, _receiptConfidencePermille, c.decimal);
    }
  }
  return loose ? _columnAmount(lines, i, strongOnly: strongOnly) : null;
}

/// Labels and values in separate blocks: the label's row in its run of
/// label-only lines picks the same row in the value-only run after it
/// (aligned to the end when the label run is longer, as headings come
/// first) or before it (equal counts).
(Money, int, bool)? _columnAmount(
  List<_Line> lines,
  int i, {
  bool strict = false,
  bool strongOnly = false,
}) {
  if (!lines[i].isLab) {
    return null;
  }
  var a = i;
  while (a > 0 && lines[a - 1].isLab) {
    a--;
  }
  var b = i;
  while (b + 1 < lines.length && lines[b + 1].isLab) {
    b++;
  }
  final labCount = b - a + 1;
  var e = b + 1;
  while (e < lines.length && lines[e].isNum) {
    e++;
  }
  final nAfter = e - (b + 1);
  // Strict (tried before "the next line"): a real block of rows, whose
  // matching labels are all total, tax or discount words.
  var plausible = true;
  if (strict) {
    for (var q = b - nAfter + 1; q <= b && plausible && q >= a; q++) {
      plausible = lines[q].isSkip || lines[q].labels.isNotEmpty;
    }
  }
  if (nAfter >= (strict ? 2 : 1) && nAfter <= labCount && plausible) {
    final k = (i - a) - (labCount - nAfter);
    if (k >= 0) {
      final c = _pick(lines[b + 1 + k].cands, strongOnly: strongOnly);
      if (c != null) {
        return (c.money, _columnConfidencePermille, c.decimal);
      }
    }
  }
  if (strict) {
    return null;
  }
  var s = a;
  while (s > 0 && lines[s - 1].isNum) {
    s--;
  }
  if (a - s == labCount) {
    final c = _pick(lines[s + (i - a)].cands, strongOnly: strongOnly);
    if (c != null) {
      return (c.money, _columnConfidencePermille, c.decimal);
    }
  }
  return null;
}

final class _Found {
  const _Found(this.money, this.confidence, this.decimal);
  final Money money;
  final int confidence;
  final bool decimal;
}

final class _Pick {
  const _Pick(this.money, this.confidence, {this.guess = false});
  final Money money;
  final int confidence;

  /// The total contradicts every cross-check: offered as a guess.
  final bool guess;
}

/// Sum of item totals is "readable" with at least this many item lines.
const int _minItemsForSum = 2;

/// A total above this multiple of the item sum is a misread.
const int _maxTotalOverItems = 3;

/// The largest strong amount of every item row (quantity, unit price and line
/// total in any order; the line total is never below the unit price).
List<int> _itemTotals(List<_Line> lines) {
  final out = <int>[];
  for (final l in lines) {
    if (l.isSkip || l.labels.isNotEmpty || !l.hasLetters) {
      continue;
    }
    final strong = l.cands.where((c) => c.strong).toList();
    if (strong.isNotEmpty) {
      out.add(strong.map((c) => c.money.minor).reduce((a, b) => a > b ? a : b));
    }
  }
  return out;
}

final RegExp _zeroAfter = RegExp(r'^[\s:=\-]*0+(?:\.0+)?(?![0-9.,])');

/// Values of every line labelled by [label] (same row, next value row or
/// column block); zero and unreadable values are dropped.
List<Money> _tenders(List<_Line> lines, RegExp label, {bool strong = false}) {
  final out = <Money>[];
  for (var i = 0; i < lines.length && out.length < 8; i++) {
    final l = lines[i];
    for (final m in label.allMatches(l.s)) {
      if (_zeroAfter.hasMatch(l.s.substring(m.end))) {
        continue;
      }
      final v = _amountFor(lines, i, m, loose: false, strongOnly: strong);
      if (v != null && v.$1.isPositive) {
        out.add(v.$1);
      }
    }
  }
  return out;
}

/// Sum of the largest strong amount of every priced row without a label,
/// including rows that hold prices only (column blocks, lost words).
int _pricedSum(List<_Line> lines) {
  var sum = 0;
  for (final l in lines) {
    if (l.isSkip || l.labels.isNotEmpty) {
      continue;
    }
    final strong = l.cands.where((c) => c.strong).toList();
    if (strong.isNotEmpty) {
      sum += strong.map((c) => c.money.minor).reduce((a, b) => a > b ? a : b);
    }
  }
  return sum;
}

/// The labelled total by cross-checks. Candidates come from every total
/// label; a candidate confirmed by net + VAT (+ service), a tender or the item
/// sum wins over an unconfirmed one wherever it sits; when the pick fails
/// every available check it is returned as a guess.
_Pick? _pickTotal(List<_Line> lines) {
  var found = <_Found>[];
  var seen = 0;
  for (var i = 0; i < lines.length && seen < 40; i++) {
    final line = lines[i];
    if (line.isSkip) {
      continue;
    }
    for (final label in line.labels) {
      seen++;
      final r = _amountFor(lines, i, label);
      if (r != null) {
        found.add(_Found(r.$1, r.$2, r.$3));
      }
    }
  }
  final hadAny = found.isNotEmpty;
  final items = _itemTotals(lines);
  final itemSum = items.fold<int>(0, (a, b) => a + b);
  final itemsReadable = items.length >= _minItemsForSum;
  // Price-only rows (no words) and priced lines the item sum may miss make
  // the sum doubtful: a labelled total then survives the 3x rule.
  final allSum = _pricedSum(lines);
  final itemsDoubtful = lines.any(
    (l) => !l.isSkip && l.labels.isEmpty && !l.hasLetters && l.cands.isNotEmpty,
  );
  if (itemsReadable) {
    final kept = [
      for (final f in found)
        if (f.money.minor <= itemSum * _maxTotalOverItems) f,
    ];
    if (kept.isNotEmpty || !itemsDoubtful) {
      found = kept;
    }
  }
  if (found.any((f) => f.decimal)) {
    found = [
      for (final f in found)
        if (f.decimal) f,
    ];
  }
  if (found.isEmpty) {
    if (!hadAny) {
      return null;
    }
    // Every labelled total was rejected: a lone card charge at least as big as
    // every item is the best remaining reading, offered as a guess.
    final card = _tenders(lines, _cardLabel, strong: true);
    final top = items.isEmpty ? 0 : items.reduce((a, b) => a > b ? a : b);
    if (card.length == 1 && card.first.minor >= top) {
      return _Pick(card.first, _fallbackConfidencePermille, guess: true);
    }
    return null;
  }

  int? net;
  for (final m in _tenders(lines, _netLabel)) {
    net = m.minor;
    break;
  }
  final tax = _tenders(lines, _taxLabel).fold<int>(0, (a, m) => a + m.minor);
  final service = _tenders(
    lines,
    _serviceLabel,
  ).fold<int>(0, (a, m) => a + m.minor);
  final discount = _tenders(
    lines,
    _discountLabel,
    strong: true,
  ).fold<int>(0, (a, m) => a + m.minor);
  final cards = _tenders(
    lines,
    _cardLabel,
    strong: true,
  ).map((m) => m.minor).toList();
  final cash = _tenders(
    lines,
    _cashLabel,
    strong: true,
  ).map((m) => m.minor).toList();
  final netTaxAvailable = net != null && (tax > 0 || discount > 0);

  bool near(int a, int b) => (a - b).abs() <= 1;
  bool netOk(int c) =>
      netTaxAvailable &&
      (near(net! - discount + tax, c) ||
          near(net - discount + tax + service, c));
  bool tenderOk(int c) => [...cards, ...cash].any((t) => near(t, c));
  bool itemsOk(int c) =>
      itemSum > 0 &&
      (near(itemSum, c) ||
          near(itemSum - discount, c) ||
          near(allSum, c) ||
          near(allSum - discount, c));
  int confirms(int c) =>
      (netOk(c) ? 1 : 0) + (tenderOk(c) ? 1 : 0) + (itemsOk(c) ? 1 : 0);

  _Found? best;
  for (final f in found) {
    final n = confirms(f.money.minor);
    if (n > 0 && (best == null || n >= confirms(best.money.minor))) {
      best = f;
    }
  }
  if (best != null) {
    return _Pick(best.money, best.confidence);
  }
  final last = found.last;
  final c = last.money.minor;
  var contradicts = 0;
  var neutral = 0;
  if (netTaxAvailable) {
    contradicts++;
  }
  if (cards.isNotEmpty) {
    contradicts++;
  }
  if (itemsReadable) {
    if (c < itemSum - discount - 1) {
      contradicts++;
    } else if (!netTaxAvailable) {
      neutral++;
    }
  }
  return _Pick(
    last.money,
    last.confidence,
    guess: contradicts > 0 && neutral == 0,
  );
}

/// No label gave an amount: the largest strong amount on lines that are not
/// tax, tender or change lines, when there are at least two of them or one
/// carries a currency marker. A lone bare line item stays unread.
Money? _fallbackAmount(List<_Line> lines) {
  final strong = <_Cand>[];
  for (final l in lines) {
    if (l.isSkip) {
      continue;
    }
    strong.addAll(l.cands.where((c) => c.strong));
  }
  if (strong.isEmpty) {
    return null;
  }
  if (strong.length < 2 && !_anyCurrencyMarked(lines)) {
    return null;
  }
  return strong.reduce((a, b) => b.money.minor > a.money.minor ? b : a).money;
}

bool _anyCurrencyMarked(List<_Line> lines) => lines.any(
  (l) => !l.isSkip && l.cands.isNotEmpty && _currencyToken.hasMatch(l.s),
);

String _markerKey(String m) => switch (m) {
  'جم' || 'جنيه' || 'ج.م' || 'ج' || 'le' || 'l.e' || 'l.e.' => 'EGP',
  _ => m,
};

WallTime? _wall(int h, int m, [String? meridiem]) {
  if (m > 59 || h > 23) {
    return null;
  }
  if (meridiem == null) {
    return WallTime(h, m);
  }
  if (h < 1 || h > 12) {
    return null;
  }
  final base = h % 12;
  return WallTime(meridiem == 'p' ? base + 12 : base, m);
}

DateTime? _readDate(String folded) {
  DateTime? build(int y, int mo, int d) {
    final v = DateTime.utc(y, mo, d);
    return v.year == y && v.month == mo && v.day == d ? v : null;
  }

  final a = _dmy.firstMatch(folded);
  if (a != null) {
    return build(
      int.parse(a.group(3)!),
      int.parse(a.group(2)!),
      int.parse(a.group(1)!),
    );
  }
  final b = _ymd.firstMatch(folded);
  if (b != null) {
    return build(
      int.parse(b.group(1)!),
      int.parse(b.group(2)!),
      int.parse(b.group(3)!),
    );
  }
  return null;
}
