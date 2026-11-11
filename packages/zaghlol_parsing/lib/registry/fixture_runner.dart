import '../normalize/text_normalizer.dart';
import '../pipeline/parse_result.dart';
import '../pipeline/parsing_pipeline.dart';
import 'registry_issue.dart';
import 'registry_loader.dart';
import 'registry_models.dart';
import 'registry_schema.dart';
import 'template_extractor.dart';

/// Longest fixture body accepted.
const int maxFixtureBodyLength = 2000;

const Set<String> _expectKeys = {
  'outcome',
  'template',
  'direction',
  'event',
  'amount',
  'currency',
  'originalAmount',
  'originalCurrency',
  'last4',
  'merchantClean',
  'merchantKey',
  'counterparty',
  'ipa',
  'phone',
  'balance',
  'available',
  'ref',
  'date',
  'time',
  'problems',
  ...pipelineExpectKeys,
};

/// `expect` keys answered by the full pipeline (stages 0 to 7) rather than
/// by the template extraction alone. A fixture that sets any of them also
/// requires the pipeline to pick the same template.
const Set<String> pipelineExpectKeys = {
  'confidence',
  'needsReview',
  'occurredAt',
  'language',
  'reasons',
  'counterpartyKind',
};

/// Slowest match of one template on one body the lint accepts. Dart has no
/// regex timeout, so this is a measurement after the fact: it bounds
/// polynomial blow-up on the fixtures and the adversarial bodies, and it can
/// not interrupt an exponential pattern (the backtracking heuristic is the
/// first line of defence for those).
const int defaultMaxMatchMillis = 100;

final RegExp _isoLocal = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:Z|[+-]\d{2}:\d{2})?$',
);

/// What one fixture produced, for the report and the lint.
final class FixtureOutcome {
  const FixtureOutcome(this.path, this.templateId, this.issues);

  final String path;

  /// Template the fixture expected (counts toward coverage when it passed).
  final String? templateId;
  final List<RegistryIssue> issues;

  bool get passed => issues.isEmpty;
}

