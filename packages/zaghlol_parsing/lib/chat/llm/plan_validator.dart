/// Phone-side validator of an `ask-plan/1` reply (T-331, FR-LLM-06/07/21/35,
/// ask-llm.md 2.4). Same steps and reason codes as the backend, run on the
/// phone's pinned schema copy as defence in depth:
///
/// 1. JSON Schema (the embedded, pinned copy). 2. Every `ref` occurs verbatim
/// in the sent text (and, when a [MaskMap] is given, is one of that
/// question's own placeholders); no `mention` names an account, card or bank
/// of the user or the registry. 3. `mention` is a substring of the sent text
/// after `foldKey`. 4. Amounts come from the question or a number word, and
/// fit the currency exponent. 5. Cross-field rules. 6. Template grammar plus
/// the phone-only rule that a template names no account/card/bank.
///
/// Failures of steps 1 to 5 give a [PlanFallback] (the caller shows the app's
/// fallback and does not count the question); a step 6 failure drops only the
/// template. Never throws, never logs: reason codes are fixed strings.
library;

import 'dart:convert';

import '../../normalize/text_normalizer.dart';
import 'mask_models.dart';
import 'number_words.dart';
import 'plan.dart';
import 'plan_schema.g.dart';
import 'template_grammar.dart';

/// A model template that passed step 6.
final class PlanTemplate {
  const PlanTemplate(this.lang, this.text);
  final String lang;
  final String text;

  @override
  String toString() => 'PlanTemplate(<redacted>)';
}

final class PlanValidation {
  const PlanValidation._(
    this.plan, {
    this.failedStep,
    this.reason,
    this.template,
    this.templateReason,
  });

  /// The validated plan, or `PlanFallback(unsupported)` when [rejected].
  final Plan plan;

  /// 1..5 when the plan was rejected.
  final int? failedStep;
  final String? reason;

  /// The model's template when it passed step 6, else null.
  final PlanTemplate? template;

  /// Why the template was dropped (step 6), else null.
  final String? templateReason;

  bool get rejected => failedStep != null;

  @override
  String toString() => 'PlanValidation($failedStep, $reason, $templateReason)';
}

final class _Name {
  const _Name(this.folded, this.ordinary);
  final String folded;
  final bool ordinary;
}

final RegExp _numberRe = RegExp(r'[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?');

/// A `⟦…⟧` placeholder token. Step 4 cuts these out of the sent text before
/// it reads numbers, so a placeholder index is never an amount (FU-409).
final RegExp _placeholderRe = RegExp('⟦[^⟦⟧]*⟧');

/// Any number character (Nd, Nl, No: `½`, `①`, `Ⅻ`), for the mention rule.
final RegExp _anyNumber = RegExp(r'\p{N}', unicode: true);

class PlanValidator {
  /// [sources]: the user's accounts, the registry aliases and the user's
  /// merchants (the masker's sources); their names must not appear in plain
  /// text. [extraAliases]: more registry aliases.
  PlanValidator({
    MaskSources sources = const StaticMaskSources(),
    Iterable<String> extraAliases = const [],
  }) : _names = _collectNames(sources, extraAliases);

  final List<_Name> _names;
  static Map<String, Object?>? _schema;

  static Map<String, Object?> get _root => _schema ??= _decodeSchema();

  static List<_Name> _collectNames(MaskSources s, Iterable<String> extra) {
    final out = <_Name>[];
    void add(String? raw, {bool ordinary = false}) {
      if (raw == null) return;
      final f = foldKey(raw);
      if (f.isNotEmpty) out.add(_Name(f, ordinary));
    }

    for (final a in s.accounts) {
      add(a.label);
      add(a.nickname);
      a.extraNames.forEach(add);
    }
    for (final i in s.institutions) {
      for (final a in i.aliases) {
        add(a.text, ordinary: a.ordinaryWord);
      }
    }
    for (final m in s.merchants) {
      m.names.forEach(add);
    }
    extra.forEach(add);
    return out;
  }

  /// Validates the decoded reply [json] (a `Map` from `jsonDecode`) against
  /// the question text actually [sent] to the backend. [lang] is the request
  /// language (`ar`/`en`). [map] is the placeholder map of this question.
  /// [primaryCurrency] is used for the fraction rule when a currency is null.
  PlanValidation validate(
    Object? json, {
    required String sent,
    required String lang,
    MaskMap? map,
    String? primaryCurrency,
  }) {
    try {
      return _validate(json, sent, lang, map, primaryCurrency);
    } on Object {
      // A validator bug must fail closed, never throw into the chat.
      return _reject(1, 'SCHEMA_INVALID');
    }
  }

