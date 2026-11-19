import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../brand/institution_brand.dart';
import '../theme/z_tokens.dart';

/// WCAG relative-luminance contrast ratio between two colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Picks white or near-black, whichever contrasts more with [bg].
Color readableOn(Color bg) {
  const dark = Color(0xFF0F2A20);
  const light = Color(0xFFFFFFFF);
  return contrastRatio(bg, light) >= contrastRatio(bg, dark) ? light : dark;
}

/// Minimum contrast of badge text on its fill (WCAG AA, normal text).
const double kBadgeMinContrast = 4.5;

/// Fill and text colours for a badge on [brand] (ARGB). The brand colour is
/// used as is when white or ink reaches [kBadgeMinContrast] on it; otherwise
/// it is darkened in small steps until one does. In dark mode the fill is
/// first deepened so the badge does not glare on Jade Night.
({Color bg, Color fg}) badgeColors(int brand, Brightness brightness) {
  var bg = Color(brand);
  if (brightness == Brightness.dark) {
    bg = Color.lerp(bg, const Color(0xFF000000), 0.3)!;
  }
  for (var i = 0; i < 40; i++) {
    final fg = readableOn(bg);
    if (contrastRatio(bg, fg) >= kBadgeMinContrast) return (bg: bg, fg: fg);
    bg = Color.lerp(bg, const Color(0xFF000000), 0.06)!;
  }
  return (bg: const Color(0xFF000000), fg: const Color(0xFFFFFFFF));
}

const _genericWords = {
  'بنك',
  'البنك',
  'مصرف',
  'المصرف',
  'bank',
  'banque',
  'the',
  'of',
  'for',
};

/// Neutral initials for a custom or unknown institution: the user's label
/// without generic words (بنك, البنك, مصرف, Bank...). One word of up to four
/// letters stays whole; a longer one gives its first two letters; several
/// words give the first letter of up to three. Never empty.
String badgeInitials(String label) {
  final words = label
      .trim()
      .split(RegExp(r'[\s\-_.]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  var useful = [
    for (final w in words)
      if (!_genericWords.contains(w.toLowerCase())) w,
  ];
  if (useful.isEmpty) useful = words;
  if (useful.isEmpty) return '?';
  String bare(String w) =>
      w.startsWith('ال') && w.runes.length > 3 ? w.substring(2) : w;
  useful = [for (final w in useful) bare(w)];
  String first(String w, int n) => String.fromCharCodes(w.runes.take(n));
  final String t;
  if (useful.length == 1) {
    final w = useful.first;
    t = w.runes.length <= 4 ? w : first(w, 2);
  } else {
    t = useful.take(3).map((w) => first(w, 1)).join();
  }
  return t.toUpperCase();
}

/// The one account / bank / card / sender avatar (T-198). Logo when bundled
/// (OQ-09: none yet), else the institution's short code on its brand colour,
/// else neutral initials from [label]. Brand data comes from
/// [institutionBrandsProvider], or [brand] when given (tests, previews).
class ZInstitutionAvatar extends ConsumerWidget {
  const ZInstitutionAvatar({
    required this.label,
    this.institutionCode,
    this.brand,
    this.size = 44,
    super.key,
  });

  /// Display name of the institution or the user's own label; only used for
  /// the neutral initials.
  final String label;
  final String? institutionCode;
  final InstitutionBrand? brand;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ZColors.of(context);
    var b = brand;
    if (b == null && institutionCode != null) {
      b = ref.watch(institutionBrandsProvider).value?[institutionCode];
    }
    final color = b?.colorValue;
    final Color bg;
    final Color fg;
    if (color == null) {
      bg = c.primaryContainer;
      fg = c.onPrimaryContainer;
    } else {
      final p = badgeColors(color, Theme.of(context).brightness);
      bg = p.bg;
      fg = p.fg;
    }
    final text = b?.badgeText ?? badgeInitials(label);
    Widget fallback() => Container(
      width: size,
      height: size,
      alignment: AlignmentDirectional.center,
      padding: EdgeInsetsDirectional.all(size * 0.1),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          textDirection: TextDirection.ltr,
          style: ZType.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
        ),
      ),
    );
    final logo = b?.logoAsset;
    return ExcludeSemantics(
      child: logo == null
          ? fallback()
          : ClipOval(
              child: Image.asset(
                logo,
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => fallback(),
              ),
            ),
    );
  }
}
