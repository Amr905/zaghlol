import '../generic/generic_parser.dart';
import '../generic/generic_policy.dart';
import '../normalize/text_normalizer.dart';
import '../registry/registry_loader.dart';
import '../registry/registry_models.dart';
import '../registry/template_extractor.dart';
import 'parse_result.dart';

/// Parsing pipeline, stages 0 to 7 (parsing-engine §1 and §4).
///
/// Pure and synchronous: no I/O, no logging, no shared mutable state, so one
/// instance per isolate is enough. [parse] never throws and no result
/// carries message text.
final class ParsingPipeline {
  const ParsingPipeline(this.registry);

  final Registry registry;

  ParseResult parse(ParseRequest request) {
    try {
      return _parse(request);
    } on Object catch (_) {
      // Total function: an unexpected failure becomes a review item instead
      // of crashing the ingest loop. Nothing from the input is kept.
      return const ParseUnrecognized(UnrecognizedReason.internalError);
    }
  }

  ParseResult _parse(ParseRequest request) {
    final body = request.body;
    final r = request.receivedAt;
    // Only the wall-clock fields count (EC-10), whatever the zone flag says.
    final receivedAt = DateTime.utc(
      r.year,
      r.month,
      r.day,
      r.hour,
      r.minute,
      r.second,
    );
    if (body.length > maxParseBodyLength) {
      return const ParseUnrecognized(UnrecognizedReason.bodyTooLong);
    }
    // Stage 1: fold once; keep the map back to the original for display.
    final folded = foldKeyIndexed(body);
    if (folded.text.isEmpty) {
      return const ParseUnrecognized(UnrecognizedReason.emptyBody);
    }

    // Stage 2: institution.
    final institution = registry.resolveSource(request.source, request.channel);

    // Stage 0: guard re-check (same drop rules as the native Guard).
    if (institution != null &&
        institution.drop.any((p) => p.regex.hasMatch(folded.text))) {
      return ParseDropped(DropReason.institutionPattern, institution.code);
    }
    // Global drop patterns see line breaks (`foldKeyLines`), as in the Guard.
    final lines = foldKeyLines(body);
    if (registry.shared.globalDrop.any((p) => p.regex.hasMatch(lines))) {
      return ParseDropped(DropReason.globalPattern, institution?.code);
    }
    if (institution == null) {
      // Stage 8: the generic fallback (FR-PAR-13) for sources that look
      // financial; everything else is an unknown source.
      if (!isGenericCandidate(
        shared: registry.shared,
        source: request.source,
        channel: request.channel,
        foldedBody: folded.text,
      )) {
        return const ParseUnrecognized(UnrecognizedReason.unknownSource);
      }
      return parseGeneric(
        body: body,
        folded: folded,
        receivedAt: receivedAt,
        language: detectLanguage(folded.text).name,
        globalLast4: registry.shared.globalLast4,
        cleaning: registry.shared.merchantCleaning,
      );
    }

    // Stage 3: first matching template, message language first.
    final language = detectLanguage(folded.text);
    ParseUnrecognized? firstFatal;
    for (final template in _candidates(institution, request, language)) {
      final groups = matchTemplateOriginal(template, folded, body);
      if (groups == null) {
        continue;
      }
      // Stage 4: typed extraction.
      final fields = extractFields(
        institution,
        template,
        groups,
        receivedAt,
        cleaning: registry.shared.merchantCleaning,
        foldedBody: folded.text,
        globalLast4: registry.shared.globalLast4,
      );
      final fatal = _fatal(institution, template, fields.problems);
      if (fatal != null) {
        // Keep looking: a later template may read the message properly.
        firstFatal ??= fatal;
        continue;
      }
      return _finish(institution, template, fields, receivedAt, language);
    }
    return firstFatal ??
        ParseUnrecognized(
          UnrecognizedReason.noTemplateMatched,
          institutionCode: institution.code,
        );
  }

  Iterable<Template> _candidates(
    Institution institution,
    ParseRequest request,
    MessageLanguage language,
  ) sync* {
    final eligible = institution.templates
        .where((t) => t.channels.contains(request.channel))
        .toList();
    for (final t in eligible) {
      if (t.lang == language.name) {
        yield t;
      }
    }
    for (final t in eligible) {
      if (t.lang != language.name) {
        yield t;
      }
    }
  }

  ParseUnrecognized? _fatal(
    Institution institution,
    Template template,
    List<String> problems,
  ) {
    UnrecognizedReason? reason;
    if (problems.contains('currency')) {
      reason = UnrecognizedReason.invalidCurrency;
    } else if (problems.contains('amount')) {
      reason = UnrecognizedReason.invalidAmount;
    }
    return reason == null
        ? null
        : ParseUnrecognized(
            reason,
            institutionCode: institution.code,
            templateId: template.id,
          );
  }