  PlanValidation _validate(
    Object? json,
    String sent,
    String lang,
    MaskMap? map,
    String? primaryCurrency,
  ) {
    // Step 1
    if (!_valid(json, _root, _root)) return _reject(1, 'SCHEMA_INVALID');
    final env = json! as Map<String, Object?>;
    final name = env['plan']! as String;
    final p = env['p']! as Map<String, Object?>;
    if (!_valid(p, {'\$ref': '#/\$defs/P_$name'}, _root)) {
      return _reject(5, 'PLAN_MISMATCH');
    }

    // Step 2
    final refs = <String>[];
    final mentions = <String>[];
    final amounts = <(String, String?)>[];
    final objects = <Map<String, Object?>>[];
    _walk(p, objects);
    for (final o in objects) {
      final r = o['ref'];
      if (r is String) refs.add(r);
      final m = o['mention'];
      if (m is String) mentions.add(m);
      final a = o['amount'];
      if (a is String) amounts.add((a, o['currency'] as String?));
    }
    for (final r in refs) {
      if (!sent.contains(r)) return _reject(2, 'REF_NOT_IN_TEXT');
      if (map != null && map[r] == null) return _reject(2, 'REF_NOT_IN_MAP');
    }
    // Plain-name check: every string of `p` (mention, currency, ...).
    final strings = <String>[];
    _strings(p, strings);
    for (final m in strings) {
      final f = foldKey(m);
      if (_names.any((n) => containsWholeWord(f, n.folded))) {
        return _reject(2, 'PLAIN_NAME');
      }
    }

    // Step 3
    final foldedSent = foldKey(sent);
    for (final m in mentions) {
      final f = foldKey(m);
      if (_anyNumber.hasMatch(m) || f.isEmpty || !foldedSent.contains(f)) {
        return _reject(3, 'MENTION_NOT_IN_TEXT');
      }
    }

    // Step 4
    if (amounts.isNotEmpty) {
      // A space is left for each token, so its neighbours never join.
      final numbersText = foldedSent.replaceAll(_placeholderRe, ' ');
      final known = {
        for (final m in _numberRe.allMatches(numbersText))
          canonicalDecimal(m.group(0)!),
        ...numberWordValues(numbersText),
      };
      for (final (amount, currency) in amounts) {
        if (!known.contains(canonicalDecimal(amount))) {
          return _reject(4, 'AMOUNT_NOT_IN_TEXT');
        }
        final cur = currency ?? primaryCurrency;
        if (cur != null) {
          final dot = amount.indexOf('.');
          final fraction = dot < 0 ? 0 : amount.length - dot - 1;
          if (fraction > planCurrencyExponent(cur)) {
            return _reject(4, 'AMOUNT_FRACTION_TOO_LONG');
          }
        }
      }
    }

    // Step 5
    final cross = _crossField(name, p, objects);
    if (cross != null) return _reject(5, cross);

    final typed = _parsePlan(name, p);

    // Step 6
    PlanTemplate? template;
    String? templateReason;
    final t = env['t'];
    if (t is Map<String, Object?>) {
      final text = t['text']! as String;
      final tl = t['lang']! as String;
      templateReason = TemplateGrammar.check(
        plan: name,
        requestLang: lang,
        templateLang: tl,
        text: text,
      );
      if (templateReason == null && _namesAName(text)) {
        templateReason = 'TEMPLATE_PLAIN_NAME';
      }
      if (templateReason == null) template = PlanTemplate(tl, text);
    }
    return PlanValidation._(
      typed,
      template: template,
      templateReason: templateReason,
    );
  }

  /// Phone-only: a template must not name an account, card, bank or merchant
  /// of the user. Everyday-word aliases are ignored here (they need a bank or
  /// account word next to them to count as names, FR-LLM-18).
  bool _namesAName(String text) {
    final f = foldKey(text);
    return _names.any((n) => !n.ordinary && containsWholeWord(f, n.folded));
  }

  static PlanValidation _reject(int step, String reason) => PlanValidation._(
    const PlanFallback(FallbackReason.unsupported),
    failedStep: step,
    reason: reason,
  );

  static void _strings(Object? node, List<String> into) {
    if (node is String) {
      into.add(node);
    } else if (node is Map<String, Object?>) {
      for (final v in node.values) {
        _strings(v, into);
      }
    } else if (node is List) {
      for (final v in node) {
        _strings(v, into);
      }
    }
  }

  static void _walk(Object? node, List<Map<String, Object?>> into) {
    if (node is Map<String, Object?>) {
      into.add(node);
      for (final v in node.values) {
        _walk(v, into);
      }
    }
  }

  static bool _hasKeys(Map<String, Object?> n, List<String> keys) =>
      n.length == keys.length && keys.every(n.containsKey);

