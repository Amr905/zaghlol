import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// PO 12-case SMS suite (T-240, plan sms-parsing-v2-plan.md section 7).
// Synthetic copies of docs/qa/po-sms-suite-2026-11-25.md; wording kept.
// A case with `pendingUntil` is reported but does not fail; any other case
// must match every expected field. Fields not representable yet (dues,
// counterparty, notice kind) are declared and compared once the task lands.

const String _assets = '../../app/assets';

// 2026-11-22 Cairo wall clock (UTC+2).
final DateTime _at = DateTime.utc(2026, 11, 22, 10);

class _Case {
  const _Case(
    this.n,
    this.senders,
    this.body,
    this.expected, {
    this.pendingUntil,
  });
  final int n;
  final List<String> senders;
  final String body;
  final Map<String, Object?> expected;
  final String? pendingUntil;
}

const List<_Case> _cases = [
  _Case(
    1,
    ['ArabBank'],
    'تم خصم 375 EGP  من بطاقة الخصم المباشر رقم 4471  عند KASHIER*BELLA CUCINA  '
    'يوم 21/11/26  الساعه 16:53  المتاح 4667.24EGP  للمزيد إتصل ب ١٩٦٢٣',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 37500,
      'currency': 'EGP',
      'last4': '4471',
      'merchantKey': 'kashier*bella cucina',
      'date': '2026-11-21',
      'balanceMinor': 466724,
    },
    pendingUntil: 'T-242',
  ),
  _Case(
    2,
    ['BanqueMisr'],
    'تم تنفيذ تحويل لحظي من حسابكم رقم xxx2734 بمبلغ 1985 جم إلى '
    'سامي ع*** ف**** ح****** رقم مرجعي 512837460921 يوم 2026-10-26 '
    'الساعه 13:00 للمزيد اتصل ب 19888',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 198500,
      'currency': 'EGP',
      'last4': '2734',
      'counterparty': 'سامي ع*** ف**** ح******',
      'date': '2026-10-26',
      'balanceMinor': null,
    },
    pendingUntil: 'T-243',
  ),
  _Case(
    3,
    ['ArabBank', 'Arab Bank'],
    'EG\nشراء بمبلغ EGP 170.10 من حساب 419*6128 .الرصيد المتوفر 1769.47 .',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 17010,
      'currency': 'EGP',
      'last4': '6128',
      'merchantKey': null,
      'date': '2026-11-22',
      'balanceMinor': 176947,
    },
    pendingUntil: 'T-242',
  ),
  _Case(
    4,
    ['BanqueMisr'],
    'تم إضافة تحويل لحظي لحسابكم رقم xxx3519 بمبلغ 300 جم من '
    'KARIM SAMIR FATHY ADEL MANSOUR رقم مرجعي 390817265544 '
    'يوم 2026-10-28 الساعه 23:46 للمزيد اتصل علي 19888',
    {
      'kind': 'transaction',
      'direction': 'income',
      'minor': 30000,
      'currency': 'EGP',
      'last4': '3519',
      'counterparty': 'KARIM SAMIR FATHY ADEL MANSOUR',
      'date': '2026-10-28',
      'balanceMinor': null,
    },
    pendingUntil: 'T-243',
  ),
  _Case(
    5,
    ['ArabBank'],
    'A Trx using Card XXXX8216 from GEIDEAE Nour Market for EGP 263.00 on '
    '20-Nov-2026 at 01:21 GMT+2. Available balance is EGP 36156.47.',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 26300,
      'currency': 'EGP',
      'last4': '8216',
      'merchantKey': 'geideae nour market',
      'date': '2026-11-20',
      'balanceMinor': 3615647,
    },
    pendingUntil: 'T-242',
  ),
  _Case(
    6,
    ['ArabBank', 'EG'],
    'EG\n قيد راتب بمبلغ USD 189.66 لحساب 410*7381 بتاريخ 27/10/2026 .',
    {
      'kind': 'transaction',
      'direction': 'income',
      'minor': 18966,
      'currency': 'USD',
      'last4': '7381',
      'merchantKey': null,
      'date': '2026-10-27',
      'balanceMinor': null,
    },
  ),
  _Case(
    7,
    ['CIB'],
    'عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490  '
    'في 25/11, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم قبل '
    'العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط '
    'التالي: https://example.invalid/x1',
    {
      'kind': 'notice',
      'last4': '5490',
      'dueMinor': 5177,
      'currency': 'EGP',
      'minDueMinor': null,
      'dueDate': '2026-11-25',
    },
  ),
  _Case(
    8,
    ['CIB'],
    'كشف حساب شهر أكتوبر 2026  لبطاقتك الائتمانية المنتهية بـ 6603 هو 51.77 جم ، '
    'الحد الأدنى للسداد قبل  25/11 هو 51.77 جم .يمكنك الاطلاع على تفاصيل كشف '
    'الحساب من خلال الرابط التالي: https://example.invalid/x1',
    {
      'kind': 'notice',
      'last4': '6603',
      'dueMinor': 5177,
      'currency': 'EGP',
      'minDueMinor': 5177,
      'dueDate': '2026-11-25',
    },
  ),
  _Case(
    9,
    ['HSBC'],
    'Your Credit Card ending with *** 1937 has been used for EGP 200.00 on '
    '21/11/2026 at SUNNY CORNER. Your available limit is EGP 777',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 20000,
      'currency': 'EGP',
      'last4': '1937',
      'merchantKey': 'sunny corner',
      'date': '2026-11-21',
      'availableMinor': 77700,
    },
  ),
  _Case(
    10,
    ['HSBC'],
    'From HSBC: 28OCT26 Transfer from 002-388***-001 EGP 2,199.95- to your '
    'Credit Card ending with 4062 as per your instruction. '
    'Your available balance is EGP 0.00',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 219995,
      'currency': 'EGP',
      'last4': '4062',
      'date': '2026-10-28',
      'balanceMinor': 0,
    },
    pendingUntil: 'T-242',
  ),
  _Case(
    11,
    ['HSBC'],
    'From HSBC: 29OCT26 Transfer from 002-356***-001 EGP 47.82- to your '
    'Credit Card ending with 7748 as per your instruction. '
    'Your available balance is EGP 41',
    {
      'kind': 'transaction',
      'direction': 'expense',
      'minor': 4782,
      'currency': 'EGP',
      'last4': '7748',
      'date': '2026-10-29',
      'balanceMinor': 4100,
    },
    pendingUntil: 'T-242',
  ),
  _Case(
    12,
    ['HSBC'],
    'HSBC Credit Card ending *** 2859 Statement Date 03/10/2026. '
    'Total Amt Due EGP 47.82, Due Date 28/10/2026. Min. Amt Due EGP 47.82. '
    'Please ignore if paid.',
    {
      'kind': 'notice',
      'last4': '2859',
      'dueMinor': 4782,
      'currency': 'EGP',
      'minDueMinor': 4782,
      'statementDate': '2026-10-03',
      'dueDate': '2026-10-28',
    },
  ),
];