  ParseParsed _finish(
    Institution institution,
    Template template,
    ExtractedFields extracted,
    DateTime receivedAt,
    MessageLanguage language,
  ) {
    final reasons = <ParseReason>{};
    for (final problem in extracted.problems) {
      final reason = switch (problem) {
        'originalAmount' ||
        'originalCurrency' => ParseReason.originalAmountInvalid,
        'balance' => ParseReason.balanceInvalid,
        'available' => ParseReason.availableInvalid,
        'last4' => ParseReason.last4Invalid,
        'merchant' => ParseReason.merchantEmpty,
        'date' => ParseReason.dateInvalid,
        _ => null,
      };
      if (reason != null) {
        reasons.add(reason);
      }
    }

    // Stage 5: direction is declared by the template (generic keyword rules
    // belong to the generic parser).
    // Stage 6 (merchant cleaning) already ran inside extractFields.

    final time = extracted.time == null ? null : parseWallTime(extracted.time!);
    if (extracted.time != null && time == null) {
      reasons.add(ParseReason.timeInvalid);
    }
    final date = extracted.date;
    if (date != null && _outOfRange(date, receivedAt)) {
      reasons.add(ParseReason.dateOutOfRange);
    }
    final (occurredAt, source) = resolveOccurredAt(date, time, receivedAt);

    final counterparty = _counterparty(extracted);
    if (template.event != TemplateEvent.balanceOnly &&
        extracted.last4 == null &&
        extracted.merchant == null &&
        counterparty == null &&
        extracted.ref == null) {
      reasons.add(ParseReason.sparseFields);
    }

    if ((extracted.balance?.isNegative ?? false) ||
        (extracted.available?.isNegative ?? false)) {
      reasons.add(ParseReason.balanceNegative);
    }

    // Stage 7: confidence in integer thousandths.
    final ordered = reasons.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    var confidence = template.baseConfidencePermille;
    for (final r in ordered) {
      confidence = confidence * r.factorPermille ~/ 1000;
    }

    return ParseParsed(
      institutionCode: institution.code,
      templateId: template.id,
      templateVersion: template.version,
      language: language.name,
      event: template.event,
      direction: extracted.direction,
      fields: ParsedFields(
        amount: extracted.amount,
        originalAmount: extracted.originalAmount,
        balance: extracted.balance,
        available: extracted.available,
        balanceIsAvailableLimit: template.isAvailableLimit,
        last4: extracted.last4,
        merchant: extracted.merchant,
        counterparty: counterparty,
        ref: extracted.ref,
        date: date,
        time: time,
        occurredAt: occurredAt,
        occurredAtSource: source,
      ),
      confidencePermille: confidence.clamp(0, 1000),
      reasons: ordered,
    );
  }

  Counterparty? _counterparty(ExtractedFields f) {
    if (f.ipa == null && f.phone == null && f.counterparty == null) {
      return null;
    }
    return Counterparty(
      kind: f.ipa != null
          ? CounterpartyKind.ipaAddress
          : f.phone != null
          ? CounterpartyKind.phone
          : CounterpartyKind.name,
      name: f.counterparty,
      ipa: f.ipa,
      phone: f.phone,
    );
  }
}

/// Message language, for ordering templates only.
enum MessageLanguage { ar, en }

/// Arabic when Arabic letters are at least as many as Latin letters (a tie,
/// including no letters at all, is Arabic). Templates of the other language
/// are still tried after those of this one.
MessageLanguage detectLanguage(String text) {
  var arabic = 0;
  var latin = 0;
  for (final u in text.codeUnits) {
    if ((u >= 0x0600 && u <= 0x06FF) ||
        (u >= 0x0750 && u <= 0x077F) ||
        (u >= 0xFB50 && u <= 0xFDFF) ||
        (u >= 0xFE70 && u <= 0xFEFF)) {
      arabic += 1;
    } else if ((u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)) {
      latin += 1;
    }
  }
  return arabic >= latin ? MessageLanguage.ar : MessageLanguage.en;
}

final RegExp _timeShape = RegExp(
  r'^([0-9]{1,2})[:.]([0-9]{2})(?::([0-9]{2}))?(?: ?(am|pm|ص|م))?$',
);

/// Reads `HH:mm`, `H:mm:ss`, `h:mm am/pm` (also `ص`/`م`). Null when the
/// shape or a range is wrong. Digits are normalized first.
WallTime? parseWallTime(String raw) {
  final m = _timeShape.firstMatch(foldKey(raw));
  if (m == null) {
    return null;
  }
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final second = int.parse(m.group(3) ?? '0');
  final marker = m.group(4);
  if (marker != null) {
    if (hour < 1 || hour > 12) {
      return null;
    }
    final pm = marker == 'pm' || marker == 'م';
    hour = hour % 12 + (pm ? 12 : 0);
  }
  if (hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  return WallTime(hour, minute, second);
}

/// Resolves when the event happened (parsing-engine §4.4):
/// - date and time: both from the message;
/// - date only: the time of day of [receivedAt];
/// - time only: the date of [receivedAt], or the day before when that would
///   be later than [receivedAt];
/// - neither: [receivedAt].
(DateTime, OccurredAtSource) resolveOccurredAt(
  DateTime? date,
  WallTime? time,
  DateTime receivedAt,
) {
  if (date != null && time != null) {
    return (
      DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
        time.second,
      ),
      OccurredAtSource.messageDateTime,
    );
  }
  if (date != null) {
    return (
      DateTime.utc(
        date.year,
        date.month,
        date.day,
        receivedAt.hour,
        receivedAt.minute,
        receivedAt.second,
      ),
      OccurredAtSource.messageDate,
    );
  }
  if (time != null) {
    var at = DateTime.utc(
      receivedAt.year,
      receivedAt.month,
      receivedAt.day,
      time.hour,
      time.minute,
      time.second,
    );
    if (at.isAfter(receivedAt)) {
      at = at.subtract(const Duration(days: 1));
    }
    return (at, OccurredAtSource.messageTime);
  }
  return (receivedAt, OccurredAtSource.receivedAt);
}

/// More than 3 days ahead of, or 2 years before, the day of receipt.
bool _outOfRange(DateTime date, DateTime receivedAt) {
  final day = DateTime.utc(receivedAt.year, receivedAt.month, receivedAt.day);
  return date.isAfter(day.add(const Duration(days: 3))) ||
      date.isBefore(DateTime.utc(day.year - 2, day.month, day.day));
}