/// Runs one fixture file (`<institution>/<case>.json`) against [registry].
///
/// Issues carry the fixture path and a field name; message text and values
/// never appear in them.
FixtureOutcome runFixture(
  Registry registry,
  String path,
  String text, {
  int maxMatchMillis = defaultMaxMatchMillis,
}) {
  final issues = <RegistryIssue>[];
  FixtureOutcome done([String? template]) =>
      FixtureOutcome(path, template, issues);
  void fail(RegistryIssueCode code, [String detail = '']) =>
      issues.add(RegistryIssue(path, code, detail));

  final slash = path.indexOf('/');
  final instCode = slash <= 0 ? '' : path.substring(0, slash);
  final institution = registry.byCode(instCode);
  if (institution == null) {
    fail(RegistryIssueCode.fixtureInvalid, 'institution');
    return done();
  }
  final map = decodeObject(path, text, issues);
  if (map == null) {
    return done();
  }
  final r = ObjReader(path, map, issues);
  final sender = r.string('sender');
  final package = r.string('package');
  final channelText = r.string('channel');
  final body = r.string('body', required: true);
  final receivedText = r.string('receivedAt', required: true);
  final expect = r.object('expect');
  if (expect == null) {
    fail(RegistryIssueCode.missingKey, 'expect');
  }
  // `expect` is read below through its raw map.
  r.finish();
  if (issues.isNotEmpty || expect == null || body == null) {
    return done();
  }
  if (body.length > maxFixtureBodyLength) {
    fail(RegistryIssueCode.tooLarge, 'body');
    return done();
  }
  final channel = channelText == null
      ? RegistryChannel.sms
      : RegistryChannel.fromWire(channelText);
  final source = sender ?? package;
  if (channel == null ||
      source == null ||
      (sender != null && package != null)) {
    fail(RegistryIssueCode.fixtureInvalid, 'source');
    return done();
  }
  final received = _parseReceived(receivedText);
  if (received == null) {
    fail(RegistryIssueCode.fixtureInvalid, 'receivedAt');
    return done();
  }
  final expected = expect.rawMap;
  for (final key in expected.keys) {
    if (!_expectKeys.contains(key)) {
      fail(RegistryIssueCode.fixtureInvalid, 'expect.$key');
    }
  }
  if (issues.isNotEmpty) {
    return done();
  }

  final expectedOutcome = expected['outcome'] ?? 'matched';
  final expectedTemplate = expected['template'];
  if (expectedOutcome is! String ||
      !const {'matched', 'dropped', 'unmatched'}.contains(expectedOutcome)) {
    fail(RegistryIssueCode.fixtureInvalid, 'expect.outcome');
    return done();
  }
  if (expectedOutcome == 'matched' && expectedTemplate is! String) {
    fail(RegistryIssueCode.fixtureInvalid, 'expect.template');
    return done();
  }

  final resolved = registry.resolveSource(source, channel);
  if (resolved?.code != institution.code) {
    fail(RegistryIssueCode.fixtureFailed, 'institution');
    return done();
  }

  final folded = foldKeyIndexed(body);
  final dropped = [
    ...institution.drop,
    ...registry.shared.globalDrop,
  ].any((p) => p.regex.hasMatch(folded.text));
  final matches = <(Template, Map<String, String>)>[];
  if (!dropped) {
    for (final t in institution.templates) {
      if (!t.channels.contains(channel)) {
        continue;
      }
      final clock = Stopwatch()..start();
      final groups = matchTemplateOriginal(t, folded, body);
      clock.stop();
      if (clock.elapsedMilliseconds > maxMatchMillis) {
        fail(RegistryIssueCode.slowMatch, t.id);
      }
      if (groups != null) {
        matches.add((t, groups));
      }
    }
  }
  final actualOutcome = dropped
      ? 'dropped'
      : matches.isEmpty
      ? 'unmatched'
      : 'matched';
  if (actualOutcome != expectedOutcome) {
    fail(RegistryIssueCode.fixtureFailed, 'outcome');
    return done();
  }
  if (actualOutcome != 'matched') {
    return done();
  }
  if (matches.length > 1) {
    fail(RegistryIssueCode.crossMatch, matches.map((m) => m.$1.id).join(','));
  }
  final (template, groups) = matches.first;
  if (template.id != expectedTemplate) {
    fail(RegistryIssueCode.fixtureFailed, 'template');
    return done();
  }
  final fields = extractFields(
    institution,
    template,
    groups,
    received,
    cleaning: registry.shared.merchantCleaning,
    foldedBody: folded.text,
    globalLast4: registry.shared.globalLast4,
  );
  final actual = <String, String?>{
    'direction': fields.direction.name,
    'event': fields.event.wire,
    'amount': fields.amount?.toCanonicalString(),
    'currency': fields.amount?.currency.code,
    'originalAmount': fields.originalAmount?.toCanonicalString(),
    'originalCurrency': fields.originalAmount?.currency.code,
    'last4': fields.last4,
    'merchantClean': fields.merchant?.display,
    'merchantKey': fields.merchant?.key,
    'counterparty': fields.counterparty,
    'ipa': fields.ipa,
    'phone': fields.phone,
    'balance': fields.balance?.toCanonicalString(),
    'available': fields.available?.toCanonicalString(),
    'ref': fields.ref,
    'date': fields.date == null ? null : _isoDate(fields.date!),
    'time': fields.time,
  };
  for (final entry in expected.entries) {
    final key = entry.key;
    if (key == 'outcome' ||
        key == 'template' ||
        key == 'problems' ||
        pipelineExpectKeys.contains(key)) {
      continue;
    }
    final want = entry.value;
    if (want != null && want is! String) {
      fail(RegistryIssueCode.fixtureInvalid, 'expect.$key');
      continue;
    }
    if (actual[key] != want) {
      fail(RegistryIssueCode.fixtureFailed, key);
    }
  }
  final wantProblems = expected['problems'];
  final gotProblems = [...fields.problems]..sort();
  final wanted = wantProblems is List<Object?>
      ? (wantProblems.whereType<String>().toList()..sort())
      : const <String>[];
  if (gotProblems.join(',') != wanted.join(',')) {
    fail(RegistryIssueCode.fixtureFailed, 'problems');
  }
  if (pipelineExpectKeys.any(expected.containsKey)) {
    _checkPipeline(
      registry,
      ParseRequest(
        body: body,
        source: source,
        channel: channel,
        receivedAt: received,
      ),
      template.id,
      expected,
      fail,
    );
  }
  return done(template.id);
}

void _checkPipeline(
  Registry registry,
  ParseRequest request,
  String templateId,
  Map<String, Object?> expected,
  void Function(RegistryIssueCode, [String]) fail,
) {
  final result = ParsingPipeline(registry).parse(request);
  if (result is! ParseParsed || result.templateId != templateId) {
    fail(RegistryIssueCode.fixtureFailed, 'pipeline');
    return;
  }
  final actual = <String, String?>{
    'confidence': result.confidencePermille.toString(),
    'needsReview': result.needsReview.toString(),
    'occurredAt': _isoDateTime(result.fields.occurredAt),
    'language': result.language,
    'counterpartyKind': result.fields.counterparty?.kind.name,
  };
  for (final key in pipelineExpectKeys) {
    if (!expected.containsKey(key)) {
      continue;
    }
    final want = expected[key];
    if (key == 'reasons') {
      final got = result.reasons.map((r) => r.name).toList()..sort();
      final wanted = want is List<Object?>
          ? (want.whereType<String>().toList()..sort())
          : null;
      if (wanted == null || got.join(',') != wanted.join(',')) {
        fail(RegistryIssueCode.fixtureFailed, key);
      }
      continue;
    }
    if (want != null && want is! String) {
      fail(RegistryIssueCode.fixtureInvalid, 'expect.$key');
    } else if (actual[key] != want) {
      fail(RegistryIssueCode.fixtureFailed, key);
    }
  }
}

DateTime? _parseReceived(String? text) {
  final m = text == null ? null : _isoLocal.firstMatch(text);
  if (m == null) {
    return null;
  }
  int g(int i) => int.parse(m.group(i) ?? '0');
  // Wall clock as written; the offset is the device zone at receipt (EC-10).
  return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _isoDateTime(DateTime d) =>
    '${_isoDate(d)}T'
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';
