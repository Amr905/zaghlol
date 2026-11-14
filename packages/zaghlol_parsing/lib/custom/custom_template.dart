import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../pipeline/parsing_pipeline.dart';
import '../registry/regex_safety.dart';
import '../registry/registry_loader.dart';
import '../registry/registry_models.dart';

// T-164 / FR-PAR-07: the custom message template engine.
//
// A Gold user tags parts of one sample message; [buildCustomTemplate]
// generates a regex template from the tagged spans and the text between
// them. The user never writes a regex, but a stored template (database row,
// backup) is still untrusted input: [CustomTemplateSpec.fromJson] re-checks
// everything (length caps, group names, `backtrackingProblems`, compile),
// and the generator itself only emits bounded shapes.
//
// Privacy: pure and I/O free. No result, error or `toString` carries message
// text; errors are codes. The pattern holds the literal words between the
// tagged parts (that is the template), never the tagged values.

/// Longest sample the builder accepts (the parser's body cap).
const int maxCustomSampleLength = maxParseBodyLength;

/// Most tagged spans in one template (one per tag kind).
const int maxCustomSpans = 6;

/// Longest literal kept next to a tagged part at the ends of the pattern.
const int _edgeLiteral = 24;

/// A middle literal longer than this is shortened to its two ends joined by
/// a bounded wildcard.
const int _middleLiteral = 48;

/// Most currency words one template maps.
const int maxCurrencyWords = 8;

/// Egyptian pound words a template on an EGP default also understands.
const List<String> _egpWords = ['جم', 'ج.م', 'جنيه', 'جنيها', 'egp'];

/// Most messages [testCustomTemplate] reads.
const int maxCustomTestMessages = 200;

/// A match slower than this is reported (never aborted: Dart regexes can not
/// be interrupted, so the bounded generator and the pattern lint are the
/// protection).
const int slowMatchMicros = 50000;

/// What a user can tag. [group] is the registry group name.
enum CustomTag {
  amount('amount'),
  currency('cur'),
  merchant('merchant'),
  last4('last4'),
  balance('balance'),
  date('date');

  const CustomTag(this.group);
  final String group;
}

/// A tagged part of the sample, in code-unit offsets of the original text.
final class TagSpan {
  const TagSpan(this.tag, this.start, this.end);

  final CustomTag tag;
  final int start;
  final int end;
}

/// Why a template could not be built or loaded. Codes only.
enum CustomTemplateError {
  sampleEmpty,
  sampleTooLong,
  noAmountTag,
  tooManySpans,
  duplicateTag,
  badSpan,
  overlap,
  badAmount,
  badBalance,
  badLast4,
  badDate,
  badCurrency,
  badMerchant,
  senderInvalid,
  patternUnsafe,
  selfParseFailed,
  invalidStored,
}

const Set<String> _channels = {'sms', 'notification', 'shortcut_message'};
const Set<String> _storedGroups = {
  'amount',
  'cur',
  'merchant',
  'last4',
  'balance',
  'date',
};

final RegExp _senderBad = RegExp(r'[\u0000-\u001F\u007F-\u009F]');
final RegExp _amountShape = RegExp(r'^[0-9](?:[0-9.,]*[0-9])?$');
final RegExp _dateShape = RegExp(
  r'^([0-9]{1,4})([/.-])([0-9]{1,2})(?:([/.-])([0-9]{2,4}))?$',
);
final RegExp _groupName = RegExp(r'\(\?<([a-z0-9]+)>');
final RegExp _dateFormatShape = RegExp(
  r'^(?:dd?[/.-]MM?(?:[/.-](?:yyyy|yy))?|yyyy[/.-]MM?[/.-]dd?)$',
);

/// A custom template as stored (`custom_templates.template_json`).
final class CustomTemplateSpec {
  const CustomTemplateSpec._({
    required this.sender,
    required this.channel,
    required this.pattern,
    required this.direction,
    required this.defaultCurrency,
    required this.lang,
    required this.dateFormat,
    required this.nearestPast,
    required this.locale,
    required this.currencyMap,
  });

  static const int version = 1;

  /// The sender id (SMS address) or package the template belongs to.
  final String sender;

  /// `sms`, `notification` or `shortcut_message`.
  final String channel;

