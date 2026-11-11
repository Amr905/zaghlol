import 'dart:convert';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/text_normalizer.dart';
import 'regex_safety.dart';
import 'registry_issue.dart';
import 'registry_models.dart';

/// Size caps for untrusted registry files (an OTA registry in the future is
/// untrusted input too).
const int maxRegistryFileBytes = 512 * 1024;
const int maxInstitutions = 500;
const int maxTemplatesPerInstitution = 200;
const int maxListItems = 200;
const int maxStringLength = 200;

/// Registry schema version this code reads.
const int registrySchemaVersion = 1;

final RegExp _groupName = RegExp(r'\(\?<([A-Za-z][A-Za-z0-9]*)>');
final RegExp _codeShape = RegExp(r'^[a-z][a-z0-9_]{1,31}$');
final RegExp _idShape = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$');
final RegExp _dateFormatShape = RegExp(
  r'^(?:d{1,2}|M{1,2}|y{2}|y{4})(?:[/.-](?:d{1,2}|M{1,2}|y{2}|y{4})){1,2}$',
);
final RegExp _permille = RegExp(r'^(?:0(?:\.(\d{1,3}))?|1(?:\.0{1,3})?)$');

/// Decodes [text] to a JSON object, or reports and returns null.
Map<String, Object?>? decodeObject(
  String path,
  String text,
  List<RegistryIssue> issues,
) {
  if (text.length > maxRegistryFileBytes) {
    issues.add(RegistryIssue(path, RegistryIssueCode.tooLarge));
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    issues.add(RegistryIssue(path, RegistryIssueCode.invalidJson));
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    issues.add(RegistryIssue(path, RegistryIssueCode.notAnObject));
    return null;
  }
  return decoded;
}

/// Strict reader over one JSON object: every key must be read, unknown keys
/// are reported by [finish].
final class ObjReader {
  ObjReader(this.path, this._map, this.issues);

  final String path;
  final Map<String, Object?> _map;
  final List<RegistryIssue> issues;
  final Set<String> _read = {};

  void _bad(RegistryIssueCode code, String key) =>
      issues.add(RegistryIssue('$path.$key', code));

  bool has(String key) => _map.containsKey(key);

  /// The underlying map, for readers that interpret free-form keys (the
  /// fixture `expect` block). Marks every key as read.
  Map<String, Object?> get rawMap {
    _read.addAll(_map.keys);
    return _map;
  }

  String? string(String key, {bool required = false}) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      if (required) {
        _bad(RegistryIssueCode.missingKey, key);
      }
      return null;
    }
    if (v is! String || v.isEmpty || v.length > maxStringLength) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    return v;
  }

  int? integer(String key, {required int min, required int max}) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      _bad(RegistryIssueCode.missingKey, key);
      return null;
    }
    if (v is! int) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    if (v < min || v > max) {
      _bad(RegistryIssueCode.badValue, key);
      return null;
    }
    return v;
  }

  /// Confidence `0`..`1` with at most 3 decimals, as thousandths. Reads the
  /// JSON scalar through its text so no floating-point type is involved.
  int? permille(String key) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      _bad(RegistryIssueCode.missingKey, key);
      return null;
    }
    if (v is String || v is bool || v is List || v is Map) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    final m = _permille.firstMatch('$v');
    if (m == null) {
      _bad(RegistryIssueCode.badValue, key);
      return null;
    }
    final text = '$v';
    if (text.startsWith('1')) {
      return 1000;
    }
    final frac = (m.group(1) ?? '').padRight(3, '0');
    return int.parse(frac);
  }

  bool? boolean(String key) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      return null;
    }
    if (v is! bool) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    return v;
  }

  List<Object?>? list(String key) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      return null;
    }
    if (v is! List<Object?>) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    if (v.length > maxListItems && key != 'templates') {
      _bad(RegistryIssueCode.tooLarge, key);
      return null;
    }
    return v;
  }

  List<String> strings(String key) {
    final raw = list(key);
    if (raw == null) {
      return const [];
    }
    final out = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final v = raw[i];
      if (v is! String || v.isEmpty || v.length > maxPatternLength) {
        issues.add(
          RegistryIssue('$path.$key[$i]', RegistryIssueCode.wrongType),
        );
      } else {
        out.add(v);
      }
    }
    return out;
  }

  ObjReader? object(String key) {
    _read.add(key);
    final v = _map[key];
    if (v == null) {
      return null;
    }
    if (v is! Map<String, Object?>) {
      _bad(RegistryIssueCode.wrongType, key);
      return null;
    }
    return ObjReader('$path.$key', v, issues);
  }

  /// Reports every key that was never read. The key name is shown only when
  /// it is a plain identifier (authors need it); anything else is `<key>`, so
  /// an error never repeats arbitrary file content.
  void finish() {
    for (final key in _map.keys) {
      if (!_read.contains(key)) {
        final shown = _identifier.hasMatch(key) ? key : '<key>';
        issues.add(RegistryIssue('$path.$shown', RegistryIssueCode.unknownKey));
      }
    }
  }
}

