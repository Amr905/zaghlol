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

/// Account / bank / card / sender avatar: official logo when bundled, else
/// initials on the brand colour, else the neutral style ([neutralBg] and
/// [neutralFg]). Brand data comes from [institutionBrandsProvider], or
/// [brand] when given (tests, previews).
class ZInstitutionAvatar extends ConsumerWidget {
  const ZInstitutionAvatar({
    required this.initials,
    required this.neutralBg,
    required this.neutralFg,
    this.institutionCode,
    this.brand,
    this.size = 44,
    super.key,
  });

  final String? institutionCode;
  final String initials;
  final Color neutralBg;
  final Color neutralFg;
  final InstitutionBrand? brand;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var b = brand;
    if (b == null && institutionCode != null) {
      b = ref.watch(institutionBrandsProvider).value?[institutionCode];
    }
    final color = b?.colorValue;
    final bg = color == null ? neutralBg : Color(color);
    final fg = color == null ? neutralFg : readableOn(bg);
    final text = Text(
      initials,
      maxLines: 1,
      style: ZType.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
    );
    Widget fallback() => Container(
      width: size,
      height: size,
      alignment: AlignmentDirectional.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: text,
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