  static String? _crossField(
    String plan,
    Map<String, Object?> p,
    List<Map<String, Object?>> objects,
  ) {
    for (final n in objects) {
      if (_hasKeys(n, const ['k', 'o', 'n', 'm', 'y'])) {
        final kind = n['k'];
        if ((n['n'] != null) != (kind == 'lastDays') ||
            (n['m'] != null) != (kind == 'monthOfYear') ||
            (n['y'] != null && kind != 'monthOfYear')) {
          return 'PERIOD_FIELD_MISMATCH';
        }
      } else if (_hasKeys(n, const ['slug', 'ref', 'mention', 'currency'])) {
        final set = ['slug', 'ref', 'mention'].where((k) => n[k] != null);
        if (set.length > 1) return 'FILTER_MULTIPLE_KEYS';
      } else if (_hasKeys(n, const ['kind', 'percent', 'amount', 'currency'])) {
        final percent = n['kind'] == 'percent';
        if ((n['percent'] != null) != percent ||
            (n['amount'] != null) == percent ||
            (percent && n['currency'] != null)) {
          return 'MODE_FIELD_MISMATCH';
        }
      } else if (_hasKeys(n, const ['kind', 'whatIf', 'amount'])) {
        final kind = n['kind'];
        if ((n['whatIf'] != null) != (kind == 'whatIf') ||
            (n['amount'] != null) != (kind == 'amount')) {
          return 'SOURCE_FIELD_MISMATCH';
        }
      }
      // A what-if target (also inside PL-INVEST) carries no currency.
      final target = n['target'];
      if (target is Map<String, Object?> && target['currency'] != null) {
        return 'TARGET_CURRENCY_SET';
      }
    }
    final instruments = p['instruments'];
    if (instruments is List &&
        instruments.toSet().length != instruments.length) {
      return 'INSTRUMENTS_DUPLICATE';
    }
    if (plan == 'PL-INCOME' &&
        (p['filter']! as Map<String, Object?>)['slug'] != null) {
      return 'INCOME_SLUG_SET';
    }
    return null;
  }

  // ------------------------------------------------------- typed parsing

  static PlanPeriod _period(Object? o) {
    final m = o! as Map<String, Object?>;
    return PlanPeriod(
      kind: PeriodKind.values.byName(m['k']! as String),
      // ignore: no_double_money (a JSON number in the plan, not money)
      offset: (m['o']! as num).toInt(),
      // ignore: no_double_money (a JSON number in the plan, not money)
      lastDays: (m['n'] as num?)?.toInt(),
      // ignore: no_double_money (a JSON number in the plan, not money)
      month: (m['m'] as num?)?.toInt(),
      // ignore: no_double_money (a JSON number in the plan, not money)
      year: (m['y'] as num?)?.toInt(),
    );
  }

  static PlanFilter _filter(Object? o) {
    final m = o! as Map<String, Object?>;
    return PlanFilter(
      slug: m['slug'] as String?,
      ref: m['ref'] as String?,
      mention: m['mention'] as String?,
      currency: m['currency'] as String?,
    );
  }

  static PlanAmount _amount(Object? o) {
    final m = o! as Map<String, Object?>;
    return PlanAmount(m['amount']! as String, m['currency'] as String?);
  }

  static PlanWhatIfCut _whatIf(Object? o) {
    final m = o! as Map<String, Object?>;
    final mode = m['mode']! as Map<String, Object?>;
    return PlanWhatIfCut(
      _filter(m['target']),
      PlanMode(
        kind: WhatIfKind.values.byName(mode['kind']! as String),
        // ignore: no_double_money (a JSON number in the plan, not money)
        percent: (mode['percent'] as num?)?.toInt(),
        amount: mode['amount'] as String?,
        currency: mode['currency'] as String?,
      ),
      // ignore: no_double_money (a JSON number in the plan, not money)
      (m['months']! as num).toInt(),
    );
  }

