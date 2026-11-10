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
};

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
FixtureOutcome runFixture(Registry registry, String path, String text) {
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

  final folded = foldBody(body);
  final dropped = [
    ...institution.drop,
    ...registry.shared.globalDrop,
  ].any((p) => p.regex.hasMatch(folded));
  final matches = <(Template, Map<String, String>)>[];
  if (!dropped) {
    for (final t in institution.templates) {
      if (!t.channels.contains(channel)) {
        continue;
      }
      final groups = matchTemplate(t, folded);
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
    if (key == 'outcome' || key == 'template' || key == 'problems') {
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
  return done(template.id);
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
