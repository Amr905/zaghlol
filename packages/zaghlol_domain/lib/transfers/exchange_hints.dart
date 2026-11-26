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

/// An inbox-scan jump older than this is not asked about (FU-366): the
/// catch-up scan must not raise a pile of stale questions on first run.
const Duration balanceJumpMaxAge = Duration(days: 14);

/// Smallest threshold in any currency with no minor digits (JPY, KRW):
/// 100 units; with digits: one major unit. A very strong rate can never
/// push the question below this.
int balanceJumpFloorMinor(Currency currency) {
  if (currency.exponent == 0) return 100;
  return _pow10(currency.exponent);
}

int _pow10(int n) {
  var m = 1;
  for (var i = 0; i < n; i++) {
    m *= 10;
  }
  return m;
}

/// The smallest rise asked about, in [currency]'s minor units.
///
/// [egpPerUnitE9]: the last known rate, 1 [currency] = rate / 1e9 EGP
/// (display rate, used only to size this threshold; nothing is converted).
/// With a rate, the threshold is [balanceJumpMinMajor] EGP expressed in
/// [currency] (rounded up), never below [balanceJumpFloorMinor]. Without a
/// rate (or for EGP itself) it is [balanceJumpMinMajor] major units.
int balanceJumpMinMinor(Currency currency, {int? egpPerUnitE9}) {
  final plain = _pow10(currency.exponent) * balanceJumpMinMajor;
  if (currency.code == 'EGP' || egpPerUnitE9 == null || egpPerUnitE9 <= 0) {
    return plain;
  }
  // minor = 500 EGP / (rate/1e9) * 10^exp, rounded up.
  final num =
      BigInt.from(balanceJumpMinMajor) *
      BigInt.from(1000000000) *
      BigInt.from(_pow10(currency.exponent));
  final den = BigInt.from(egpPerUnitE9);
  final q = (num + den - BigInt.one) ~/ den;
  final floor = balanceJumpFloorMinor(currency);
  if (q > BigInt.from(Money.maxMinor)) return plain;
  final v = q.toInt();
  return v < floor ? floor : v;
}

/// The unexplained rise of a reported balance, or null when there is none
/// worth asking about.
///
/// [previous]: the last reported balance; [countedEffectMinor]: the signed
/// cash effect of the counted transactions after it, up to the new report
/// (same currency); [reported]: the new balance; [egpPerUnitE9]: see
/// [balanceJumpMinMinor]. Different currencies, or a rise below
/// [balanceJumpMinMinor], give null.
Money? unexplainedBalanceRise({
  required Money previous,
  required int countedEffectMinor,
  required Money reported,
  int? egpPerUnitE9,
}) {
  if (previous.currency != reported.currency) return null;
  final expected =
      BigInt.from(previous.minor) + BigInt.from(countedEffectMinor);
  final rise = BigInt.from(reported.minor) - expected;
  if (rise <
          BigInt.from(
            balanceJumpMinMinor(reported.currency, egpPerUnitE9: egpPerUnitE9),
          ) ||
      rise > BigInt.from(Money.maxMinor)) {
    return null;
  }
  return Money(reported.currency, rise.toInt());
}
