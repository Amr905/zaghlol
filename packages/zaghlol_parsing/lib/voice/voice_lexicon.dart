/// Word tables of the voice parser (T-109): Egyptian and English number
/// words, currency words, verbs, fillers. Keys are stored folded with
/// [foldKey], so lookups use folded token keys. Data only.
library;

import '../normalize/text_normalizer.dart';

enum LexKind {
  unit,
  teen,
  tens,
  hundred, // 100, also the "x hundred" multiplier
  hundredCompound, // 200..900 in one word
  thousand, // الف, also the multiplier
  thousandPlural, // الاف / تلاف: multiplier only
  thousandDual, // الفين
  million,
  millionDual,
  fraction,
  article, // English a / an before hundred / thousand
  currency,
  subunit, // قرش
  conj,
  verb,
  stop,
  measure,
  kSuffix,
}

final class Lex {
  const Lex(
    this.kind, {
    this.value = 0,
    this.den = 1,
    this.code,
    this.ambiguous = false,
    this.sterling = false,
  });

  final LexKind kind;

  /// Number value; for fractions the numerator.
  final int value;

  /// Fraction denominator.
  final int den;

  /// Currency ISO code (null for an ambiguous currency word).
  final String? code;
  final bool ambiguous;

  /// `جنيه` can be followed by `استرليني` (GBP).
  final bool sterling;
}

final Map<String, Lex> lexicon = _build();

