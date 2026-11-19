import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Brand data for one registry institution (BRAND-logos). Both fields are
/// optional: no colour means the neutral style, no logo means initials.
class InstitutionBrand {
  const InstitutionBrand({
    this.colorValue,
    this.logoAsset,
    this.acronym,
    this.shortCode,
  });

  /// Opaque ARGB value of the brand colour, or null.
  final int? colorValue;

  /// Path under `assets/brand/logos/`, or null.
  final String? logoAsset;

  /// Latin short name (NBE, CIB...) shown when the full name does not fit.
  final String? acronym;

  /// Badge text of at most five characters when [acronym] is longer.
  final String? shortCode;

  /// What the avatar prints: [shortCode], else [acronym].
  String? get badgeText => shortCode ?? acronym;
}

/// Parses `institutions_brand.json`; unknown or malformed rows are skipped.
Map<String, InstitutionBrand> parseInstitutionBrands(String json) {
  final root = jsonDecode(json);
  final rows = root is Map ? root['institutions'] : null;
  final out = <String, InstitutionBrand>{};
  if (rows is! Map) return out;
  rows.forEach((k, v) {
    if (k is! String || v is! Map) return;
    final hex = v['brandColor'];
    int? color;
    if (hex is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      color = 0xFF000000 | int.parse(hex.substring(1), radix: 16);
    }
    final logo = v['logoAsset'];
    out[k] = InstitutionBrand(
      colorValue: color,
      logoAsset: logo is String && logo.isNotEmpty ? logo : null,
      acronym: v['acronym'] is String && (v['acronym'] as String).isNotEmpty
          ? v['acronym'] as String
          : null,
      shortCode:
          v['shortCode'] is String && (v['shortCode'] as String).isNotEmpty
          ? v['shortCode'] as String
          : null,
    );
  });
  return out;
}

final institutionBrandsProvider = FutureProvider<Map<String, InstitutionBrand>>(
  (ref) async => parseInstitutionBrands(
    await rootBundle.loadString('assets/brand/institutions_brand.json'),
  ),
);
