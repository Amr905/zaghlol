/// Public API of the `zaghlol_domain` package.
library;

export 'budget/civil_date.dart';
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
export 'recurring/recurring_rules.dart';
export 'transfers/offsets.dart';
export 'transfers/transfer_matching.dart';

/// Placeholder so the package has a stable, testable entry point.
/// Real content arrives in later tasks.
const String packageName = 'zaghlol_domain';