  /// Registry-style pattern with named groups, for folded text.
  final String pattern;

  /// `expense` or `income`.
  final TemplateDirection direction;

  /// Used when the message has no currency part.
  final Currency defaultCurrency;
  final String lang;
  final String? dateFormat;
  final bool nearestPast;
  final NumberLocale locale;

  /// Folded currency words of the message (`جم`) to ISO codes. A word the
  /// user tagged that no built-in marker knows is mapped to
  /// [defaultCurrency] here, visibly, never guessed at parse time.
  final Map<String, String> currencyMap;

  Set<String> get groups => {
    for (final m in _groupName.allMatches(pattern)) m.group(1)!,
  };

  Map<String, Object?> toJson() => {
    'v': version,
    'sender': sender,
    'channel': channel,
    'pattern': pattern,
    'direction': direction.name,
    'currency': defaultCurrency.code,
    'lang': lang,
    'dateFormat': dateFormat,
    'nearestPast': nearestPast,
    'locale': locale == NumberLocale.eu ? 'eu' : 'standard',
    'currencyMap': currencyMap,
  };

  /// Validates stored JSON as untrusted input. Never throws.
  static CustomTemplateSpec? fromJson(Object? json) {
    try {
      return _fromJson(json);
    } on Object {
      return null;
    }
  }

  static CustomTemplateSpec? _fromJson(Object? json) {
    if (json is! Map || json['v'] != version) {
      return null;
    }
    final sender = json['sender'];
    final channel = json['channel'];
    final pattern = json['pattern'];
    final direction = json['direction'];
    final currency = json['currency'];
    final lang = json['lang'];
    final dateFormat = json['dateFormat'];
    final nearestPast = json['nearestPast'];
    final locale = json['locale'];
    final map = json['currencyMap'];
    if (map is! Map ||
        map.length > maxCurrencyWords ||
        !map.entries.every(
          (e) =>
              e.key is String &&
              (e.key as String).isNotEmpty &&
              (e.key as String).length <= 16 &&
              e.value is String &&
              Currency.tryOf(e.value as String) != null,
        )) {
      return null;
    }
    if (sender is! String ||
        !validSender(sender) ||
        channel is! String ||
        !_channels.contains(channel) ||
        pattern is! String ||
        direction is! String ||
        currency is! String ||
        (lang != 'ar' && lang != 'en') ||
        (dateFormat != null && dateFormat is! String) ||
        nearestPast is! bool ||
        (locale != 'standard' && locale != 'eu')) {
      return null;
    }
    final dir = TemplateDirection.fromWire(direction);
    final cur = Currency.tryOf(currency);
    if (dir == null || dir == TemplateDirection.neutral || cur == null) {
      return null;
    }
    if (!_patternAcceptable(pattern)) {
      return null;
    }
    final names = {for (final m in _groupName.allMatches(pattern)) m.group(1)!};
    if (!names.contains('amount') || !_storedGroups.containsAll(names)) {
      return null;
    }
    if (names.contains('date')) {
      if (dateFormat is! String || !_dateFormatShape.hasMatch(dateFormat)) {
        return null;
      }
    } else if (dateFormat != null) {
      return null;
    }
    return CustomTemplateSpec._(
      sender: sender,
      channel: channel,
      pattern: pattern,
      direction: dir,
      defaultCurrency: cur,
      lang: lang as String,
      dateFormat: dateFormat as String?,
      nearestPast: nearestPast,
      locale: locale == 'eu' ? NumberLocale.eu : NumberLocale.standard,
      currencyMap: {
        for (final e in map.entries) e.key as String: e.value as String,
      },
    );
  }

