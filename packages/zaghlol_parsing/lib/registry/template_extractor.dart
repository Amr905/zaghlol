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

/// Reads typed fields from [groups]. [receivedAt] carries the device-local
/// wall clock of receipt as a UTC-flagged `DateTime` (the zone is the
/// device's, EC-10); it is used for dates without a year.
ExtractedFields extractFields(
  Institution institution,
  Template template,
  Map<String, String> groups,
  DateTime receivedAt, {
  MerchantCleaningConfig cleaning = MerchantCleaningConfig.defaults,
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
    final result = parseAmount(
      _dropTrailingPunctuation(raw),
      currency: currency,
      locale: template.locale,
    );
    final value = result.valueOrNull;
    if (value == null || (key == 'amount' && !value.isPositive)) {
      problems.add(field);
      return null;
    }
    return value;
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
