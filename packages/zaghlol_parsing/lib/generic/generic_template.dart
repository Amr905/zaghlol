import '../custom/custom_template.dart';
import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../pipeline/parsing_pipeline.dart' show detectLanguage;
import '../registry/registry_models.dart';
import 'generic_parser.dart';

/// Tags the custom-template builder (T-164, S-65) can start from, read from
/// a message by the generic extractor: what a confirmed generic suggestion
/// "learns". Offsets only, never text.
final class GenericTemplateSuggestion {
  const GenericTemplateSuggestion(this.tags, this.direction);

  /// One span per tag kind, in original-text offsets.
  final List<TagSpan> tags;

  /// The direction the message reads as; null when no keyword says it.
  final TemplateDirection? direction;
}

const Map<GenericField, CustomTag> _tagOf = {
  GenericField.amount: CustomTag.amount,
  GenericField.currency: CustomTag.currency,
  GenericField.merchant: CustomTag.merchant,
  GenericField.last4: CustomTag.last4,
  GenericField.date: CustomTag.date,
};

/// Builder tags for [generic] (original-text offsets). Never throws.
List<TagSpan> genericTemplateTags(ParseGeneric generic) {
  final out = <TagSpan>[];
  for (final e in _tagOf.entries) {
    final s = generic.spans[e.key];
    if (s != null && s.end > s.start) {
      out.add(TagSpan(e.value, s.start, s.end));
    }
  }
  return out;
}

/// Reads [sample] with the generic extractor and returns the builder tags,
/// or null when it reads no amount (the user then tags by hand). Pure; the
/// sample is not kept.
GenericTemplateSuggestion? suggestTemplateTags(
  String sample, {
  DateTime? receivedAt,
}) {
  try {
    final folded = foldKeyIndexed(sample);
    if (folded.text.isEmpty) {
      return null;
    }
    final r = parseGeneric(
      body: sample,
      folded: folded,
      receivedAt: receivedAt ?? DateTime.utc(2026),
      language: detectLanguage(folded.text).name,
    );
    if (r is! ParseGeneric) {
      return null;
    }
    return GenericTemplateSuggestion(genericTemplateTags(r), r.direction);
  } on Object {
    return null;
  }
}

/// A custom template for [sender] built from a confirmed generic reading of
/// [sample]: every tag the extractor found, dropping the optional date and
/// merchant tags if the template cannot be built with them. [direction] is
/// the confirmed one. Returns the last build (with its error) when none
/// works. Never throws.
CustomTemplateBuild templateFromGeneric({
  required String sample,
  required ParseGeneric generic,
  required TemplateDirection direction,
  required String sender,
  String channel = 'sms',
}) {
  final all = genericTemplateTags(generic);
  final attempts = [
    all,
    [
      for (final t in all)
        if (t.tag != CustomTag.date) t,
    ],
    [
      for (final t in all)
        if (t.tag != CustomTag.date && t.tag != CustomTag.merchant) t,
    ],
  ];
  CustomTemplateBuild? last;
  for (final tags in attempts) {
    last = buildCustomTemplate(
      sample: sample,
      spans: tags,
      direction: direction,
      sender: sender,
      channel: channel,
      defaultCurrency: generic.amount.currency,
    );
    if (last.spec != null) {
      return last;
    }
  }
  return last!;
}