  /// The template as an institution the pipeline can resolve by [sender].
  /// [id] is the `custom_templates.id`; the institution code is derived from
  /// it (`custom_` + up to 24 lowercase hex or letters).
  Institution toInstitution(String id) {
    final code = customInstitutionCode(id);
    final compiled = compilePattern(pattern)!;
    final channelKind = RegistryChannel.fromWire(channel)!;
    final template = Template(
      id: '${code}_t1',
      version: 1,
      lang: lang,
      channels: {channelKind},
      event: direction == TemplateDirection.income
          ? TemplateEvent.transferIn
          : TemplateEvent.cardPurchase,
      direction: direction,
      baseConfidencePermille: 850,
      pattern: compiled,
      currencyMap: currencyMap,
      date: dateFormat == null ? null : DatePolicy(dateFormat!, nearestPast),
      locale: locale,
      isAvailableLimit: false,
      groupNames: groups,
    );
    return Institution(
      code: code,
      nameAr: 'custom',
      nameEn: 'custom',
      country: 'EG',
      defaultCurrency: defaultCurrency,
      senders: channelKind == RegistryChannel.notification
          ? const []
          : [SenderRule(SenderMatchKind.exact, sender, null)],
      packages: channelKind == RegistryChannel.notification ? [sender] : [],
      walletCardNames: const [],
      last4: const [],
      drop: const [],
      templates: [template],
    );
  }

  @override
  String toString() => 'CustomTemplateSpec(<redacted>)';
}

/// `custom_<id>` limited to `[a-z0-9_]`, at most 32 characters.
String customInstitutionCode(String id) {
  final slug = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final cut = slug.length > 24 ? slug.substring(0, 24) : slug;
  return 'custom_${cut.isEmpty ? 'x' : cut}';
}

/// 1 to 128 characters, no control characters (the table's CHECK).
bool validSender(String sender) =>
    sender.isNotEmpty && sender.length <= 128 && !_senderBad.hasMatch(sender);

bool _patternAcceptable(String pattern) {
  if (pattern.isEmpty || pattern.length > maxPatternLength) {
    return false;
  }
  if (backtrackingProblems(pattern).isNotEmpty) {
    return false;
  }
  return compilePattern(pattern) != null;
}

/// Result of [buildCustomTemplate]: a spec or an error code.
final class CustomTemplateBuild {
  const CustomTemplateBuild._(this.spec, this.error);

  final CustomTemplateSpec? spec;
  final CustomTemplateError? error;

  bool get ok => spec != null;
}

CustomTemplateBuild _fail(CustomTemplateError e) =>
    CustomTemplateBuild._(null, e);

/// One whitespace-delimited word of [sample], for the tap-to-tag UI.
final class SampleToken {
  const SampleToken(this.start, this.end);

  final int start;
  final int end;
}

/// Splits [sample] into tappable words: runs of non-space characters, with
/// surrounding quotes, brackets and the sentence punctuation `: ; , .`
/// trimmed off (a dot or comma inside a number stays).
List<SampleToken> tokenizeSample(String sample) {
  final out = <SampleToken>[];
  final units = sample.codeUnits;
  var i = 0;
  while (i < units.length) {
    if (_isSpaceUnit(units[i])) {
      i += 1;
      continue;
    }
    var j = i;
    while (j < units.length && !_isSpaceUnit(units[j])) {
      j += 1;
    }
    var a = i;
    var b = j;
    while (a < b && _isEdgePunct(units[a])) {
      a += 1;
    }
    while (b > a && _isEdgePunct(units[b - 1])) {
      b -= 1;
    }
    if (a < b) {
      out.add(SampleToken(a, b));
    }
    i = j;
  }
  return out;
}

bool _isSpaceUnit(int u) =>
    u == 0x20 || (u >= 0x09 && u <= 0x0D) || u == 0xA0 || u == 0x200F;

bool _isEdgePunct(int u) =>
    u == 0x3A || // :
    u == 0x3B || // ;
    u == 0x2C || // ,
    u == 0x2E || // .
    u == 0x28 || // (
    u == 0x29 || // )
    u == 0x22 || // "
    u == 0x27 || // '
    u == 0x5B || // [
    u == 0x5D || // ]
    u == 0x60C; // arabic comma

/// Builds a template from a [sample] and the user's [spans]. Never throws.
///
/// The template is accepted only if it passes the safety lint and parses its
/// own sample into a transaction (`selfParseFailed` otherwise).
CustomTemplateBuild buildCustomTemplate({
  required String sample,
  required List<TagSpan> spans,
  required TemplateDirection direction,
  required String sender,
  String channel = 'sms',
  Currency? defaultCurrency,
}) {
  try {
    return _build(
      sample,
      spans,
      direction,
      sender,
      channel,
      defaultCurrency ?? Currency.of('EGP'),
    );
  } on Object {
    return _fail(CustomTemplateError.patternUnsafe);
  }
}

