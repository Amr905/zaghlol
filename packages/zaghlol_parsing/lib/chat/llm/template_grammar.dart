/// Template grammar (FR-LLM-35, ask-llm.md 2.3 and the shared vectors'
/// `templateRules`). Pure: returns the first failing rule's reason code or
/// null. A failure drops only the template; the plan stays. T-331.
library;

import 'plan_schema.g.dart';

final RegExp _blank = RegExp(r'\{([A-Za-z]+)\}');
final RegExp _labelTld = RegExp(r'\p{L}\.\p{L}{2}', unicode: true);
final RegExp _nd = RegExp(r'\p{Nd}', unicode: true);
final RegExp _cc = RegExp(r'\p{Cc}', unicode: true);
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

bool _isArabicScript(int cp) =>
    (cp >= 0x0600 && cp <= 0x06FF) ||
    (cp >= 0x0750 && cp <= 0x077F) ||
    (cp >= 0x08A0 && cp <= 0x08FF) ||
    (cp >= 0xFB50 && cp <= 0xFDFF) ||
    (cp >= 0xFE70 && cp <= 0xFEFF);

bool _isEmoji(int cp) =>
    (cp >= 0x1F000 && cp <= 0x1FAFF) ||
    (cp >= 0x2600 && cp <= 0x27BF) ||
    cp == 0x2B50 ||
    cp == 0x2B55;

bool _isControl(int u) =>
    u == 0x061C ||
    (u >= 0x200B && u <= 0x200F) ||
    u == 0x2060 ||
    (u >= 0x202A && u <= 0x202E) ||
    (u >= 0x2066 && u <= 0x2069) ||
    u == 0xFEFF;

/// Dart has no NFC in the SDK and the package takes no dependency for it, so
/// this is a conservative test: text with a combining mark that composes with
/// a Latin or Arabic base (U+0300..U+036F, U+0653..U+0655) or a character
/// NFC replaces (U+212A, U+212B, U+2126) counts as not NFC. A template that
/// needs those is dropped, which is the safe side.
bool isLikelyNfc(String text) {
  for (final u in text.runes) {
    if ((u >= 0x0300 && u <= 0x036F) ||
        (u >= 0x0653 && u <= 0x0655) ||
        u == 0x212A ||
        u == 0x212B ||
        u == 0x2126) {
      return false;
    }
  }
  return true;
}

abstract final class TemplateGrammar {
  /// Rule order of the vectors: LENGTH, NOT_NFC, LANG, PLAN_NOT_ALLOWED,
  /// PLACEHOLDER, DIGIT, BAD_BLANK, DUPLICATE_BLANK, AT, LINK, MARKUP,
  /// CONTROL, EMOJI, SCRIPT.
  static String? check({
    required String plan,
    required String requestLang,
    required String templateLang,
    required String text,
  }) {
    if (text.isEmpty ||
        text.length > 200 ||
        text.contains(RegExp('[\n\r\u0085  ]'))) {
      return 'TEMPLATE_LENGTH';
    }
    if (!isLikelyNfc(text)) return 'TEMPLATE_NOT_NFC';
    if ((templateLang != 'ar' && templateLang != 'en') ||
        templateLang != requestLang) {
      return 'TEMPLATE_LANG';
    }
    final allowed = planTemplateBlanks[plan];
    if (allowed == null) return 'TEMPLATE_PLAN_NOT_ALLOWED';
    if (text.contains('⟦') || text.contains('⟧')) {
      return 'TEMPLATE_PLACEHOLDER';
    }
    if (_nd.hasMatch(text)) return 'TEMPLATE_DIGIT';
    final found = [for (final m in _blank.allMatches(text)) m.group(1)!];
    final remainder = text.replaceAll(_blank, '');
    if (remainder.contains('{') ||
        remainder.contains('}') ||
        found.any((f) => !allowed.contains(f))) {
      return 'TEMPLATE_BAD_BLANK';
    }
    if (found.length != found.toSet().length) return 'TEMPLATE_DUPLICATE_BLANK';
    if (text.contains(RegExp('[@＠﹫]'))) return 'TEMPLATE_AT';
    if (text.contains('://') ||
        text.toLowerCase().contains('www.') ||
        _labelTld.hasMatch(text)) {
      return 'TEMPLATE_LINK';
    }
    if (text.contains(RegExp(r'[<>\[\]()*_#`|~]'))) return 'TEMPLATE_MARKUP';
    if (_cc.hasMatch(text) || text.runes.any(_isControl)) {
      return 'TEMPLATE_CONTROL';
    }
    if (text.runes.where(_isEmoji).length > 1) return 'TEMPLATE_EMOJI';
    final letters = [
      for (final m in _letter.allMatches(remainder)) m.group(0)!.runes.first,
    ];
    final arabic = letters.where(_isArabicScript).length;
    if (requestLang == 'ar'
        ? letters.isEmpty || arabic * 100 < letters.length * 70
        : arabic > 0) {
      return 'TEMPLATE_SCRIPT';
    }
    return null;
  }
}
