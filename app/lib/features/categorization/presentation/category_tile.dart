// Category glyph in a soft tinted circle (mockups 08/09): the stored icon key
// and `#RRGGBB` colour, falling back to the theme's mint tile.

import 'package:flutter/material.dart';

import '../../../core/theme/z_tokens.dart';
import 'category_visuals.dart';

class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.iconKey,
    this.colorHex,
    this.size = 44,
  });

  /// Null (unknown category) falls back to the generic glyph.
  final String? iconKey;
  final String? colorHex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final tint = colorHex == null ? null : parseHexColor(colorHex!);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint == null ? c.surfaceAlt : tint.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(
          iconFor(iconKey ?? ''),
          size: size * 0.5,
          color: tint ?? c.primary,
        ),
      ),
    );
  }
}