CustomTemplateBuild _build(
  String sample,
  List<TagSpan> spans,
  TemplateDirection direction,
  String sender,
  String channel,
  Currency defaultCurrency,
) {
  if (sample.trim().isEmpty) {
    return _fail(CustomTemplateError.sampleEmpty);
  }
  if (sample.length > maxCustomSampleLength) {
    return _fail(CustomTemplateError.sampleTooLong);
  }
  if (spans.isEmpty || !spans.any((s) => s.tag == CustomTag.amount)) {
    return _fail(CustomTemplateError.noAmountTag);
  }
  if (spans.length > maxCustomSpans) {
    return _fail(CustomTemplateError.tooManySpans);
  }
  if (direction == TemplateDirection.neutral ||
      !_channels.contains(channel) ||
      !validSender(sender.trim())) {
    return _fail(CustomTemplateError.senderInvalid);
  }
  if ({for (final s in spans) s.tag}.length != spans.length) {
    return _fail(CustomTemplateError.duplicateTag);
  }

  final folded = foldKeyIndexed(sample);
  final text = folded.text;
  // Original offset -> folded offset.
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final parts = <_Part>[];
  var cursor = 0;
  for (final s in sorted) {
    if (s.start < 0 || s.end > sample.length || s.start >= s.end) {
      return _fail(CustomTemplateError.badSpan);
    }
    final range = _foldedRange(folded, s.start, s.end);
    if (range == null) {
      return _fail(CustomTemplateError.badSpan);
    }
    var (a, b) = range;
    if (s.tag == CustomTag.amount || s.tag == CustomTag.balance) {
      while (b > a && (text[b - 1] == '.' || text[b - 1] == ',')) {
        b -= 1;
      }
    }
    if (a >= b) {
      return _fail(CustomTemplateError.badSpan);
    }
    if (a < cursor) {
      return _fail(CustomTemplateError.overlap);
    }
    parts.add(_Part(s.tag, a, b));
    cursor = b;
  }

  CustomTemplateError? invalid;
  String? dateFormat;
  var nearestPast = false;
  var locale = NumberLocale.standard;
  final currencyMap = <String, String>{};
  final buffer = StringBuffer();
  var pos = 0;
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    final value = text.substring(p.start, p.end);
    final literal = text.substring(pos, p.start);
    final first = i == 0;
    buffer.write(_literalPattern(literal, first ? _Edge.head : _Edge.middle));
    final lastPart = i == parts.length - 1;
    final trailing = lastPart ? text.substring(p.end) : null;
    final followed =
        !lastPart || (trailing != null && trailing.trim().isNotEmpty);
    switch (p.tag) {
      case CustomTag.amount:
      case CustomTag.balance:
        if (!_amountShape.hasMatch(value)) {
          invalid ??= p.tag == CustomTag.amount
              ? CustomTemplateError.badAmount
              : CustomTemplateError.badBalance;
        }
        if (p.tag == CustomTag.amount) {
          locale = _localeOf(value);
        }
        buffer.write('(?<${p.tag.group}>[0-9](?:[0-9.,]*[0-9])?)');
      case CustomTag.currency:
        if (value.length > 8 || RegExp(r'[0-9\s]').hasMatch(value)) {
          invalid ??= CustomTemplateError.badCurrency;
        } else if (resolveCurrencyMarker(value, defaultCurrency) == null) {
          currencyMap[value] = defaultCurrency.code;
        }
        buffer.write(r'(?<cur>[^\s0-9]{1,8})');
      case CustomTag.last4:
        if (!RegExp(r'^[0-9]{4}$').hasMatch(value)) {
          invalid ??= CustomTemplateError.badLast4;
        }
        buffer.write('(?<last4>[0-9]{4})');
      case CustomTag.merchant:
        if (value.isEmpty || value.length > 60 || value.contains('\n')) {
          invalid ??= CustomTemplateError.badMerchant;
        }
        // Lazy when something follows (the next literal ends it), otherwise
        // greedy up to the cap.
        buffer.write(
          followed ? '(?<merchant>.{1,60}?)' : '(?<merchant>[^\\n]{1,60})',
        );
      case CustomTag.date:
        final shape = _dateShape.firstMatch(value);
        if (shape == null) {
          invalid ??= CustomTemplateError.badDate;
          break;
        }
        final sep1 = RegExp.escape(shape.group(2)!);
        final sep2 = shape.group(4);
        final y = shape.group(5);
        final first = shape.group(1)!;
        if (first.length == 4) {
          if (sep2 == null || y == null || y.length > 2) {
            invalid ??= CustomTemplateError.badDate;
            break;
          }
          dateFormat =
              'yyyy${shape.group(2)}MM$sep2'
              'dd';
          buffer.write(
            '(?<date>[0-9]{4}$sep1[0-9]{1,2}${RegExp.escape(sep2)}[0-9]{1,2})',
          );
        } else {
          dateFormat = 'dd${shape.group(2)}MM';
          var body = '[0-9]{1,2}$sep1[0-9]{1,2}';
          if (sep2 != null && y != null) {
            dateFormat = '$dateFormat$sep2${y.length == 4 ? 'yyyy' : 'yy'}';
            body += '${RegExp.escape(sep2)}[0-9]{${y.length == 4 ? 4 : 2}}';
          } else {
            nearestPast = true;
          }
          buffer.write('(?<date>$body)');
        }
    }
    pos = p.end;
  }
  buffer.write(_literalPattern(text.substring(pos), _Edge.tail));
  if (invalid != null) {
    return _fail(invalid);
  }
  if (currencyMap.isNotEmpty && defaultCurrency.code == 'EGP') {
    for (final w in _egpWords) {
      currencyMap.putIfAbsent(foldKey(w), () => 'EGP');
    }
  }
  var pattern = buffer.toString();
  if (parts.first.start == 0) {
    pattern = '^$pattern';
  }
  if (!_patternAcceptable(pattern)) {
    return _fail(CustomTemplateError.patternUnsafe);
  }
  final spec = CustomTemplateSpec._(
    sender: sender.trim(),
    channel: channel,
    pattern: pattern,
    direction: direction,
    defaultCurrency: defaultCurrency,
    lang: detectLanguage(text).name,
    dateFormat: dateFormat,
    nearestPast: nearestPast,
    locale: locale,
    currencyMap: currencyMap,
  );
  final stopwatch = Stopwatch()..start();
  final self = _parseWith(spec, 'self', sample, DateTime.utc(2026, 1, 1));
  stopwatch.stop();
  if (self is! ParseParsed ||
      self.fields.amount == null ||
      stopwatch.elapsedMicroseconds > slowMatchMicros * 4) {
    return _fail(CustomTemplateError.selfParseFailed);
  }
  return CustomTemplateBuild._(spec, null);
}

