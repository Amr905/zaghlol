/// Public API of the `zaghlol_domain` package.
library;

export 'ask/invest_bands.dart';
export 'ask/invest_illustrations.dart';
export 'ask/savings_suggest.dart';
export 'ask/what_if.dart';
export 'budget/cash_pool.dart';
export 'budget/civil_date.dart';
export 'budget/cycle_label.dart';
export 'budget/cycle_totals.dart';
export 'budget/payday_schedule.dart';
export 'budget/safe_to_spend.dart';
export 'core/domain_event.dart';
export 'core/domain_event_bus.dart';
export 'core/failure.dart';
export 'core/result.dart';
export 'core/safe_exception.dart';
export 'money/currency.dart';
export 'money/money.dart';
export 'money/money_errors.dart';
export 'money/multi_currency_total.dart';
export 'money/rounding.dart';
export 'money/src/allocation.dart' show maxAllocationParts;
export 'mascot_rules/mascot_rules.dart';
export 'recurring/recurring_rules.dart';
export 'roi/roi_assumptions.dart';
export 'salary/payday_detection.dart';
export 'salary/salary_rules.dart';
export 'roi/roi_rules.dart';
export 'transfers/offsets.dart';
export 'transfers/splits.dart';
export 'transfers/transfer_matching.dart';
export 'wealth/balance_rules.dart';
export 'wealth/net_worth.dart';
export 'wealth/opening_balances.dart';
export 'zakah/hijri.dart';
export 'zakah/zakah_engine.dart';

/// Placeholder so the package has a stable, testable entry point.
/// Real content arrives in later tasks.
const String packageName = 'zaghlol_domain';