final RegExp _identifier = RegExp(r'^[A-Za-z0-9_]{1,40}$');

List<CompiledPattern> _patterns(
  ObjReader r,
  String key,
  List<RegistryIssue> issues,
) {
  final out = <CompiledPattern>[];
  final texts = r.strings(key);
  for (var i = 0; i < texts.length; i++) {
    final p = _compileChecked('${r.path}.$key[$i]', texts[i], issues);
    if (p != null) {
      out.add(p);
    }
  }
  return out;
}

CompiledPattern? _compileChecked(
  String path,
  String source,
  List<RegistryIssue> issues,
) {
  final compiled = compilePattern(source);
  if (compiled == null) {
    issues.add(RegistryIssue(path, RegistryIssueCode.badRegex));
    return null;
  }
  final problems = backtrackingProblems(source);
  if (problems.isNotEmpty) {
    issues.add(
      RegistryIssue(path, RegistryIssueCode.unsafeRegex, problems.join(',')),
    );
    return null;
  }
  return compiled;
}

/// Parses `shared.json`. Returns null when it has errors.
SharedConfig? parseShared(String path, String text, List<RegistryIssue> out) {
  final before = out.length;
  final map = decodeObject(path, text, out);
  if (map == null) {
    return null;
  }
  final r = ObjReader(path, map, out);
  final schema = r.integer('schema', min: 1, max: 1000);
  if (schema != null && schema != registrySchemaVersion) {
    out.add(RegistryIssue('$path.schema', RegistryIssueCode.badValue));
  }
  final dropReader = r.object('drop');
  final globalDrop = dropReader == null
      ? <CompiledPattern>[]
      : _patterns(dropReader, 'global', out);
  dropReader?.finish();
  final last4 = _patterns(r, 'last4', out);
  final keywords = r.strings('shortcutKeywords');
  final genericReader = r.object('generic');
  var senderHints = <CompiledPattern>[];
  var bodyHints = <CompiledPattern>[];
  var always = <String>[];
  if (genericReader != null) {
    senderHints = _patterns(genericReader, 'senderHints', out);
    bodyHints = _patterns(genericReader, 'bodyHints', out);
    always = genericReader.strings('alwaysCapture');
    genericReader.finish();
  }
  var cleaning = MerchantCleaningConfig.defaults;
  final cleanReader = r.object('merchantCleaning');
  if (cleanReader != null) {
    cleaning = MerchantCleaningConfig(
      countryTokens: _union(
        MerchantCleaningConfig.defaults.countryTokens,
        cleanReader.strings('countryTokens'),
      ),
      cityPhrases: _union(
        MerchantCleaningConfig.defaults.cityPhrases,
        cleanReader.strings('cityPhrases'),
      ),
      legalSuffixes: _union(
        MerchantCleaningConfig.defaults.legalSuffixes,
        cleanReader.strings('legalSuffixes'),
      ),
      noiseTokens: _union(
        MerchantCleaningConfig.defaults.noiseTokens,
        cleanReader.strings('noiseTokens'),
      ),
    );
    cleanReader.finish();
  }
  r.finish();
  if (out.length != before) {
    return null;
  }
  return SharedConfig(
    globalDrop: globalDrop,
    globalLast4: last4,
    shortcutKeywords: keywords,
    senderHints: senderHints,
    bodyHints: bodyHints,
    alwaysCapture: always,
    merchantCleaning: cleaning,
  );
}

List<String> _union(List<String> base, List<String> extra) {
  final seen = <String>{...base};
  return [
    ...base,
    for (final e in extra)
      if (seen.add(e)) e,
  ];
}