NumberLocale _localeOf(String amount) {
  final comma = amount.lastIndexOf(',');
  final dot = amount.lastIndexOf('.');
  if (comma >= 0 && dot >= 0) {
    return comma > dot ? NumberLocale.eu : NumberLocale.standard;
  }
  if (comma >= 0 && amount.length - comma - 1 <= 2) {
    return NumberLocale.eu;
  }
  return NumberLocale.standard;
}

enum _Edge { head, middle, tail }

final class _Part {
  const _Part(this.tag, this.start, this.end);

  final CustomTag tag;
  final int start;
  final int end;
}

/// Folded range covering the original span `[start, end)`, or null.
(int, int)? _foldedRange(FoldedText f, int start, int end) {
  var a = -1;
  var b = -1;
  for (var i = 0; i < f.origin.length; i++) {
    final o = f.origin[i];
    if (o >= start && o < end) {
      if (a < 0) {
        a = i;
      }
      b = i + 1;
    }
  }
  if (a < 0) {
    return null;
  }
  // Trim folded whitespace at the ends.
  while (a < b && f.text[a] == ' ') {
    a += 1;
  }
  while (b > a && f.text[b - 1] == ' ') {
    b -= 1;
  }
  return a < b ? (a, b) : null;
}

/// Pattern text for the literal between tagged parts (folded text): spaces
/// become `\s+`, digit runs `[0-9]+` (a reference or counter may differ),
/// everything else is escaped. Long literals keep their ends only.
String _literalPattern(String literal, _Edge edge) {
  var text = literal;
  switch (edge) {
    case _Edge.head:
      if (text.length > _edgeLiteral) {
        text = text.substring(text.length - _edgeLiteral);
      }
    case _Edge.tail:
      if (text.length > _edgeLiteral) {
        text = text.substring(0, _edgeLiteral);
      }
    case _Edge.middle:
      if (text.length > _middleLiteral) {
        final gap = (text.length - 32) * 2 + 20;
        return '${_escape(text.substring(0, 16))}'
            '[\\s\\S]{0,${gap > 300 ? 300 : gap}}?'
            '${_escape(text.substring(text.length - 16))}';
      }
  }
  return _escape(text);
}

