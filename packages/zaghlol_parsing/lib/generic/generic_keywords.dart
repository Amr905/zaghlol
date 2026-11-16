import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart' show GenericEvent;

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
  'you sent',
  'sent to',
  'pos',
  'used for',
  'has been used',
  'was used',
  'withdrew',
  'deducted',
  'you transferred',
  'transferred to',
  'transfer of',
  'cash withdrawal',
  'خصم',
  'مخصوم',
  'سحب',
  'شراء',
  'استخدام',
  'استخدمت',
  'مشتريات',
  'دفع',
  'مدفوع',
  'صرف',
  'تحويل صادر',
  'خصمنا',
  'قمت بارسال',
  'ارسلت الي',
  'تم تحويل',
  'سداد',
  // InstaPay / CIB wording: `تم تنفيذ تحويل لحظي ... من حسابك`, `from your
  // account ending`. A transfer out names the reader's own account as the
  // source.
  'تنفيذ تحويل',
  'من حسابك',
  'من حسابكم',
  'from your account',
  'made from your',
]);

/// Expense keywords that flip meaning when the object is the reader
/// (`Ahmed paid you`, `sent to you`): a hit followed by one of these is
/// dropped, so the direction stays unset instead of being guessed. The bare
/// verb `sent` is not a keyword at all (`Ahmed sent you EGP 500` is income),
/// only `you sent` and `sent to`. Folded, matched right after the keyword.
final Map<String, List<String>> addressedToReaderSuffixes = {
  for (final e in const {
    'paid': [' you', ' لك', ' اليك'],
    'charged': [' you'],
    'sent to': [' you'],
    'transferred to': [' you', ' your'],
    'دفع': [' لك', ' اليك'],
    'ارسلت الي': ['ك'],
  }.entries)
    foldKey(e.key): [
      for (final x in e.value)
        x.startsWith(' ') ? ' ${foldKey(x.trim())}' : foldKey(x),
    ],
};

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
  'transferred to your',
  'credited to your',
  'returned',
  'تم رد',
  'رد مبلغ',
  'الى حسابك',
  'لحسابك',
]);

/// Words that name the kind of transaction (FR-PAR-13 event hint). Checked
/// in this order; the first kind with a keyword within [genericEventWindow]
/// characters of the amount wins. A hint only, never a direction.
final List<(GenericEvent, List<String>)> eventKeywords = [
  (
    GenericEvent.refund,
    _fold(const [
      'refund',
      'refunded',
      'reversal',
      'reversed',
      'returned',
      'استرداد',
      'مرتجع',
      'تم رد',
      'رد مبلغ',
    ]),
  ),
  (
    GenericEvent.withdrawal,
    _fold(const [
      'withdrawal',
      'withdrawn',
      'withdrew',
      'atm',
      'cash withdrawal',
      'سحب',
      'صراف',
    ]),
  ),
  (
    GenericEvent.transfer,
    _fold(const [
      'transfer',
      'transferred',
      'you sent',
      'sent to',
      'instapay',
      'ipn',
      'تحويل',
      'قمت بارسال',
      'ارسلت الي',
      'انستاباي',
    ]),
  ),
  (
    GenericEvent.purchase,
    _fold(const [
      'purchase',
      'purchased',
      'pos',
      'spent',
      'used for',
      'has been used',
      'was used',
      'charged',
      'paid at',
      'شراء',
      'مشتريات',
      'استخدام',
    ]),
  ),
];

/// Characters around the amount searched for an event keyword.
const int genericEventWindow = 48;

/// Words that point at the transaction amount without naming a direction
/// (`transfer of`, `بمبلغ`): they help pick the amount among several.
final List<String> amountCueKeywords = _fold(const [
  'transfer',
  'transferred',
  'amount',
  'تحويل',
  'بمبلغ',
  'بقيمه',
  'مبلغ',
  'قيمه',
]);

/// Promotion wording (batch-27 fix). A message with one of these and no
/// [completedTransactionCues] hit is an offer, not a transaction: the generic
/// parser returns unrecognized (it still goes to review; the Guard never
/// drops on promo words globally, PO T-035 Q6).
final List<String> promoKeywords = _fold(const [
  'offer',
  'offers',
  'win',
  'enjoy',
  'chance to',
  'عرض خاص',
  'عروض',
  'اربح',
  'احصل على',
  'استمتع',
]);

/// Words that say money already moved. Any hit overrides [promoKeywords],
/// so `Purchase of EGP 100 at OFFER MART` or `Congratulations! EGP 500 has
/// been credited` stay transactions.
final List<String> completedTransactionCues = _fold(const [
  'debited',
  'debit',
  'charged',
  'credited',
  'paid',
  'received',
  'transferred',
  'purchase',
  'withdrawn',
  'deducted',
  'was used',
  'has been used',
  'transfer of',
  'تم خصم',
  'خصم من',
  'تم تحويل',
  'تم سداد',
  'تم ايداع',
  'تم إضافة',
  'تم شراء',
  'تم استلام',
  'تم صرف',
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
  'outstanding',
  'رصيد',
  'متاح',
  'الحد',
  'المستحق',
]);

/// Short balance words matched only as whole words (`Avl Bal: EGP 10`), so
/// `global` or `total due` elsewhere does not hit.
final List<String> balanceWholeWords = _fold(const [
  'bal',
  'avl',
  'bln',
  'due',
  'minimum',
]);

/// Words that introduce the merchant or the other party.
final Set<String> merchantMarkers = Set.unmodifiable(
  _fold(const [
    'at',
    'to',
    'from',
    'merchant',
    'لدى',
    'عند',
    'الى',
    'من',
    'في',
    'التاجر',
  ]),
);

