import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../merchant/merchant_cleaner.dart';
import '../normalize/amount_parser.dart';
import '../normalize/currency_markers.dart';
import '../normalize/text_normalizer.dart';
import 'registry_models.dart';

/// Typed fields read from one template match (parsing-engine §4, stage 4).
///
/// This is the minimal extraction the registry lint needs to run fixtures;
/// the pipeline (T-033) adds stages 0, 5, 7 and the generic fallback around
/// it. [problems] lists the field names that matched but could not be read
/// (`amount`, `currency`, `last4`, `date`...): never values.
final class ExtractedFields {
  const ExtractedFields({
    required this.templateId,
    required this.event,
    required this.direction,
    this.amount,
    this.originalAmount,
    this.balance,
    this.available,
    this.last4,
    this.merchant,
    this.counterparty,
    this.ipa,
    this.phone,
    this.ref,
    this.date,
    this.time,
    this.problems = const [],
  });

  final String templateId;
  final TemplateEvent event;
  final TemplateDirection direction;
  final Money? amount;
  final Money? originalAmount;
  final Money? balance;
  final Money? available;
  final String? last4;

  /// Cleaned merchant (display form and `merchant_norm` key).
  final CleanedMerchant? merchant;
  final String? counterparty;
  final String? ipa;
  final String? phone;
  final String? ref;

  /// Calendar date (UTC midnight is used only to carry y/m/d).
  final DateTime? date;
  final String? time;
  final List<String> problems;
}

/// Folds a message body for matching (`foldKey`).
String foldBody(String body) => foldKey(body);

/// Runs [template] against an already folded body. Returns the named
/// captures, or null when the pattern does not match.
Map<String, String>? matchTemplate(Template template, String foldedBody) {
  final m = template.pattern.regex.firstMatch(foldedBody);
  if (m == null) {
    return null;
  }
  final out = <String, String>{};
  for (final name in template.groupNames) {
    final v = m.namedGroup(name);
    if (v != null && v.isNotEmpty) {
      out[name] = v;
    }
  }
  return out;
}

/// Groups whose captured text is shown to the user (or stored as an id) and
/// is therefore taken from the original message, not the folded one.
const Set<String> displayGroups = {
  'merchant',
  'counterparty',
  'ipa',
  'phone',
  'ref',
};

/// Like [matchTemplate], but the [displayGroups] captures are read from the
/// [original] text (through the offset map of [folded]) and normalized only
/// for digits, tatweel and harakat: case and letter variants (alef, ya, ta
/// marbuta) are kept, so an Arabic counterparty name shows as written.
/// The regex still runs on the folded text.
///
/// Dart reports no group offsets, so the capture is located by its text
/// inside the matched region. When the same folded text occurs twice in that
/// region the position is ambiguous and the folded capture is returned for
/// that group (never a wrong span): letters then show folded and Latin text
/// lower-cased, which merchant cleaning absorbs.
Map<String, String>? matchTemplateOriginal(
  Template template,
  FoldedText folded,
  String original,
) {
  final m = template.pattern.regex.firstMatch(folded.text);
  if (m == null) {
    return null;
  }
  final out = <String, String>{};
  for (final name in template.groupNames) {
    final v = m.namedGroup(name);
    if (v == null || v.isEmpty) {
      continue;
    }
    if (displayGroups.contains(name)) {
      final at = _uniqueOffset(folded.text, v, m.start, m.end);
      final span = at == null
          ? null
          : folded.originalSpan(original, at, at + v.length);
      final shown = span == null ? null : foldForMatching(span);
      out[name] = shown == null || shown.isEmpty ? v : shown;
      continue;
    }
    out[name] = v;
  }
  return out;
}

/// Offset of [value] inside `text[from, to)` when it occurs exactly once.
int? _uniqueOffset(String text, String value, int from, int to) {
  final first = text.indexOf(value, from);
  if (first < 0 || first + value.length > to) {
    return null;
  }
  final second = text.indexOf(value, first + 1);
  if (second >= 0 && second + value.length <= to) {
    return null;
  }
  return first;
}

