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
  r'(?<![a-z])(?<!sub)(?<!sub )(?:grand total|total due|amount due|net total|total amount|total price|net amount|total|net|amount)(?![a-z])'
  r'|الاجمالي النهائي|الاجمالي|اجمالي|المبلغ المستحق|المستحق|المطلوب سداده|المطلوب|قيمه الفاتوره|صافي المبلغ|الصافي|صافي|المجموع',
);

/// Lines that are never the total: subtotal, tax, discount, tender, change,
/// item counts. `incl. VAT` after a total is removed first.
final RegExp _skipLine = RegExp(
  r'(?<![a-z])(?:sub ?total|vat|tax|discount|disc|paid|cash|change|tendered|tender|received|returned|refund|savings?|saved|balance|card|visa|mastercard|change due|items?|qty|quantity)(?![a-z])'
  r'|المجموع الفرعي|قبل الخصم|ضريبه|خصم|المدفوع|مدفوع|الباقي|نقدي|نقدا|عدد|الكميه|المستلم|المرتجع|مرتجع|توفير|وفرت|الرصيد|فيزا|بطاقه',
);
final RegExp _inclTax = RegExp(
  r'(?:incl\w*\.?|inc\.?|with|including|شامل(?: ال)?)\s*(?:vat|tax|ضريبه)',
);
final RegExp _phoneLine = RegExp(
  r'(?<![a-z])(?:tel|phone|mob|mobile|fax|hotline)(?![a-z])|هاتف|تليفون|موبايل|محمول',
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
final RegExp _letters = RegExp(r'[a-zء-ي]');
final RegExp _qtyBefore = RegExp(
  r'(?:(?:^|[^a-z])[x×]|qty|quantity|الكميه|كميه|#|no\.?|number|ref|رقم)\s*:?\s*$',
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
  const _Cand(this.start, this.end, this.money, this.strong);
  final int start;
  final int end;
  final Money money;
  final bool strong;
}

final class _Line {
  _Line(this.s, this.cands, this.isSkip, this.labels);
  final String s;
  final List<_Cand> cands;
  final bool isSkip;
  final List<RegExpMatch> labels;

  bool get hasLetters => _letters.hasMatch(_stripCurrency(s));

  /// Only an amount (and maybe a currency): a value cell.
  bool get isNum => cands.isNotEmpty && !hasLetters;

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
    for (final raw in foldKeyLines(text).split('\n'))
      if (raw.trim().isNotEmpty) _buildLine(raw.trim(), currency),
  ];

  Money? amount;
  var confidence = _receiptConfidencePermille;
  var templateId = receiptLabelTemplateId;
  var seen = 0;
  for (var i = 0; i < lines.length && seen < 40; i++) {
    final line = lines[i];
    if (line.isSkip) {
      continue;
    }
    for (final label in line.labels) {
      seen++;
      final found = _amountFor(lines, i, label);
      if (found != null) {
        amount = found.$1;
        confidence = found.$2;
      }
    }
  }
  if (amount == null) {
    amount = _fallbackAmount(lines);
    if (amount == null) {
      return const ParseUnrecognized(UnrecognizedReason.genericNoAmount);
    }
    confidence = _fallbackConfidencePermille;
    templateId = receiptFallbackTemplateId;
  }

  final date = _readDate(folded);
  final time = _time.firstMatch(folded);
  final wall = time == null
      ? null
      : _wall(int.parse(time.group(1)!), int.parse(time.group(2)!));
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
        _phoneLine.hasMatch(key)) {
      continue;
    }
    final cleaned = cleanMerchant(line, config: cleaning);
    if (cleaned.key.isNotEmpty) {
      return cleaned;
    }
  }
  return null;
}

_Line _buildLine(String s, Currency currency) {
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
      if (_percentAfter.hasMatch(after) ||
          _qtyAfter.hasMatch(after) ||
          _qtyBefore.hasMatch(before) ||
          (!hasPoint &&
              ((m.start > 0 && s[m.start - 1] == '-') ||
                  (after.isNotEmpty && after[0] == '-')))) {
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
      cands.add(_Cand(m.start, m.end, money, strong));
    }
  }
  final labels = isSkip
      ? const <RegExpMatch>[]
      : _totalLabel.allMatches(s).toList(growable: false);
  return _Line(s, cands, isSkip, labels);
}

_Cand? _pick(Iterable<_Cand> cands) {
  _Cand? first;
  for (final c in cands) {
    first ??= c;
    if (c.strong) {
      return c;
    }
  }
  return first;
}

/// The amount for [label] on line [i]: after it, before it, on one of the
/// next two value-only lines, then by column position.
(Money, int)? _amountFor(List<_Line> lines, int i, RegExpMatch label) {
  final line = lines[i];
  final after = _pick(
    line.cands.where((c) => c.start >= label.end && c.start - label.end <= 40),
  );
  if (after != null) {
    return (after.money, _receiptConfidencePermille);
  }
  final before = _pick(
    line.cands.where((c) => c.end <= label.start).toList().reversed,
  );
  if (before != null) {
    return (before.money, _receiptConfidencePermille);
  }
  final block = _columnAmount(lines, i, strict: true);
  if (block != null) {
    return block;
  }
  for (var j = i + 1; j <= i + 2 && j < lines.length; j++) {
    final next = lines[j];
    if (next.isSkip || next.labels.isNotEmpty || !next.isNum) {
      break;
    }
    final c = _pick(next.cands);
    if (c != null) {
      return (c.money, _receiptConfidencePermille);
    }
  }
  return _columnAmount(lines, i);
}

/// Labels and values in separate blocks: the label's row in its run of
/// label-only lines picks the same row in the value-only run after it
/// (aligned to the end when the label run is longer, as headings come
/// first) or before it (equal counts).
(Money, int)? _columnAmount(List<_Line> lines, int i, {bool strict = false}) {
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
      final c = _pick(lines[b + 1 + k].cands);
      if (c != null) {
        return (c.money, _columnConfidencePermille);
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
    final c = _pick(lines[s + (i - a)].cands);
    if (c != null) {
      return (c.money, _columnConfidencePermille);
    }
  }
  return null;
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

WallTime? _wall(int h, int m) => h > 23 || m > 59 ? null : WallTime(h, m);

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
