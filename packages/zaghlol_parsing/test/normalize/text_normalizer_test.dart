import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

typedef _Row = (String name, String input, String expected);

void main() {
  group('normalizeText', () {
    final rows = <_Row>[
      ('arabic-indic digits', '٠١٢٣٤٥٦٧٨٩', '0123456789'),
      ('extended digits', '۰۱۲۳۴۵۶۷۸۹', '0123456789'),
      ('decimal separator', '١٢٫٥٠', '12.50'),
      ('thousands separator', '١٬٢٥٠', '1,250'),
      ('nbsp', 'a b', 'a b'),
      ('narrow nbsp', 'a b', 'a b'),
      ('thin space', 'a b', 'a b'),
      ('zero width', 'a\u200Bb\u200Cc\u200Dd', 'abcd'),
      ('word joiner and soft hyphen', 'a\u2060b\u00ADc', 'abc'),
      ('rtl and ltr marks', '\u200F١٢٣\u200E', '123'),
      ('embedding controls', '\u202A1\u202B2\u202C3\u202D4\u202E', '1234'),
      ('isolates', '\u20661\u20672\u20683\u2069', '123'),
      ('arabic letter mark', '\u061C12', '12'),
      ('bom', '\uFEFF12', '12'),
      ('whitespace runs', '  a \t\n b  ', 'a b'),
      ('arabic comma kept', 'أ،ب', 'أ،ب'),
      ('tatweel kept at display level', 'محمـد', 'محمـد'),
      ('letters kept at display level', 'أحمد', 'أحمد'),
      ('empty', '', ''),
    ];
    for (final (name, input, expected) in rows) {
      test(name, () => expect(normalizeText(input), expected));
    }
  });

  group('foldForMatching', () {
    final rows = <_Row>[
      ('tatweel', 'محمـــد', 'محمد'),
      ('harakat', 'مُحَمَّد', 'محمد'),
      ('dagger alef', 'هٰذا', 'هذا'),
      ('digits too', 'مبلغ ١٢٫٥', 'مبلغ 12.5'),
      ('tatweel between spaces', 'a ـ b', 'a b'),
      ('letters not folded', 'أحمد مدرسة', 'أحمد مدرسة'),
    ];
    for (final (name, input, expected) in rows) {
      test(name, () => expect(foldForMatching(input), expected));
    }
  });

  group('foldKey', () {
    final rows = <_Row>[
      ('alef hamza above', 'أحمد', 'احمد'),
      ('alef hamza below', 'إيمان', 'ايمان'),
      ('alef madda', 'آمن', 'امن'),
      ('alef wasla', 'ٱسم', 'اسم'),
      ('alef maksura', 'مصطفى', 'مصطفي'),
      ('teh marbuta', 'مدرسة', 'مدرسه'),
      ('ascii lowercase', 'CARREFOUR Maadi', 'carrefour maadi'),
      ('all levels together', 'أَحْمَـد ١٢', 'احمد 12'),
    ];
    for (final (name, input, expected) in rows) {
      test(name, () => expect(foldKey(input), expected));
    }
  });

  group('foldArabicVariants', () {
    test('folds letter variants and marks, keeps case and escapes', () {
      expect(foldArabicVariants('أإآٱ ى ة'), 'اااا ي ه');
      expect(foldArabicVariants('جـنيه \\S\\D ABC'), 'جنيه \\S\\D ABC');
      expect(foldArabicVariants('أَحْمَد'), 'احمد');
    });
  });

  group('fuzz', () {
    final random = Random(13);
    const pool = <int>[
      0x20, 0x09, 0x0A, 0xA0, 0x202F, 0x2009, 0x200B, 0x200F, 0x202A, 0x2066,
      0x061C, 0xFEFF, 0x0640, 0x064B, 0x0652, 0x0670, 0x0623, 0x0625, 0x0622,
      0x0671, 0x0649, 0x0629, 0x0660, 0x0669, 0x06F0, 0x06F9, 0x066B, 0x066C,
      0x41, 0x5A, 0x61, 0x31, 0x2E, 0x2C, 0xD800, 0xDC00, //
    ];

    String randomText() {
      final length = random.nextInt(24);
      final units = List<int>.generate(length, (_) {
        return random.nextBool()
            ? pool[random.nextInt(pool.length)]
            : random.nextInt(0x10000);
      });
      return String.fromCharCodes(units);
    }

    bool hasForbidden(String text) {
      for (final u in text.codeUnits) {
        final removed =
            (u >= 0x200B && u <= 0x200F) ||
            (u >= 0x202A && u <= 0x202E) ||
            (u >= 0x2066 && u <= 0x2069) ||
            u == 0x061C ||
            u == 0x2060 ||
            u == 0x00AD ||
            u == 0xFEFF ||
            u == 0x0640 ||
            (u >= 0x064B && u <= 0x0652) ||
            u == 0x0670;
        final folded =
            u == 0x0623 ||
            u == 0x0625 ||
            u == 0x0622 ||
            u == 0x0671 ||
            u == 0x0649 ||
            u == 0x0629 ||
            (u >= 0x41 && u <= 0x5A);
        if (removed || folded) {
          return true;
        }
      }
      return false;
    }

    test('never throws and is idempotent', () {
      for (var i = 0; i < 3000; i++) {
        final s = randomText();
        for (final f in [normalizeText, foldForMatching, foldKey]) {
          final once = f(s);
          expect(f(once), once);
        }
      }
    });

    test('foldKey output has no removed or folded code points', () {
      for (var i = 0; i < 3000; i++) {
        expect(hasForbidden(foldKey(randomText())), isFalse);
      }
    });

    test('foldKeyLines is foldKey with each line break run as one \\n', () {
      const breaks = [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029];
      for (var i = 0; i < 3000; i++) {
        final base = randomText();
        // Splice line breaks in, so most inputs carry some.
        final units = [...base.codeUnits];
        for (var k = random.nextInt(4); k > 0; k--) {
          units.insert(
            random.nextInt(units.length + 1),
            breaks[random.nextInt(breaks.length)],
          );
        }
        final s = String.fromCharCodes(units);
        final lines = foldKeyLines(s);
        expect(lines.replaceAll('\n', ' '), foldKey(s));
        expect(foldKeyLines(lines), lines);
        expect(lines, equals(lines.trim()));
        for (final bad in [' \n', '\n ', '\n\n', '  ']) {
          expect(lines.contains(bad), isFalse);
        }
        for (final u in lines.codeUnits) {
          // Only LF survives; every other line break folds to it.
          expect(u != 0x0A && breaks.contains(u), isFalse);
        }
      }
    });

    test('output never has leading, trailing or doubled spaces', () {
      for (var i = 0; i < 1000; i++) {
        final out = foldKey(randomText());
        expect(out, equals(out.trim()));
        expect(out.contains('  '), isFalse);
      }
    });
  });

  group('foldKeyIndexed', () {
    test('text equals foldKey on rows and random input', () {
      const rows = [
        '',
        '   ',
        'أحمد  محمـد',
        '\u200f١٢٣\u200e abc  DEF',
        'a\u00A0\u00A0b\tc',
        '\u200b \u200b x',
        'ة ى أ إ آ ٱ',
        '😀 x 😀',
      ];
      for (final r in rows) {
        expect(foldKeyIndexed(r).text, foldKey(r));
      }
      final rnd = Random(7);
      const pool = [
        'a',
        'B',
        ' ',
        '\u00A0',
        '\u0640',
        '\u064B',
        '\u200f',
        '٣',
        'ة',
        'أ',
        'ى',
        '\u2060',
        '\n',
        '😀',
        'ي',
        '.',
      ];
      for (var i = 0; i < 3000; i++) {
        final b = StringBuffer();
        for (var k = rnd.nextInt(24); k >= 0; k--) {
          b.write(pool[rnd.nextInt(pool.length)]);
        }
        final input = b.toString();
        final f = foldKeyIndexed(input);
        expect(f.text, foldKey(input));
        expect(f.origin.length, f.text.length);
        for (var j = 1; j < f.origin.length; j++) {
          expect(f.origin[j], greaterThan(f.origin[j - 1]));
        }
        for (final o in f.origin) {
          expect(o, inInclusiveRange(0, input.length - 1));
        }
      }
    });

    test('a folded span maps back to the original text', () {
      const original = 'خصم  لـدى إيمان  و أحمد';
      final f = foldKeyIndexed(original);
      final start = f.text.indexOf('ايمان');
      expect(start, isNonNegative);
      expect(f.originalSpan(original, start, start + 5), 'إيمان');
      final two = f.text.indexOf('ايمان و احمد');
      expect(f.originalSpan(original, two, two + 12), 'إيمان  و أحمد');
    });

    test('tatweel inside a span stays in the original span', () {
      const original = 'to مـحمد now';
      final f = foldKeyIndexed(original);
      final start = f.text.indexOf('محمد');
      expect(f.originalSpan(original, start, start + 4), 'مـحمد');
    });

    test('empty and out-of-range spans are null', () {
      final f = foldKeyIndexed('abc');
      expect(f.originalSpan('abc', 1, 1), isNull);
      expect(f.originalSpan('abc', -1, 2), isNull);
      expect(f.originalSpan('abc', 0, 9), isNull);
    });
  });
}