/// Reads typed fields from [groups]. [receivedAt] carries the device-local
/// wall clock of receipt as a UTC-flagged `DateTime` (the zone is the
/// device's, EC-10); it is used for dates without a year.
ExtractedFields extractFields(
  Institution institution,
  Template template,
  Map<String, String> groups,
  DateTime receivedAt, {
  MerchantCleaningConfig cleaning = MerchantCleaningConfig.defaults,

  /// Folded body and the shared `last4` patterns: when the template has no
  /// `last4` group, the institution patterns and then these are tried (both
  /// are registry data, first hit wins).
  String? foldedBody,
  List<CompiledPattern> globalLast4 = const [],
}) {
  final problems = <String>[];

  Currency? resolve(String? marker) {
    if (marker == null) {
      return institution.defaultCurrency;
    }
    final folded = foldKey(marker);
    final mapped = template.currencyMap[folded];
    if (mapped != null) {
      return Currency.tryOf(mapped);
    }
    return resolveCurrencyMarker(folded, institution.defaultCurrency);
  }

  Money? money(String key, Currency? currency, String field) {
    final raw = groups[key];
    if (raw == null) {
      return null;
    }
    if (currency == null) {
      problems.add(field);
      return null;
    }
    var text = _dropTrailingPunctuation(raw);
    // FU-078: an overdrawn balance (`-500.00`, `−500.00`) is a real negative
    // amount. One leading sign, balance and available only; an amount with
    // a sign stays a problem (a charge is never negative).
    var negative = false;
    if ((key == 'balance' || key == 'available') && text.isNotEmpty) {
      final first = text.codeUnitAt(0);
      if (first == 0x2D || first == 0x2212) {
        negative = true;
        text = text.substring(1).trimLeft();
      }
    }
    final result = parseAmount(
      text,
      currency: currency,
      locale: template.locale,
    );
    final value = result.valueOrNull;
    if (value == null || (key == 'amount' && !value.isPositive)) {
      problems.add(field);
      return null;
    }
    return negative ? -value : value;
  }

  // A `cur` capture that cannot be resolved is a problem, never a silent
  // fall back to the institution currency (money is never silently
  // converted).
  final currency = resolve(groups['cur']);
  if (currency == null) {
    problems.add('currency');
  }
  final amount = money('amount', currency, 'amount');
  if (template.event != TemplateEvent.balanceOnly &&
      amount == null &&
      !problems.contains('amount')) {
    problems.add('amount');
  }
  final balance = money('balance', currency, 'balance');
  final available = money('available', currency, 'available');
  Money? original;
  if (groups.containsKey('oamount')) {
    final ocur = groups['ocur'] == null ? null : resolve(groups['ocur']);
    if (groups['ocur'] == null || ocur == null) {
      problems.add('originalCurrency');
    } else {
      original = money('oamount', ocur, 'originalAmount');
    }
  }

  var last4 = groups['last4'];
  if (last4 != null && !RegExp(r'^[0-9]{4}$').hasMatch(last4)) {
    problems.add('last4');
    last4 = null;
  }

  if (last4 == null &&
      foldedBody != null &&
      !template.groupNames.contains('last4')) {
    last4 = _declaredLast4([...institution.last4, ...globalLast4], foldedBody);
  }

  final merchantRaw = groups['merchant'];
  final merchant = merchantRaw == null
      ? null
      : cleanMerchant(merchantRaw, config: cleaning);
  if (merchant != null && merchant.display.isEmpty) {
    problems.add('merchant');
  }

  DateTime? date;
  final dateRaw = groups['date'];
  if (dateRaw != null && template.date != null) {
    date = parseTemplateDate(dateRaw, template.date!, receivedAt);
    if (date == null) {
      problems.add('date');
    }
  }

  return ExtractedFields(
    templateId: template.id,
    event: template.event,
    direction: template.direction,
    amount: amount,
    originalAmount: original,
    balance: balance,
    available: available,
    last4: last4,
    merchant: merchant == null || merchant.display.isEmpty ? null : merchant,
    counterparty: groups['counterparty'],
    ipa: groups['ipa'],
    phone: groups['phone'],
    ref: groups['ref'],
    date: date,
    time: groups['time'],
    problems: problems,
  );
}

String? _declaredLast4(List<CompiledPattern> patterns, String foldedBody) {
  for (final p in patterns) {
    final digits = p.regex.firstMatch(foldedBody)?.group(1);
    if (digits != null && RegExp(r'^[0-9]{4}$').hasMatch(digits)) {
      return digits;
    }
  }
  return null;
}

/// A number capture may run into sentence punctuation (`150.`); one trailing
/// `.` or `,` after a digit is dropped. Template authors should still keep
/// the punctuation out of the capture.
String _dropTrailingPunctuation(String raw) {
  final t = raw.trim();
  if (t.length > 1 && RegExp(r'[0-9][.,]$').hasMatch(t)) {
    return t.substring(0, t.length - 1);
  }
  return t;
}

/// Parses a date capture by [policy.format]. Returns null for any shape or
/// calendar mismatch (31/2, month 13) instead of rolling over.
DateTime? parseTemplateDate(
  String raw,
  DatePolicy policy,
  DateTime receivedAt,
) {
  final tokens = RegExp(r'd{1,2}|M{1,2}|y{4}|y{2}|[/.-]')
      .allMatches(policy.format)
      .map((m) => m.group(0)!)
      .toList();
  final parts = RegExp(r'[0-9]+|[/.-]').allMatches(foldKey(raw)).toList();
  if (parts.length != tokens.length) {
    return null;
  }
  int? day;
  int? month;
  int? year;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    final text = parts[i].group(0)!;
    if ('/.-'.contains(token)) {
      if (text != token) {
        return null;
      }
      continue;
    }
    final value = int.tryParse(text);
    if (value == null) {
      return null;
    }
    switch (token[0]) {
      case 'd':
        day = value;
      case 'M':
        month = value;
      case 'y':
        year = token.length == 2 ? 2000 + value : value;
    }
  }
  if (day == null || month == null) {
    return null;
  }
  DateTime? build(int y) {
    final d = DateTime.utc(y, month!, day!);
    return d.year == y && d.month == month && d.day == day ? d : null;
  }

  if (year != null) {
    return build(year);
  }
  if (!policy.nearestPast) {
    return build(receivedAt.year);
  }
  final today = DateTime.utc(receivedAt.year, receivedAt.month, receivedAt.day);
  final thisYear = build(receivedAt.year);
  if (thisYear != null && !thisYear.isAfter(today)) {
    return thisYear;
  }
  // Feb 29 may exist only in an earlier year: look back up to 4 years.
  for (var back = 1; back <= 4; back++) {
    final d = build(receivedAt.year - back);
    if (d != null) {
      return d;
    }
  }
  return null;
}