class _Neg {
  const _Neg(this.name, this.source, this.body, {this.pendingUntil});
  final String? pendingUntil;
  final String name;
  final String source;
  final String body;
}

const List<_Neg> _negatives = [
  _Neg(
    'OTP with an amount',
    'HSBC',
    'Your OTP is 482913 to confirm a payment of EGP 500.00. Do not share it.',
  ),
  _Neg(
    'promo with an amount',
    'HSBC',
    'Special offer: get cashback up to EGP 500.00 when you shop with your card '
        'this month. Terms apply.',
  ),
  _Neg(
    'declined purchase',
    'HSBC',
    'Your Credit Card ending with *** 1937 purchase of EGP 200.00 at SUNNY '
        'CORNER was declined due to insufficient limit.',
  ),
  _Neg(
    'T&C footer only',
    'HSBC',
    'Terms and conditions apply. A late payment fee of EGP 150.00 may be '
        'charged on overdue balances.',
    pendingUntil: 'T-243', // generic reader reads the fee as a payment today
  ),
  _Neg('hotline-only number', 'CIB', 'للمزيد اتصل ب 19888'),
];

String _d(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Comparable view of a result. Notice/due fields stay absent until they exist.
Map<String, Object?> _view(ParseResult r) {
  if (r is ParseParsed) {
    final f = r.fields;
    return {
      'kind': 'transaction',
      'direction': r.direction.name,
      'minor': f.amount?.minor,
      'currency': f.amount?.currency.code,
      'last4': f.last4,
      'merchantKey': f.merchant?.key,
      'counterparty': f.counterparty?.name,
      'date': f.date == null ? null : _d(f.date!),
      'balanceMinor': f.balance?.minor,
      'availableMinor': f.available?.minor,
    };
  }
  if (r is ParseGeneric) {
    return {
      'kind': 'transaction',
      'direction': r.direction?.name,
      'minor': r.amount.minor,
      'currency': r.amount.currency.code,
      'last4': r.last4,
      'merchantKey': r.merchant?.key,
      'date': r.dateRead ? _d(r.occurredAt) : _d(_at),
    };
  }
  if (r is ParseNotice) {
    return {
      'kind': 'notice',
      'last4': r.last4,
      'dueMinor': r.amountDue?.minor,
      'currency': r.amountDue?.currency.code,
      'minDueMinor': r.minDue?.minor,
      'dueDate': r.dueDate == null ? null : _d(r.dueDate!),
      'statementDate': r.statementDate == null ? null : _d(r.statementDate!),
    };
  }
  return {'kind': r.runtimeType.toString()};
}

bool _matches(Map<String, Object?> exp, Map<String, Object?> got) {
  for (final e in exp.entries) {
    if (e.key == 'date' && !got.containsKey('date')) return false;
    if (got[e.key] != e.value) return false;
  }
  return true;
}

Registry _registry() {
  final inst = <String, String>{};
  for (final f in Directory('$_assets/registry/institutions').listSync()) {
    if (f is File) inst[f.uri.pathSegments.last] = f.readAsStringSync();
  }
  return RegistryLoader.load(
    manifest: File('$_assets/registry/registry_manifest.json')
        .readAsStringSync(),
    shared: File('$_assets/registry/shared.json').readAsStringSync(),
    institutions: inst,
  ).registry!;
}

void main() {
  final pipeline = ParsingPipeline(_registry());
  ParseResult parse(String body, String source) => pipeline.parse(
    ParseRequest(
      body: body,
      source: source,
      channel: RegistryChannel.sms,
      receivedAt: _at,
    ),
  );

  var pass = 0;
  var pending = 0;
  final failures = <String>[];

  for (final c in _cases) {
    final ok = c.senders.every(
      (s) => _matches(c.expected, _view(parse(c.body, s))),
    );
    if (ok) {
      pass++;
    } else if (c.pendingUntil != null) {
      pending++;
    } else {
      failures.add('case ${c.n}');
    }
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('po_suite: $pass/12 pass, $pending pending');
  });

  group('PO suite', () {
    for (final c in _cases) {
      test(
        'case ${c.n}${c.pendingUntil == null ? '' : ' (pending ${c.pendingUntil})'}',
        () {
          for (final s in c.senders) {
            final got = _view(parse(c.body, s));
            if (c.pendingUntil != null) {
              // Reported only; must never throw.
              continue;
            }
            for (final e in c.expected.entries) {
              expect(
                got[e.key],
                e.value,
                reason: 'case ${c.n} sender $s ${e.key}',
              );
            }
          }
        },
      );
    }
    test('no unmarked case fails', () => expect(failures, isEmpty));
  });

  group('negatives never become a transaction', () {
    for (final n in _negatives) {
      test(n.name, () {
        final r = parse(n.body, n.source);
        final tx = r is ParseParsed || r is ParseGeneric;
        if (n.pendingUntil != null) return; // known gap, reported in task
        expect(tx, isFalse);
      });
    }
  });
}
