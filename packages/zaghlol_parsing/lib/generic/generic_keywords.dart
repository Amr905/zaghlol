import '../normalize/text_normalizer.dart';

/// Keyword dictionaries of the generic parser (parsing-engine §7).
///
/// Data only. Every entry is written in natural spelling and folded with
/// [foldKey] once, so it compares against the folded message text. Latin
/// entries must match whole words (the parser checks the boundary); Arabic
/// entries match as substrings, so clitics such as `بخصم` still hit.
List<String> _fold(List<String> words) =>
    List.unmodifiable([for (final w in words) foldKey(w)]);

/// Words that mean money left the account.
final List<String> expenseKeywords = _fold(const [
  'debited',
  'debit',
  'withdrawn',
  'withdrawal',
  'purchase',
  'purchased',
  'spent',
  'paid',
  'payment',
  'charged',
  'sent',
  'pos',
  'خصم',
  'مخصوم',
  'سحب',
  'شراء',
  'مشتريات',
  'دفع',
  'مدفوع',
  'صرف',
  'تحويل صادر',
  'خصمنا',
]);

/// Words that mean money arrived.
final List<String> incomeKeywords = _fold(const [
  'credited',
  'received',
  'deposit',
  'deposited',
  'refund',
  'refunded',
  'reversal',
  'salary',
  'cashback',
  'ايداع',
  'اضافه',
  'استلام',
  'استلمت',
  'تحويل وارد',
  'راتب',
  'استرداد',
  'مرتجع',
  'كاش باك',
]);

/// Words that mean the attempt failed: a failed attempt is not spend.
final List<String> declineKeywords = _fold(const [
  'declined',
  'failed',
  'unsuccessful',
  'insufficient',
  'rejected',
  'رفض',
  'مرفوض',
  'فشل',
  'لم يتم',
  'لم تتم',
  'غير كاف',
]);

/// A number after one of these is a balance or a limit, not the amount.
final List<String> balanceKeywords = _fold(const [
  'balance',
  'avail',
  'limit',
  'رصيد',
  'متاح',
  'الحد',
]);

/// Words that introduce the merchant or the other party.
final Set<String> merchantMarkers = Set.unmodifiable(
  _fold(const ['at', 'to', 'from', 'لدى', 'عند', 'الى', 'من']),
);

/// Words that end a merchant span (and never start one).
final Set<String> merchantStopWords = Set.unmodifiable({
  ...merchantMarkers,
  ..._fold(const [
    'on',
    'using',
    'with',
    'via',
    'ref',
    'reference',
    'card',
    'ending',
    'balance',
    'avail',
    'available',
    'date',
    'time',
    'for',
    'your',
    'my',
    'the',
    'a',
    'an',
    'you',
    'account',
    'acct',
    'in',
    'is',
    'was',
    'has',
    'have',
    'been',
    'and',
    'transaction',
    'txn',
    'trx',
    'successfully',
    'thank',
    'thanks',
    'bank',
    'atm',
    'by',
    'of',
    'amount',
    'has',
    'will',
    'ب',
    'بتاريخ',
    'يوم',
    'الرصيد',
    'رصيد',
    'بطاقه',
    'بطاقتك',
    'رقم',
    'حساب',
    'حسابك',
    'حسابي',
    'في',
    'و',
    'مبلغ',
    'بمبلغ',
    'عبر',
    'الساعه',
    'متاح',
    'المتاح',
    'بنجاح',
    'شكرا',
    'تم',
    'علي',
    'على',
  ]),
});

/// Currency words, symbols aside. Each maps to an ISO code. A word shared by
/// several currencies (`ريال`, `دينار`, `pound`) is absent on purpose: the
/// parser never guesses a currency. Longest first at lookup time.
final Map<String, String> currencyWords = Map.unmodifiable({
  for (final e in const {
    'egyptian pound': 'EGP',
    'egyptian pounds': 'EGP',
    'le': 'EGP',
    'l.e': 'EGP',
    'جنيه مصري': 'EGP',
    'جنيها': 'EGP',
    'جنيه': 'EGP',
    'ج.م': 'EGP',
    'جم': 'EGP',
    'dollar': 'USD',
    'dollars': 'USD',
    'دولار': 'USD',
    'euro': 'EUR',
    'euros': 'EUR',
    'يورو': 'EUR',
    'ريال سعودي': 'SAR',
    'ر.س': 'SAR',
    'درهم اماراتي': 'AED',
    'درهم': 'AED',
    'د.ا': 'AED',
    'دينار كويتي': 'KWD',
    'د.ك': 'KWD',
  }.entries)
    foldKey(e.key): e.value,
});
