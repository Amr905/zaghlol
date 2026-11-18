import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  group('backtrackingProblems', () {
    final rows = <(String, String, List<String>)>[
      ('plain literal', 'تم خصم', []),
      ('digits with group', r'(\d{4})', []),
      ('lazy wildcards', r'a.*?b.*?c', []),
      ('optional group with unbounded inside', r'x(?:.*?y (\d+))?', []),
      ('bounded repeat of group', r'(?:\d+,){1,3}', []),
      ('alternation of distinct words', r'(?:يوم|في)+', []),
      ('class with specials', r'[\d,.()+*]+', []),
      ('escaped specials', r'\(\d+\)\*', []),
      ('nested plus', r'(a+)+b', ['nested_quantifier']),
      ('nested star in group', r'(?:x.*)*y', ['nested_quantifier']),
      ('nested with brace', r'(\d+){2,}', ['nested_quantifier']),
      ('nested through inner group', r'((a+)b)+', ['nested_quantifier']),
      ('duplicate alternatives', r'(?:a|a)*', ['ambiguous_alternation']),
      (
        'duplicate group alternatives',
        r'(?:(ab)|(ab))+',
        ['ambiguous_alternation'],
      ),
      ('empty alternative', r'(?:a|)+', ['ambiguous_alternation']),
      ('word-or-digit overlap', r'(\w|\d)+x', ['ambiguous_alternation']),
      ('dot-or-space overlap', r'(?:.|\s)*x', ['ambiguous_alternation']),
      ('class overlap', r'(?:[a-z]|[a-f])+', ['ambiguous_alternation']),
      ('disjoint single chars', r'(?:a|b|\d)+', []),
      ('disjoint classes', r'(?:[a-z]|\d)+', []),
      ('lookahead', r'a(?=b)', ['lookaround']),
      ('negative lookbehind', r'(?<!a)b', ['lookaround']),
      ('backreference', r'(a)\1', ['backreference']),
      ('named group is not lookaround', r'(?<amount>\d+)', []),
      (
        'seven unbounded wildcards',
        r'.*a.*b.*c.*d.*e.*f.*g.*',
        ['too_many_wildcards'],
      ),
      ('six unbounded wildcards ok', r'.*a.*b.*c.*d.*e.*f', []),
      ('too long', 'a' * 601, ['too_long']),
      (
        'bounded repeat of inner unbounded, 50',
        r'(a+){1,50}b',
        ['nested_bounded_quantifier'],
      ),
      (
        'bounded repeat of inner unbounded, 4',
        r'(?:\d+,){4}',
        ['nested_bounded_quantifier'],
      ),
      ('exact repeat 3 of inner unbounded is accepted', r'(?:\d+,){3}', []),
      ('bounded repeat of a bounded group', r'(?:\d{1,3},){1,50}', []),
      (
        'prefix alternatives in a repeating group',
        r'(?:a|aa)+b',
        ['ambiguous_alternation'],
      ),
      ('prefix alternatives (a|ab)*', r'(a|ab)*c', ['ambiguous_alternation']),
      ('x and x? alternatives', r'(?:a|a?)+b', ['ambiguous_alternation']),
      ('x and x? once is accepted', r'(?:a|a?)b', []),
      ('prefix alternatives once is accepted', r'(?:ج|جم) ', []),
      ('escaped question mark is not optional', r'(?:b|a\?)+c', []),
    ];
    for (final (name, pattern, expected) in rows) {
      test(name, () => expect(backtrackingProblems(pattern), expected));
    }

    test('never throws on arbitrary text', () {
      const pieces = [
        '(',
        ')',
        '|',
        '*',
        '+',
        '?',
        '{',
        '}',
        r'\',
        '[',
        ']',
        'a',
        '.',
      ];
      var seed = 7;
      for (var i = 0; i < 3000; i++) {
        final b = StringBuffer();
        for (var k = 0; k < 14; k++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          b.write(pieces[seed % pieces.length]);
        }
        backtrackingProblems(b.toString());
        compilePattern(b.toString());
      }
    });
  });

  group('compilePattern', () {
    test('accepts and drops a leading inline case flag', () {
      final p = compilePattern(r'(?i)\botp\b');
      expect(p, isNotNull);
      expect(p!.source, r'(?i)\botp\b');
      expect(p.regex.hasMatch('your otp is'), isTrue);
    });

    test('other inline flags and invalid syntax fail', () {
      expect(compilePattern('(?s)a'), isNull);
      expect(compilePattern('a('), isNull);
      expect(compilePattern(''), isNull);
    });

    test('pattern letters are folded like the body', () {
      final p = compilePattern('إيداع بطاقة')!;
      expect(p.regex.hasMatch(foldKey('ايداع بطاقه')), isTrue);
    });

    test('folding the pattern keeps escapes intact', () {
      expect(compilePattern(r'\S+\D\W')!.regex.hasMatch('a1-'), isFalse);
      expect(compilePattern(r'\S+\D\W')!.regex.hasMatch('ab-'), isTrue);
    });
  });

  group('accepted shapes stay fast on hostile input', () {
    test('safe lazy templates finish a 2000-char adversarial body quickly', () {
      final p = compilePattern(
        r'تم خصم (?<amount>[\d,.]+) .*?بطاقة .*?\*\*(?<last4>\d{4}) لدى (?<merchant>.+?) يوم',
      )!;
      expect(backtrackingProblems(p.source), isEmpty);
      final hostile = '${'تم خصم 1 ' * 200}${' ' * 200}';
      expect(p.regex.hasMatch(hostile), isFalse);
    });

    test('safe lazy templates match a hostile body within 50 ms', () {
      final p = compilePattern(
        r'تم خصم (?<amount>[\d,.]+) .*?بطاقة .*?\*\*(?<last4>\d{4}) لدى (?<merchant>.+?) يوم',
      )!;
      final hostile = '${'تم خصم 1 ' * 200}${' ' * 200}';
      final sw = Stopwatch()..start();
      p.regex.hasMatch(hostile);
      expect(sw.elapsedMilliseconds, lessThan(50));
    }, tags: 'benchmark');
  });

  group('match budget (FU-074)', () {
    test('a stalled regex is quarantined after repeated overruns', () {
      final slow = RegExp(r'^(a+)+$');
      final input = '${'a' * 24}!';
      expect(isRegexQuarantined(slow), isFalse);
      for (var i = 0; i < quarantineStrikes; i++) {
        expect(isRegexQuarantined(slow), isFalse);
        expect(
          budgetedFirstMatch(
            slow,
            input,
            budget: const Duration(milliseconds: 1),
          ),
          isNull,
        );
      }
      expect(isRegexQuarantined(slow), isTrue);
      // Later calls return at once, even for input that would match.
      final w = Stopwatch()..start();
      expect(budgetedFirstMatch(slow, 'aaa'), isNull);
      expect(w.elapsedMilliseconds, lessThan(5));
    });

    test('a single over-budget run does not quarantine', () {
      final r = RegExp(r'(\d+)');
      budgetedFirstMatch(r, 'x 12', budget: const Duration(microseconds: -1));
      expect(isRegexQuarantined(r), isFalse);
      expect(budgetedFirstMatch(r, 'x 12')?.group(1), '12');
    });

    test('a quarantined drop pattern counts as a match (fail closed)', () {
      final r = RegExp('otp');
      for (var i = 0; i < quarantineStrikes; i++) {
        budgetedFirstMatch(r, 'x', budget: const Duration(microseconds: -1));
      }
      expect(budgetedHasMatch(r, 'hello'), isFalse);
      expect(budgetedHasMatch(r, 'hello', dropPattern: true), isTrue);
    });

    test('a fast regex is never quarantined and still matches', () {
      final r = RegExp(r'(\d+)');
      expect(budgetedFirstMatch(r, 'x 12')?.group(1), '12');
      expect(budgetedHasMatch(r, 'none'), isFalse);
      expect(isRegexQuarantined(r), isFalse);
    });
  });
}