String _escape(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (c == 0x20) {
      out.write(r'\s+');
      while (i < text.length && text.codeUnitAt(i) == 0x20) {
        i += 1;
      }
    } else if (c >= 0x30 && c <= 0x39) {
      out.write('[0-9]+');
      while (i < text.length &&
          text.codeUnitAt(i) >= 0x30 &&
          text.codeUnitAt(i) <= 0x39) {
        i += 1;
      }
    } else {
      out.write(RegExp.escape(text[i]));
      i += 1;
    }
  }
  return out.toString();
}

ParseResult _parseWith(
  CustomTemplateSpec spec,
  String id,
  String body,
  DateTime receivedAt,
) {
  final registry = Registry.ofInstitutions([spec.toInstitution(id)]);
  return ParsingPipeline(registry).parse(
    ParseRequest(
      body: body,
      source: spec.sender,
      channel: RegistryChannel.fromWire(spec.channel)!,
      receivedAt: receivedAt,
    ),
  );
}

/// Why one message did not match (`templates_builder_testFailReason`).
enum CustomTestFailure { amount, other }

/// Counts of [testCustomTemplate]. No text.
final class CustomTestReport {
  const CustomTestReport({
    required this.total,
    required this.matched,
    required this.failures,
    required this.slowest,
  });

  final int total;
  final int matched;

  /// Index into the tested list, with the reason, for each miss (first 20).
  final List<(int, CustomTestFailure)> failures;

  /// Slowest single parse, in microseconds.
  final int slowest;

  bool get slow => slowest > slowMatchMicros;
}

/// Runs [spec] over [messages] (at most [maxCustomTestMessages]; the rest
/// are not read). Never throws.
CustomTestReport testCustomTemplate(
  CustomTemplateSpec spec,
  List<String> messages, {
  DateTime? receivedAt,
}) {
  final at = receivedAt ?? DateTime.now();
  final n = messages.length > maxCustomTestMessages
      ? maxCustomTestMessages
      : messages.length;
  final registry = Registry.ofInstitutions([spec.toInstitution('test')]);
  final pipeline = ParsingPipeline(registry);
  final channel = RegistryChannel.fromWire(spec.channel)!;
  final failures = <(int, CustomTestFailure)>[];
  var matched = 0;
  var slowest = 0;
  final watch = Stopwatch();
  for (var i = 0; i < n; i++) {
    watch
      ..reset()
      ..start();
    final r = pipeline.parse(
      ParseRequest(
        body: messages[i],
        source: spec.sender,
        channel: channel,
        receivedAt: at,
      ),
    );
    watch.stop();
    if (watch.elapsedMicroseconds > slowest) {
      slowest = watch.elapsedMicroseconds;
    }
    if (r is ParseParsed && r.fields.amount != null) {
      matched += 1;
    } else if (failures.length < 20) {
      final amountProblem =
          r is ParseUnrecognized &&
          r.reason == UnrecognizedReason.invalidAmount;
      failures.add((
        i,
        amountProblem ? CustomTestFailure.amount : CustomTestFailure.other,
      ));
    }
  }
  return CustomTestReport(
    total: n,
    matched: matched,
    failures: failures,
    slowest: slowest,
  );
}

/// Parses one message with [spec] (the re-parse job and the screen use it).
ParseResult parseWithCustomTemplate(
  CustomTemplateSpec spec,
  String id,
  String body,
  DateTime receivedAt,
) => _parseWith(spec, id, body, receivedAt);
