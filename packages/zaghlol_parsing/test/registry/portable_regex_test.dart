import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

void main() {
  group('guardPatternText', () {
    test('strips a leading (?i) only', () {
      expect(guardPatternText('(?i)otp'), 'otp');
      expect(guardPatternText('a(?i)b'), 'a(?i)b');
    });

    test('folds Arabic letter variants, tatweel and harakat', () {
      expect(guardPatternText('كلمة المرور المؤقتة'), 'كلمه المرور المؤقته');
      expect(guardPatternText('الأمان'), 'الامان');
      expect(guardPatternText('خـصْم'), 'خصم');
      expect(guardPatternText('مصرى'), 'مصري');
    });
  });

  group('portableRegexProblems rejects', () {
    final cases = <String, String>{
      'OTP': 'uppercase',
      r'\botp\b': 'shorthand_escape',
      r'\B': 'shorthand_escape',
      r'\w+': 'shorthand_escape',
      r'\W': 'shorthand_escape',
      r'\d{4}': 'shorthand_escape',
      r'\D': 'shorthand_escape',
      r'\s': 'shorthand_escape',
      r'\S': 'shorthand_escape',
      r'\p{L}': 'shorthand_escape',
      r'\u0660': 'shorthand_escape',
      r'\x41': 'shorthand_escape',
      r'(a)\1': 'backreference',
      r'(?<n>a)\k<n>': 'backreference',
      'a\nb': 'control_char',
      'a\tb': 'control_char',
      r'\t': 'escape',
      r'\-': 'escape',
      'a(?i)b': 'inline_flag',
      '(?m)^a': 'inline_flag',
      'a(?=b)': 'lookaround',
      'a(?!b)': 'lookaround',
      '(?<=a)b': 'lookaround',
      '(?<!a)b': 'lookaround',
      '(?<name>a)': 'named_group',
      '(?>a)': 'atomic_group',
      'a*+': 'possessive',
      'a++': 'possessive',
      'a?+': 'possessive',
      'a{2}+': 'possessive',
      '[[:alpha:]]': 'posix_class',
      '[a[b]]': 'nested_class',
      '[a&&b]': 'class_set_operation',
      '[a--b]': 'class_set_operation',
      '[]a]': 'nested_class',
    };
    for (final e in cases.entries) {
      test('${e.key} → ${e.value}', () {
        expect(portableRegexProblems(e.key), contains(e.value));
      });
    }

    test('more than one capture group in last4', () {
      expect(portableRegexProblems('(a)([0-9]{4})', maxCaptureGroups: 1), [
        'capture_groups',
      ]);
      expect(portableRegexProblems('[0-9]{4}', requireCaptureGroup: true), [
        'no_capture_group',
      ]);
    });
  });

  group('portableRegexProblems accepts', () {
    for (final p in [
      r'(?:^|[^a-z])otp(?:$|[^a-z])',
      r'\*\*([0-9]{4})',
      r'ج\.?م ?[0-9]',
      r'^cib-(?:egy|alert)$',
      r'[\-a-z]',
      r'[^0-9.,*x]',
      r'a\/b',
      r'a\nb',
      r'[^a-z\n]',
      'رقم ([0-9]{4})',
      r'\(\)\[\]\{\}\|\^\$\?\+\*\.\\',
    ]) {
      test(p, () {
        expect(portableRegexProblems(p), isEmpty);
        // And it compiles in the Guard's mode.
        expect(() => compileGuardPattern(p), returnsNormally);
      });
    }
  });
}
