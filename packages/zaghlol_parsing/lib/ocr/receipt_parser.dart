import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../pipeline/parse_result.dart';
import '../pipeline/parsing_pipeline.dart' show resolveOccurredAt;
import '../registry/registry_models.dart';

/// Confidence of a receipt read without a bank template (never auto-accepted;
/// the confirmation screen always shows it anyway).
const int _receiptConfidencePermille = 600;

/// Words that label the amount to pay on a till receipt, English and Arabic
/// (already folded: `الإجمالي` is `الاجمالي`). A bare `total` after `sub` is
/// the subtotal and is skipped by the look-behinds. Linear: no nested
/// quantifiers.
final RegExp _totalLabel = RegExp(
  r'(?<![a-z])(?<!sub)(?<!sub )(?:grand total|total due|amount due|net total|total amount|total)(?![a-z])'
  r'|الاجمالي|اجمالي|المجموع|المطلوب|صافي المبلغ',
);

final RegExp _numberToken = RegExp(r'[0-9][0-9,]*(?:\.[0-9]{1,3})?');
final RegExp _currencyToken = RegExp(
  r'(?<![a-z])(egp|usd|eur|gbp|sar|aed|kwd|qar)(?![a-z])|جم|جنيه|ج\.م|\$|€|£',
);
final RegExp _dmy = RegExp(
  r'(?<![0-9])(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?![0-9])',
);
final RegExp _ymd = RegExp(r'(?<![0-9])(\d{4})-(\d{1,2})-(\d{1,2})(?![0-9])');
final RegExp _time = RegExp(r'(?<![0-9])(\d{1,2}):(\d{2})(?![0-9:])');
final RegExp _letters = RegExp(r'[a-zء-ي]');

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

/// Reads a till receipt from OCR text: the last "total" amount, the first
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

  Money? amount;
  for (final label in _totalLabel.allMatches(folded)) {
    final end = label.end;
    final window = folded.substring(
      end,
      end + 32 > folded.length ? folded.length : end + 32,
    );
    final n = _numberToken.firstMatch(window);
    if (n == null) {
      continue;
    }
    final parsed = parseAmount(n.group(0)!, currency: currency);
    final money = parsed.valueOrNull;
    if (money != null && money.isPositive) {
      amount = money;
    }
  }
  if (amount == null) {
    return const ParseUnrecognized(UnrecognizedReason.genericNoAmount);
  }

  final date = _readDate(folded);
  final time = _time.firstMatch(folded);
  final wall = time == null
      ? null
      : _wall(int.parse(time.group(1)!), int.parse(time.group(2)!));
  final (occurredAt, source) = resolveOccurredAt(date, wall, receivedAt);

  CleanedMerchant? merchant;
  for (final raw in text.split('\n').take(6)) {
    final line = raw.trim();
    final key = line.toLowerCase();
    if (!_letters.hasMatch(key) ||
        _headingWords.any(key.contains) ||
        _totalLabel.hasMatch(key)) {
      continue;
    }
    final cleaned = cleanMerchant(line, config: cleaning);
    if (cleaned.key.isNotEmpty) {
      merchant = cleaned;
      break;
    }
  }

  return ParseParsed(
    institutionCode: 'ocr_receipt',
    templateId: 'ocr.receipt.generic',
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
      merchant: merchant,
      counterparty: null,
      ref: null,
      date: date,
      time: wall,
      occurredAt: occurredAt,
      occurredAtSource: source,
    ),
    confidencePermille: _receiptConfidencePermille,
    reasons: const [],
  );
}

String _markerKey(String m) => switch (m) {
  'جم' || 'جنيه' || 'ج.م' => 'EGP',
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