/// Parses one institution file. [fileCode] is the file name without
/// `.json` and must equal the `code` inside. Returns null on any error.
Institution? parseInstitution(
  String path,
  String fileCode,
  String text,
  List<RegistryIssue> out,
) {
  final before = out.length;
  final map = decodeObject(path, text, out);
  if (map == null) {
    return null;
  }
  final r = ObjReader(path, map, out);
  final code = r.string('code', required: true);
  if (code != null && (!_codeShape.hasMatch(code) || code != fileCode)) {
    out.add(RegistryIssue('$path.code', RegistryIssueCode.badValue));
  }
  final names = r.object('names');
  final nameAr = names?.string('ar', required: true);
  final nameEn = names?.string('en', required: true);
  names?.finish();
  if (names == null) {
    out.add(RegistryIssue('$path.names', RegistryIssueCode.missingKey));
  }
  final country = r.string('country', required: true);
  final currencyCode = r.string('defaultCurrency', required: true);
  final currency = currencyCode == null ? null : Currency.tryOf(currencyCode);
  if (currencyCode != null && currency == null) {
    out.add(RegistryIssue('$path.defaultCurrency', RegistryIssueCode.badValue));
  }
  final senders = _senders(r, out);
  final packages = r.strings('packages');
  final cards = r.strings('walletCardNames');
  final last4 = _patterns(r, 'last4', out);
  final drop = _patterns(r, 'drop', out);
  r.string('fixtures'); // optional pointer, informational
  final templates = _templates(r, path, out, currency);
  r.finish();
  if (out.length != before ||
      code == null ||
      nameAr == null ||
      nameEn == null ||
      country == null ||
      currency == null) {
    return null;
  }
  return Institution(
    code: code,
    nameAr: nameAr,
    nameEn: nameEn,
    country: country,
    defaultCurrency: currency,
    senders: senders,
    packages: packages,
    walletCardNames: cards,
    last4: last4,
    drop: drop,
    templates: templates,
  );
}

List<SenderRule> _senders(ObjReader r, List<RegistryIssue> out) {
  final raw = r.list('senders');
  if (raw == null) {
    return const [];
  }
  final rules = <SenderRule>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    final path = '${r.path}.senders[$i]';
    if (item is! Map<String, Object?>) {
      out.add(RegistryIssue(path, RegistryIssueCode.wrongType));
      continue;
    }
    final o = ObjReader(path, item, out);
    final match = o.string('match', required: true);
    final value = o.string('value', required: true);
    o.finish();
    if (match == null || value == null) {
      continue;
    }
    if (match == 'exact') {
      rules.add(SenderRule(SenderMatchKind.exact, value.trim(), null));
    } else if (match == 'regex') {
      final p = _compileChecked('$path.value', value, out);
      if (p != null) {
        rules.add(SenderRule(SenderMatchKind.regex, value, p));
      }
    } else {
      out.add(RegistryIssue('$path.match', RegistryIssueCode.badValue));
    }
  }
  return rules;
}

List<Template> _templates(
  ObjReader r,
  String path,
  List<RegistryIssue> out,
  Currency? defaultCurrency,
) {
  final raw = r.list('templates');
  if (raw == null) {
    out.add(RegistryIssue('${r.path}.templates', RegistryIssueCode.missingKey));
    return const [];
  }
  if (raw.isEmpty || raw.length > maxTemplatesPerInstitution) {
    out.add(RegistryIssue('${r.path}.templates', RegistryIssueCode.badValue));
    return const [];
  }
  final ids = <String>{};
  final templates = <Template>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    final tp = '${r.path}.templates[$i]';
    if (item is! Map<String, Object?>) {
      out.add(RegistryIssue(tp, RegistryIssueCode.wrongType));
      continue;
    }
    final t = _template(ObjReader(tp, item, out), out);
    if (t != null) {
      if (!ids.add(t.id)) {
        out.add(RegistryIssue(tp, RegistryIssueCode.duplicateId));
      } else {
        templates.add(t);
      }
    }
  }
  return templates;
}

