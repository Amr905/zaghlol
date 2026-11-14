import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/category_glyph.dart';

void main() {
  test('every catalog category has its own emoji (exact, not keyword)', () {
    const codes = [
      'groceries',
      'dining',
      'transport',
      'bills',
      'housing',
      'shopping',
      'debt',
      'subscriptions',
      'health',
      'education',
      'entertainment',
      'family_giving',
      'savings',
      'income',
    ];
    for (final c in codes) {
      expect(ZCategoryGlyph.systemEmoji.containsKey(c), isTrue, reason: c);
      expect(
        ZCategoryGlyph.glyphFor('sys:$c'),
        ZCategoryGlyph.systemEmoji[c],
        reason: c,
      );
    }
    // The old keyword guess gave the receipt glyph to these.
    expect(ZCategoryGlyph.glyphFor('sys:debt'), isNot('\u{1F9FE}'));
    expect(ZCategoryGlyph.glyphFor('sys:savings'), isNot('\u{1F9FE}'));
  });

  test('custom ids still fall back to keywords, then the receipt', () {
    expect(ZCategoryGlyph.glyphFor('my-cafe'), '\u{1F354}');
    expect(ZCategoryGlyph.glyphFor('zzz'), '\u{1F9FE}');
  });
}
