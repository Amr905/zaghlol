// T-272 (D-86, PO 2026-11-26): an exchange made at the bank counter sends no
// SMS. The next balance message then shows more money than the ledger
// explains. This rule says when that rise is worth one gentle question
// ("Did you exchange money?"). Pure Dart; integer minor units; nothing is
// converted and nothing here creates a transaction.

import '../money/currency.dart';
import '../money/money.dart';

/// A rise smaller than this many major units of the account's currency is
/// not asked about (fees, interest, rounding, a missed small credit).
const int balanceJumpMinMajor = 500;

/// How far back another currency's income must be for the question to make
/// sense ("you hold another currency with a recent salary or credit").
const Duration balanceJumpForeignCreditLookback = Duration(days: 45);

/// The smallest rise asked about, in [currency]'s minor units.
int balanceJumpMinMinor(Currency currency) {
  var m = balanceJumpMinMajor;
  for (var i = 0; i < currency.exponent; i++) {
    m *= 10;
  }
  return m;
}

/// The unexplained rise of a reported balance, or null when there is none
/// worth asking about.
///
/// [previous]: the last reported balance; [countedEffectMinor]: the signed
/// cash effect of the counted transactions after it, up to the new report
/// (same currency); [reported]: the new balance. Different currencies, or a
/// rise below [balanceJumpMinMinor], give null.
Money? unexplainedBalanceRise({
  required Money previous,
  required int countedEffectMinor,
  required Money reported,
}) {
  if (previous.currency != reported.currency) return null;
  final expected =
      BigInt.from(previous.minor) + BigInt.from(countedEffectMinor);
  final rise = BigInt.from(reported.minor) - expected;
  if (rise < BigInt.from(balanceJumpMinMinor(reported.currency)) ||
      rise > BigInt.from(Money.maxMinor)) {
    return null;
  }
  return Money(reported.currency, rise.toInt());
}