  static Plan _parsePlan(String name, Map<String, Object?> p) {
    // ignore: no_double_money (a JSON number in the plan, not money)
    int i(String k) => (p[k]! as num).toInt();
    switch (name) {
      case 'PL-SPEND':
        return PlanSpend(_period(p['period']), _filter(p['filter']));
      case 'PL-COMPARE':
        return PlanCompare(
          _period(p['periodA']),
          _period(p['periodB']),
          _filter(p['filter']),
        );
      case 'PL-BREAKDOWN':
        return PlanBreakdown(
          _period(p['period']),
          BreakdownBy.values.byName(p['by']! as String),
          i('limit'),
        );
      case 'PL-TOPN':
        return PlanTopN(
          _period(p['period']),
          TopOf.values.byName(p['of']! as String),
          i('n'),
        );
      case 'PL-AVERAGE':
        return PlanAverage(
          AveragePer.values.byName(p['per']! as String),
          _period(p['period']),
          _filter(p['filter']),
        );
      case 'PL-INCOME':
        return PlanIncome(_period(p['period']), _filter(p['filter']));
      case 'PL-SAVED':
        return PlanSaved(_period(p['period']));
      case 'PL-BILLS-DUE':
        return PlanBillsDue(i('windowDays'));
      case 'PL-BUDGET-LEFT':
        return PlanBudgetLeft(p['slug'] as String?);
      case 'PL-SAFE-SPEND':
        return const PlanSafeSpend();
      case 'PL-BALANCE':
        return PlanBalance(p['ref'] as String?);
      case 'PL-WHATIF-CUT':
        return _whatIf(p);
      case 'PL-WHATIF-SAVE':
        return PlanWhatIfSave(_amount(p['amount']), i('months'));
      case 'PL-SUGGEST':
        return PlanSuggest(p['currency'] as String?);
      case 'PL-INVEST':
        final s = p['source']! as Map<String, Object?>;
        return PlanInvest(
          PlanInvestSource(
            InvestSourceKind.values.byName(s['kind']! as String),
            whatIf: s['whatIf'] == null ? null : _whatIf(s['whatIf']),
            amount: s['amount'] == null ? null : _amount(s['amount']),
          ),
          [
            for (final x in p['instruments']! as List)
              Instrument.fromWire(x! as String),
          ],
          i('horizonMonths'),
        );
      case 'PL-FALLBACK':
        return PlanFallback(
          FallbackReason.values.byName(p['reason']! as String),
        );
      case 'PL-REFUSE':
        return PlanRefuse(
          RefuseReason.values.byName(p['reason']! as String),
          selfHarm: p['selfHarm']! as bool,
        );
    }
    throw StateError('unreachable: schema enum covers every plan');
  }
}

// ---------------------------------------------- JSON Schema subset (step 1)

Map<String, Object?> _decodeSchema() => _jsonDecode(planSchemaJson);

Map<String, Object?> _jsonDecode(String s) =>
    jsonDecode(s) as Map<String, Object?>;

/// The keyword subset the contract uses (ask-plan-v1.schema.json $comment):
/// type (incl. lists), properties, required, additionalProperties:false,
/// enum, anyOf, $ref to `#/$defs/X`, pattern, minimum, maximum, minItems,
/// maxItems, items.
bool _valid(Object? v, Map<String, Object?> s, Map<String, Object?> root) {
  final ref = s['\$ref'];
  if (ref is String) {
    const prefix = '#/\$defs/';
    if (!ref.startsWith(prefix)) return false;
    final target =
        (root['\$defs']! as Map<String, Object?>)[ref.substring(prefix.length)];
    if (target is! Map<String, Object?>) return false;
    return _valid(v, target, root);
  }
  final anyOf = s['anyOf'];
  if (anyOf is List) {
    return anyOf.any((x) => _valid(v, x! as Map<String, Object?>, root));
  }
  final type = s['type'];
  if (type != null) {
    final types = type is List ? type.cast<String>() : [type as String];
    if (!types.any((t) => _isType(v, t))) return false;
  }
  final en = s['enum'];
  if (en is List && !en.contains(v)) return false;
  if (v is String) {
    final pattern = s['pattern'];
    if (pattern is String && !RegExp(pattern, unicode: true).hasMatch(v)) {
      return false;
    }
  }
  // ignore: no_double_money (a JSON number in the plan, not money)
  if (v is num) {
    final min = s['minimum'];
    final max = s['maximum'];
    // ignore: no_double_money (a JSON number in the plan, not money)
    if (min is num && v < min) return false;
    // ignore: no_double_money (a JSON number in the plan, not money)
    if (max is num && v > max) return false;
  }
  if (v is List) {
    final min = s['minItems'];
    final max = s['maxItems'];
    if (min is int && v.length < min) return false;
    if (max is int && v.length > max) return false;
    final items = s['items'];
    if (items is Map<String, Object?> &&
        !v.every((x) => _valid(x, items, root))) {
      return false;
    }
  }
  if (v is Map<String, Object?>) {
    final props = (s['properties'] as Map<String, Object?>?) ?? const {};
    final req = (s['required'] as List?) ?? const [];
    for (final k in req) {
      if (!v.containsKey(k)) return false;
    }
    if (s['additionalProperties'] == false &&
        v.keys.any((k) => !props.containsKey(k))) {
      return false;
    }
    for (final e in v.entries) {
      final sub = props[e.key];
      if (sub is Map<String, Object?> && !_valid(e.value, sub, root)) {
        return false;
      }
    }
  }
  return true;
}

bool _isType(Object? v, String t) => switch (t) {
  'null' => v == null,
  'string' => v is String,
  'boolean' => v is bool,
  'object' => v is Map,
  'array' => v is List,
  'integer' =>
    // ignore: no_double_money (a JSON number in the plan, not money)
    v is int || (v is double && v.isFinite && v == v.truncateToDouble()),
  // ignore: no_double_money (a JSON number in the plan, not money)
  'number' => v is num,
  _ => false,
};