/// Markers that name a merchant rather than any other party: a span after
/// one of them scores higher.
final Set<String> strongMerchantMarkers = Set.unmodifiable(
  _fold(const ['at', 'merchant', 'لدى', 'عند', 'التاجر']),
);

/// Words that end a merchant span (and never start one).
final Set<String> merchantStopWords = Set.unmodifiable({
  ...merchantMarkers,
  ..._fold(const [
    'on',
    'ببطاقه',
    'برقم',
    'بالرقم',
    'للمزيد',
    'for more',
    'ببطاقتك',
    'بكارت',
    'بتاريخ',
    'بمبلغ',
    'باستخدام',
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
    'into',
    'a/c',
    'avl',
    'bal',
    'limit',
    'made',
    'via',
    'المرجع',
    'مرجع',
    'التاريخ',
    'لحسابك',
    'لحسابكم',
    'حسابكم',
    'بطاقتكم',
    'الحالي',
    'كارت',
    'بكارت',
    'البطاقه',
    'ref',
    'ref.',
    'reference',
    'رصيدك',
    'ماكينه',
    'الصراف',
    'صراف',
    'بالبطاقه',
    'بالكارت',
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
    'جنيه استرليني': 'GBP',
    'استرليني': 'GBP',
    'pound sterling': 'GBP',
    'جنيهات': 'EGP',
    'جنيها': 'EGP',
    'ج م': 'EGP',
    'جنيه': 'EGP',
    'ج.م': 'EGP',
    'جم': 'EGP',
    'dollar': 'USD',
    'dollars': 'USD',
    'دولار امريكي': 'USD',
    'دولار': 'USD',
    'euro': 'EUR',
    'euros': 'EUR',
    'يورو': 'EUR',
    'ريال سعودي': 'SAR',
    'ر.س': 'SAR',
    'ريال قطري': 'QAR',
    'دينار اردني': 'JOD',
    'درهم اماراتي': 'AED',
    'درهم': 'AED',
    'د.ا': 'AED',
    'دينار كويتي': 'KWD',
    'د.ك': 'KWD',
  }.entries)
    foldKey(e.key): e.value,
});

/// Letter prefixes before `$` or `£` (folded, lowercase) and the currency
/// they make (batch 25: `A$` is never USD). A letter prefix not listed here
/// makes the symbol unreadable, so no currency is guessed.
const Map<String, String> prefixedSymbols = {
  r'us$': 'USD',
  r'a$': 'AUD',
  r'au$': 'AUD',
  r'c$': 'CAD',
  r'ca$': 'CAD',
  r's$': 'SGD',
  r'nz$': 'NZD',
  r'hk$': 'HKD',
  'e£': 'EGP',
  'le£': 'EGP',
};

/// SMS-AUTO: a credit-card word. A settlement cue counts only next to one,
/// so "we received your payment" from a shop is not a card settlement.
final List<String> cardWords = _fold(const [
  'credit card',
  'creditcard',
  'card ending',
  'your card',
  'بطاقه ائتمان',
  'بطاقه الائتمان',
  'بطاقتك',
  'بطاقه',
  'كريديت',
  'كارد',
]);

/// SMS-AUTO: the card account received a payment (the settlement leg that
/// lands on the card): stored as a transfer in. Synthetic-unverified wording.
final List<String> cardSettlementReceivedCues = _fold(const [
  'payment received',
  'payment has been received',
  'payment was received',
  'received your payment',
  'we have received your payment',
  'payment credited',
  'payment has been credited',
  'payment posted',
  'payment was posted',
  'thank you for your payment',
  'thanks for your payment',
  'repayment received',
  'تم استلام سداد',
  'تم استلام دفعه',
  'تم استلام مبلغ',
  'تم استلام دفعتك',
  'استلمنا دفعتك',
  'استلمنا سداد',
  'تم تسجيل سداد',
  'تم قيد سداد',
  'شكرا لسدادك',
  'شكرا علي سدادك',
]);

/// Only the unambiguous received-side wording of [cardSettlementReceivedCues]
/// counts without a "received/credited/posted" word next to "payment of";
/// "payment of" needs one of these in the same message.
final List<String> cardSettlementReceivedVerbs = _fold(const [
  'received',
  'credited',
  'posted',
  'thank you',
  'thanks',
  'استلام',
  'استلمنا',
  'تسجيل',
  'قيد',
  'شكرا',
]);

/// SMS-AUTO: money left the paying account towards a credit card (the
/// settlement leg that leaves an account): stored as a transfer out. Needs a
/// debit word as well, so the side is never guessed.
final List<String> cardSettlementPaidCues = _fold(const [
  'credit card payment',
  'card payment',
  'payment to your credit card',
  'payment towards your',
  'payment to credit card',
  'paid your credit card',
  'pay your credit card',
  'credit card bill',
  'card bill',
  'card repayment',
  'transferred to your credit card',
  'transfer to your credit card',
  'سداد بطاقه',
  'سداد فاتوره بطاقه',
  'سداد مستحقات بطاقه',
  'سداد البطاقه',
  'سداد بطاقتك',
  'دفع فاتوره بطاقه',
  'تسديد بطاقه',
  'تسديد البطاقه',
  'تحويل الي بطاقه',
  'تحويل الى بطاقه',
]);

final List<String> cardSettlementDebitWords = _fold(const [
  'debited',
  'deducted',
  'withdrawn',
  'you paid',
  'you transferred',
  'from your account',
  'from account',
  'from a/c',
  'خصم',
  'تم خصم',
  'تم سحب',
  'من حسابك',
]);
