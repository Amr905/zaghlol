// T-163: icons and colours a custom category may use (S-64). Stored as a
// short icon key and a `#RRGGBB` string, the same shape the catalog seeds.

import 'package:flutter/material.dart';

/// Icon keys offered in the editor, in display order.
const Map<String, IconData> categoryIcons = {
  'cart': Icons.shopping_cart_outlined,
  'home': Icons.home_outlined,
  'car': Icons.directions_car_outlined,
  'food': Icons.restaurant_outlined,
  'health': Icons.favorite_border,
  'school': Icons.school_outlined,
  'travel': Icons.flight_outlined,
  'gift': Icons.card_giftcard_outlined,
  'work': Icons.work_outline,
  'fun': Icons.celebration_outlined,
  'bolt': Icons.bolt_outlined,
  'pets': Icons.pets_outlined,
};

/// Fallback for system icon keys that are not in [categoryIcons].
IconData iconFor(String key) => categoryIcons[key] ?? Icons.category_outlined;

/// The approved colour set (deep tones that keep contrast on both themes).
const List<String> categoryPalette = [
  '#174C4F',
  '#0F7A55',
  '#7A4A0F',
  '#5B3A8C',
  '#8C3A5B',
  '#2F5D8C',
  '#6B6B2A',
  '#4D695C',
];

/// Parses `#RRGGBB`; null when malformed.
Color? parseHexColor(String hex) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex);
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}
