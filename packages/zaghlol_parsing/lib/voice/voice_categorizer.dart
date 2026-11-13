/// Categorization of voice items (T-109, domain-algorithms §9 step 5). Uses
/// the shared [Categorizer] (user rule, catalog merchant, keywords, needs
/// classification) so a spoken "Uber" and a bank-SMS "UBER" agree.
library;

import '../categorize/categorizer.dart';
import '../categorize/types.dart';
import '../merchant/merchant_cleaner.dart';
import '../normalize/text_normalizer.dart';
import 'voice_types.dart';

/// A [VoiceItem] with its category decision.
final class CategorizedVoiceItem {
  const CategorizedVoiceItem({
    required this.item,
    required this.decision,
    required this.confidencePermille,
  });

  final VoiceItem item;

  /// `decision.needsClassification` means "needs classification": the user
  /// picks a category (FR-VOI-03).
  final CategoryDecision decision;

  /// [VoiceItem.confidencePermille] scaled by how the category was found
  /// (rule or exact 1000, prefix/token 950, keyword 900, fuzzy 850, none 600).
  final int confidencePermille;

  @override
  String toString() => 'CategorizedVoiceItem(<redacted>)';
}

/// Categorizes [items] in order with one memoizing [Categorizer]. A port
/// failure propagates (never read as "no match").
Future<List<CategorizedVoiceItem>> categorizeVoiceItems(
  List<VoiceItem> items,
  CategorizerPorts ports, {
  CategorizerConfig config = const CategorizerConfig(),
}) async {
  final categorizer = Categorizer(ports, config: config, memoize: true);
  final out = <CategorizedVoiceItem>[];
  for (final item in items) {
    final text = item.matchText;
    final decision = text.trim().isEmpty
        ? const CategoryDecision(
            source: CategorySource.none,
            tier: CategorizeTier.none,
          )
        : await categorizer.categorize(
            CategorizeInput(
              merchantNorm: cleanMerchant(text).key,
              merchantText: foldKey(text),
            ),
          );
    out.add(
      CategorizedVoiceItem(
        item: item,
        decision: decision,
        confidencePermille: item.confidencePermille * _factor(decision) ~/ 1000,
      ),
    );
  }
  return out;
}

int _factor(CategoryDecision d) {
  if (d.needsClassification) return 600;
  return switch (d.tier) {
    CategorizeTier.rule || CategorizeTier.exact => 1000,
    CategorizeTier.prefix || CategorizeTier.token => 950,
    CategorizeTier.keyword => 900,
    CategorizeTier.fuzzy => 850,
    _ => 600,
  };
}