Map<String, Lex> _build() {
  final m = <String, Lex>{};
  void add(Iterable<String> words, Lex lex) {
    for (final w in words) {
      m[foldKey(w)] = lex;
    }
  }

  // Units 1..9 (Egyptian, MSA, English).
  const units = <int, List<String>>{
    1: ['واحد', 'واحدة', 'one'],
    2: ['اتنين', 'اثنين', 'اثنان', 'اتنان', 'two'],
    3: ['تلاتة', 'تلات', 'ثلاثة', 'ثلاث', 'three'],
    4: ['اربعة', 'أربعة', 'اربع', 'أربع', 'four'],
    5: ['خمسة', 'خمس', 'five'],
    6: ['ستة', 'ست', 'six'],
    7: ['سبعة', 'سبع', 'seven'],
    8: ['تمانية', 'تمنية', 'ثمانية', 'تمان', 'ثمان', 'eight'],
    9: ['تسعة', 'تسع', 'nine'],
  };
  units.forEach((v, ws) => add(ws, Lex(LexKind.unit, value: v)));

  add(['عشرة', 'عشر', 'ten'], const Lex(LexKind.teen, value: 10));
  const teens = <int, List<String>>{
    11: ['حداشر', 'احداشر', 'احدعشر', 'eleven'],
    12: ['اتناشر', 'اطناشر', 'اثناعشر', 'twelve'],
    13: ['تلتاشر', 'تلاتاشر', 'تلطاشر', 'thirteen'],
    14: ['ربعتاشر', 'اربعتاشر', 'اربعطاشر', 'fourteen'],
    15: ['خمستاشر', 'خمسطاشر', 'fifteen'],
    16: ['ستاشر', 'سطاشر', 'sixteen'],
    17: ['سبعتاشر', 'سبعطاشر', 'seventeen'],
    18: ['تمنتاشر', 'تمانتاشر', 'تمنطاشر', 'eighteen'],
    19: ['تسعتاشر', 'تسعطاشر', 'nineteen'],
  };
  teens.forEach((v, ws) => add(ws, Lex(LexKind.teen, value: v)));

  const tens = <int, List<String>>{
    20: ['عشرين', 'عشرون', 'twenty'],
    30: ['تلاتين', 'ثلاثين', 'ثلاثون', 'thirty'],
    40: ['اربعين', 'أربعين', 'أربعون', 'forty'],
    50: ['خمسين', 'خمسون', 'fifty'],
    60: ['ستين', 'ستون', 'sixty'],
    70: ['سبعين', 'سبعون', 'seventy'],
    80: ['تمانين', 'ثمانين', 'ثمانون', 'eighty'],
    90: ['تسعين', 'تسعون', 'ninety'],
  };
  tens.forEach((v, ws) => add(ws, Lex(LexKind.tens, value: v)));

  add([
    'ميه',
    'مية',
    'ميت',
    'مايه',
    'مائه',
    'مئه',
    'hundred',
  ], const Lex(LexKind.hundred, value: 100));
  add([
    'ميتين',
    'مئتين',
    'مائتين',
    'مايتين',
  ], const Lex(LexKind.hundredCompound, value: 200));
  const hundredPrefixes = <int, List<String>>{
    3: ['تلت', 'تلات', 'ثلاث', 'ثلث'],
    4: ['ربع', 'اربع', 'أربع'],
    5: ['خمس'],
    6: ['ست', 'س'],
    7: ['سبع'],
    8: ['تمن', 'تمان', 'ثمان', 'ثمن'],
    9: ['تسع'],
  };
  const hundredSuffixes = ['ميه', 'مية', 'ميت', 'مايه', 'مائه', 'مئه'];
  hundredPrefixes.forEach((v, ps) {
    for (final p in ps) {
      for (final s in hundredSuffixes) {
        add(['$p$s'], Lex(LexKind.hundredCompound, value: v * 100));
      }
    }
  });

  add(['الف', 'ألف', 'thousand'], const Lex(LexKind.thousand, value: 1000));
  add(['الاف', 'آلاف', 'تلاف'], const Lex(LexKind.thousandPlural));
  add(['الفين', 'ألفين'], const Lex(LexKind.thousandDual));
  add(['مليون', 'million'], const Lex(LexKind.million));
  add(['مليونين'], const Lex(LexKind.millionDual));
  add(['k'], const Lex(LexKind.kSuffix));

  add(['نص', 'نصف', 'half'], const Lex(LexKind.fraction, value: 1, den: 2));
  add(['ربع', 'quarter'], const Lex(LexKind.fraction, value: 1, den: 4));
  add(['تلت', 'ثلث'], const Lex(LexKind.fraction, value: 1, den: 3));
  add(['a', 'an'], const Lex(LexKind.article));

  // Currencies. `value` is the implicit count of a bare word (1) or a dual
  // word (2).
  Lex cur(String code, {int count = 1, bool sterling = false}) =>
      Lex(LexKind.currency, value: count, code: code, sterling: sterling);
  add([
    'جنيه',
    'جنية',
    'جنيها',
    'جنيهات',
    'ج',
    'egp',
    'le',
    'pound',
    'pounds',
  ], cur('EGP', sterling: true));
  add(['جنيهين'], cur('EGP', count: 2));
  add(['دولار', 'دولارات', r'$', 'usd', 'dollar', 'dollars'], cur('USD'));
  add(['دولارين'], cur('USD', count: 2));
  add(['يورو', '€', 'eur', 'euro', 'euros'], cur('EUR'));
  add(['ريال', 'ريالات', 'sar', 'riyal', 'riyals'], cur('SAR'));
  add(['ريالين'], cur('SAR', count: 2));
  add(['درهم', 'دراهم', 'aed', 'dirham', 'dirhams'], cur('AED'));
  add(['£', 'gbp'], cur('GBP'));
  add(['kwd'], cur('KWD'));
  add(['qar'], cur('QAR'));
  add([
    'دينار',
    'دنانير',
  ], const Lex(LexKind.currency, value: 1, ambiguous: true));
  add(['قرش', 'قروش'], const Lex(LexKind.subunit, value: 1));
  add(['قرشين'], const Lex(LexKind.subunit, value: 2));

  add([
    'و',
    'and',
    '،',
    ',',
    ';',
    '؛',
    '&',
    'ثم',
    'كمان',
    'plus',
    'then',
  ], const Lex(LexKind.conj));

  add([
    'دفعت',
    'دفعنا',
    'دفع',
    'اشتريت',
    'اشترينا',
    'اشتري',
    'صرفت',
    'صرفنا',
    'صرف',
    'طلعت',
    'حاسبت',
    'سددت',
    'جبت',
    'جيبت',
    'خدت',
    'اخدت',
    'كلفني',
    'كلفتني',
    'كلفت',
    'اتصرف',
    'اتدفع',
    'سجل',
    'سجلي',
    'سجللي',
    'ضيف',
    'ضيفلي',
    'حط',
    'حطلي',
    'هات',
    'انا',
    'لسه',
    'سلفت',
    'paid',
    'pay',
    'bought',
    'buy',
    'spent',
    'spend',
    'got',
    'get',
    'had',
    'i',
    'record',
    'log',
    'add',
    'just',
    'my',
  ], const Lex(LexKind.verb));

  add([
    'على',
    'في',
    'عشان',
    'علشان',
    'حق',
    'تمن',
    'ثمن',
    'من',
    'عن',
    'ده',
    'دي',
    'دا',
    'النهارده',
    'انهارده',
    'اليوم',
    'مصري',
    'استرليني',
    'for',
    'on',
    'at',
    'of',
    'the',
    'to',
    'some',
    'in',
    'today',
    'me',
  ], const Lex(LexKind.stop));

  add([
    'كيلو',
    'كيلوجرام',
    'جرام',
    'جم',
    'لتر',
    'كيس',
    'علبه',
    'قطعه',
    'دسته',
    'رغيف',
    'طبق',
    'حته',
    'kilo',
    'kg',
    'gram',
    'liter',
    'litre',
  ], const Lex(LexKind.measure));

  return m;
}

/// Words that start with `و` and are not "and + word" (never stripped).
final Set<String> waWords = {
  for (final w in [
    'وقود',
    'وجبة',
    'وجبات',
    'ورق',
    'وصلة',
    'وردة',
    'ورد',
    'وكالة',
    'وظيفة',
    'ودائع',
    'وديعة',
    'وسط',
    'ولاد',
    'وليد',
    'واي',
    'وايفاي',
    'واتساب',
    'وان',
    'ويندوز',
    'وزن',
    'وحدة',
    'وصفة',
    'وثيقة',
  ])
    foldKey(w),
  'wifi',
};