Template? _template(ObjReader r, List<RegistryIssue> out) {
  final before = out.length;
  final id = r.string('id', required: true);
  if (id != null && !_idShape.hasMatch(id)) {
    out.add(RegistryIssue('${r.path}.id', RegistryIssueCode.badValue));
  }
  final version = r.integer('version', min: 1, max: 1 << 20);
  final lang = r.string('lang', required: true);
  if (lang != null && lang != 'ar' && lang != 'en') {
    out.add(RegistryIssue('${r.path}.lang', RegistryIssueCode.badValue));
  }
  final channels = <RegistryChannel>{};
  final channelTexts = r.strings('channel');
  for (final c in channelTexts) {
    final ch = RegistryChannel.fromWire(c);
    if (ch == null) {
      out.add(RegistryIssue('${r.path}.channel', RegistryIssueCode.badValue));
    } else {
      channels.add(ch);
    }
  }
  if (channelTexts.isEmpty) {
    channels.add(RegistryChannel.sms);
  }
  final eventText = r.string('event', required: true);
  final event = eventText == null ? null : TemplateEvent.fromWire(eventText);
  if (eventText != null && event == null) {
    out.add(RegistryIssue('${r.path}.event', RegistryIssueCode.badValue));
  }
  final dirText = r.string('direction', required: true);
  final direction = dirText == null
      ? null
      : TemplateDirection.fromWire(dirText);
  if (dirText != null && direction == null) {
    out.add(RegistryIssue('${r.path}.direction', RegistryIssueCode.badValue));
  }
  final confidence = r.permille('baseConfidence');
  final patternText = r.string('pattern', required: true);
  CompiledPattern? pattern;
  final groups = <String>{};
  if (patternText != null) {
    pattern = _compileChecked('${r.path}.pattern', patternText, out);
    for (final m in _groupName.allMatches(patternText)) {
      final name = m.group(1)!;
      if (!templateGroupNames.contains(name)) {
        out.add(
          RegistryIssue('${r.path}.pattern', RegistryIssueCode.unknownGroup),
        );
      }
      groups.add(name);
    }
    if (!groups.contains('amount') && event != TemplateEvent.balanceOnly) {
      out.add(
        RegistryIssue(
          '${r.path}.pattern',
          RegistryIssueCode.missingGroup,
          'amount',
        ),
      );
    }
  }
  final currencyMap = _currencyMap(r, out);
  final date = _date(r, out, groups);
  final localeText = r.string('locale');
  var locale = NumberLocale.standard;
  if (localeText == 'eu') {
    locale = NumberLocale.eu;
  } else if (localeText != null && localeText != 'standard') {
    out.add(RegistryIssue('${r.path}.locale', RegistryIssueCode.badValue));
  }
  var isAvailableLimit = false;
  final flags = r.object('flags');
  if (flags != null) {
    isAvailableLimit = flags.boolean('isAvailableLimit') ?? false;
    flags.finish();
  }
  r.finish();
  if (out.length != before ||
      id == null ||
      version == null ||
      lang == null ||
      event == null ||
      direction == null ||
      confidence == null ||
      pattern == null) {
    return null;
  }
  return Template(
    id: id,
    version: version,
    lang: lang,
    channels: channels,
    event: event,
    direction: direction,
    baseConfidencePermille: confidence,
    pattern: pattern,
    currencyMap: currencyMap,
    date: date,
    locale: locale,
    isAvailableLimit: isAvailableLimit,
    groupNames: groups,
  );
}

Map<String, String> _currencyMap(ObjReader r, List<RegistryIssue> out) {
  final reader = r.object('currencyMap');
  if (reader == null) {
    return const {};
  }
  final map = <String, String>{};
  for (final entry in reader.rawMap.entries) {
    final key = entry.key;
    final v = entry.value;
    final code = v is String ? v : '';
    if (Currency.tryOf(code) == null || key.isEmpty || key.length > 32) {
      out.add(
        RegistryIssue('${reader.path}.currencyMap', RegistryIssueCode.badValue),
      );
      continue;
    }
    map[foldKey(key)] = code;
  }
  return map;
}

DatePolicy? _date(ObjReader r, List<RegistryIssue> out, Set<String> groups) {
  final reader = r.object('date');
  if (reader == null) {
    return null;
  }
  final format = reader.string('format', required: true);
  final policy = reader.string('yearPolicy');
  reader.finish();
  if (format != null && !_dateFormatShape.hasMatch(format)) {
    out.add(RegistryIssue('${reader.path}.format', RegistryIssueCode.badValue));
  }
  if (policy != null && policy != 'nearest_past') {
    out.add(
      RegistryIssue('${reader.path}.yearPolicy', RegistryIssueCode.badValue),
    );
  }
  if (!groups.contains('date')) {
    out.add(RegistryIssue(reader.path, RegistryIssueCode.missingGroup, 'date'));
  }
  if (format == null) {
    return null;
  }
  return DatePolicy(format, policy == 'nearest_past' || policy == null);
}
