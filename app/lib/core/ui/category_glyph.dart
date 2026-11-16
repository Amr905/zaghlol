import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';
import 'z_card.dart';

/// Emoji tile for a transaction's category (mockups 03 / 20). Keys are matched
/// loosely against the category id so seeded and custom ids both resolve;
/// unknown ids get the receipt glyph.
class ZCategoryGlyph extends StatelessWidget {
  const ZCategoryGlyph({
    super.key,
    this.categoryId,
    this.income = false,
    this.transfer = false,
    this.size = 40,
  });

  final String? categoryId;
  final bool income;
  final bool transfer;
  final double size;

  /// One emoji per catalog (system) category code (`sys:<code>`, the 14
  /// codes in tools/catalog_build/data/catalog_curated.csv). Exact match
  /// first; the keyword table below only serves custom ids.
  static const Map<String, String> systemEmoji = {
    'groceries': '\u{1F6D2}',
    'dining': '\u{1F354}',
    'transport': '\u{1F697}',
    'bills': '⚡',
    'housing': '\u{1F3E0}',
    'shopping': '\u{1F6CD}️',
    'debt': '\u{1F4B3}',
    'subscriptions': '\u{1F4FA}',
    'health': '\u{1F48A}',
    'education': '\u{1F393}',
    'entertainment': '\u{1F3AC}',
    'family_giving': '\u{1F381}',
    'savings': '\u{1F437}',
    'income': '\u{1F4BC}',
  };

  static const _emoji = <(List<String>, String)>[
    (['grocer', 'supermarket', 'market'], '\u{1F6D2}'),
    (['dining', 'food', 'restaurant', 'delivery', 'cafe'], '\u{1F354}'),
    (['transport', 'fuel', 'car', 'taxi', 'ride'], '\u{1F697}'),
    (['util', 'bill', 'electric', 'telecom', 'internet'], '⚡'),
    (['health', 'pharm', 'medical'], '\u{1F48A}'),
    (['entertain', 'fun', 'movie'], '\u{1F3AC}'),
    (['shop', 'cloth', 'fashion'], '\u{1F6CD}️'),
    (['educ', 'school'], '\u{1F393}'),
    (['travel', 'flight'], '✈️'),
    (['subscri', 'stream'], '\u{1F4FA}'),
    (['home', 'rent', 'house'], '\u{1F3E0}'),
    (['gift'], '\u{1F381}'),
  ];

  /// True for a catalog (system) category id, bare or `sys:`-prefixed.
  static bool isSystemId(String id) {
    final key = id.toLowerCase();
    return systemEmoji.containsKey(
      key.startsWith('sys:') ? key.substring(4) : key,
    );
  }

  static String glyphFor(String? id, {bool income = false}) {
    if (income) return '\u{1F4BC}';
    final key = (id ?? '').toLowerCase();
    final exact = systemEmoji[key.startsWith('sys:') ? key.substring(4) : key];
    if (exact != null) return exact;
    for (final (words, e) in _emoji) {
      if (words.any(key.contains)) return e;
    }
    return '\u{1F9FE}';
  }

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    if (transfer) {
      return ZCategoryTile(
        size: size,
        color: c.textMuted,
        child: Icon(Icons.swap_horiz_rounded, size: 22, color: c.textMuted),
      );
    }
    final glyph = glyphFor(categoryId, income: income);
    final tint = income
        ? c.primary
        : switch (glyph) {
            '\u{1F6D2}' => c.textMuted,
            '\u{1F354}' => c.dangerText,
            _ => c.primary,
          };
    return ZCategoryTile(
      size: size,
      color: tint,
      child: Text(glyph, style: TextStyle(fontSize: size * 0.48, height: 1)),
    );
  }
}
