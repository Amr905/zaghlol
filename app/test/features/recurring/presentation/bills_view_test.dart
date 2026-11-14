// T-102: the S-24 view model. Synthetic data.
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bills_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

void main() {
  viewTests();
  final egp = Currency.of('EGP');
  test('yearly and monthly equivalents per cadence, rounded half up', () {
    final m = Money(egp, 32000);
    expect(yearlyOf(m, 'monthly', null).minor, 384000);
    expect(yearlyOf(m, 'weekly', null).minor, 1664000);
    expect(monthlyOf(Money(egp, 120000), 'yearly', null).minor, 10000);
    expect(monthlyOf(Money(egp, 100), 'yearly', null).minor, 8);
    expect(yearlyOf(Money(egp, 100), 'custom_days', 365).minor, 100);
  });

  test('merchant key for hand-typed names', () {
    expect(billMerchantKey('Gym  Club!', 'ID-1'), 'gym club');
    expect(billMerchantKey('قسط الثلاجة', 'AB-12-cd'), 'bill ab12cd');
  });
}

RecurringItemRow row(
  String id,
  String kind,
  String status,
  int minor,
  String due, {
  String currency = 'EGP',
  String cadence = 'monthly',
  int paid = 0,
  int? total,
}) => RecurringItemRow(
  id: id,
  kind: kind,
  status: status,
  name: id,
  amountMinor: minor,
  currency: currency,
  cadence: cadence,
  nextDueDate: due,
  totalCount: total,
  paidCount: paid,
  reminderDays: 3,
  createdAt: 0,
);

void viewTests() {
  test('buildBillsView groups per currency and never mixes them', () {
    final today = CivilDate(2026, 11, 13);
    final d = buildBillsView([
      row('gym', 'subscription', 'active', 75000, '2026-11-20'),
      row('usd', 'subscription', 'active', 1000, '2026-11-25', currency: 'USD'),
      row(
        'late',
        'installment',
        'active',
        100000,
        '2026-11-10',
        paid: 2,
        total: 3,
      ),
      row('next', 'bill', 'active', 5000, '2026-12-20'),
      row('sug', 'subscription', 'suggested', 32000, '2026-11-28'),
      row('done', 'installment', 'completed', 100, '2026-11-01'),
    ], today);
    expect(d.suggestions.single.id, 'sug');
    expect(d.upcoming.map((b) => b.id), ['late', 'gym', 'usd', 'next']);
    expect(d.upcoming.first.timing, BillTiming.overdue);
    expect(d.upcoming.first.daysUntil, -3);
    expect(d.upcoming.first.isLast, isTrue);
    expect(d.dueThisMonth.map((m) => (m.currency.code, m.minor)).toSet(), {
      ('EGP', 175000),
      ('USD', 1000),
    });
    expect(d.subTotals, hasLength(2));
    expect(d.subTotals.first.yearly.minor, 900000);
  });
}
