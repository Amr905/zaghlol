// Representative fake data for the Insights design shots (mockups 07-10).
import 'package:zaghlol/core/db/app_database.dart' show CategoryRow;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zaghlol/features/budget/presentation/budget_view.dart';
import 'package:zaghlol/features/insights/domain/chart_models.dart';
import 'package:zaghlol/features/insights/presentation/chart_explain_providers.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/features/recurring/presentation/bills_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../features/budget/presentation/budget_test_support.dart';

CategoryRow _cat(
  String id,
  String icon,
  String color,
  int sort, [
  String? ar,
]) => CategoryRow(
  id: id,
  nameAr: ar ?? id,
  nameEn: id,
  icon: icon,
  color: color,
  bucket: 'needs',
  isCustom: 0,
  isArchived: 0,
  sort: sort,
);

List<CategoryRow> categories() => [
  _cat('dining', 'food', '#8C3A5B', 1, 'أكل بره ودليفري'),
  _cat('transport', 'car', '#2F5D8C', 2, 'مواصلات'),
  _cat('groceries', 'cart', '#4D695C', 3, 'خزين البيت'),
  _cat('bills', 'bolt', '#6B6B2A', 4, 'إيجار وفواتير'),
  _cat('installments', 'work', '#5B3A8C', 5, 'أقساط وكريدت'),
];

CurrencyBudgetView budgetView() => CurrencyBudgetView(
  currency: egp,
  spent: egpM(19800),
  limit: egpM(22000),
  percent: 90,
  safePerDay: egpM(314),
  rows: [
    rowView('dining', 'Dining', 'أكل بره', 3850, 4000),
    rowView('transport', 'Transport', 'مواصلات', 2150, 2500),
    rowView('groceries', 'Groceries', 'خزين البيت', 5400, 7000),
    rowView('bills', 'Bills', 'فواتير', 4200, 4200),
  ],
  notBudgeted: egpM(0),
);

BillRowView _bill(
  String name,
  String kind,
  int amount,
  int day,
  int daysUntil, {
  int paid = 0,
  int? total,
}) => BillRowView(
  id: name,
  name: name,
  kind: kind,
  amount: egpM(amount),
  due: CivilDate(2026, 11, day),
  daysUntil: daysUntil,
  timing: BillTiming.upcoming,
  paidCount: paid,
  totalCount: total,
);

BillsViewData billsData() => BillsViewData(
  suggestions: [SuggestionView(id: 's', name: 'Netflix', amount: egpM(320))],
  upcoming: [
    _bill(
      'قسط فاليو · تريدلاين',
      RecurringKind.installment,
      1000,
      5,
      1,
      paid: 3,
      total: 6,
    ),
    _bill(
      'قسط سيمبل · زارا',
      RecurringKind.installment,
      450,
      13,
      9,
      paid: 5,
      total: 6,
    ),
    _bill('سداد كارت HSBC', RecurringKind.cardDue, 1450, 15, 11),
    _bill('الجمعية', RecurringKind.gameya, 2000, 30, 26, paid: 6, total: 10),
  ],
  subscriptions: const [],
  subTotals: [CurrencyTotal(monthly: egpM(1300), yearly: egpM(15600))],
  dueThisMonth: [egpM(2900)],
);

CategoryDonut donut() => CategoryDonut(
  total: egpM(19800),
  slices: [
    CategorySlice(
      categoryId: 'groceries',
      amount: egpM(5400),
      shareBp: 2700,
      count: 9,
    ),
    CategorySlice(
      categoryId: 'bills',
      amount: egpM(4200),
      shareBp: 2100,
      count: 4,
    ),
    CategorySlice(
      categoryId: 'dining',
      amount: egpM(3850),
      shareBp: 1900,
      count: 12,
    ),
    CategorySlice(
      categoryId: 'installments',
      amount: egpM(2900),
      shareBp: 1500,
      count: 3,
    ),
    CategorySlice(
      categoryId: 'transport',
      amount: egpM(2150),
      shareBp: 1100,
      count: 8,
    ),
  ],
);

Override previousDonutOverride() => previousDonutChartProvider.overrideWith(
  (ref, code) async => ChartReady(
    CategoryDonut(
      total: egpM(18000),
      slices: [
        CategorySlice(
          categoryId: 'dining',
          amount: egpM(3000),
          shareBp: 1700,
          count: 9,
        ),
        CategorySlice(
          categoryId: 'groceries',
          amount: egpM(5000),
          shareBp: 2800,
          count: 8,
        ),
      ],
    ),
  ),
);

List<CashFlowPoint> cashFlow() => [
  for (var m = 5; m <= 10; m++)
    CashFlowPoint(
      period: ChartPeriod.month(2026, m),
      income: egpM(32400 - (10 - m) * 150),
      spend: egpM(20100 - (10 - m) * 300),
      isPartial: false,
    ),
];
