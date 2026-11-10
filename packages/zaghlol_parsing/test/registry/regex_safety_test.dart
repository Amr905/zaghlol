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
      final sw = Stopwatch()..start();
      p.regex.hasMatch(hostile);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });
}
