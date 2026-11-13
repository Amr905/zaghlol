// T-089: pure matching rules for own-account movements (domain-algorithms
// §4, BR-XFR-01/02, FR-CUR-06). No Flutter, no database. The app layer reads
// the unpaired legs, asks these functions what to do and writes the result in
// one transaction.
//
// Money rules: amounts are integer minor units; same-currency pairs need the
// exact same amount; a cross-currency conversion uses integer arithmetic only
// (BigInt, rate as an integer of 1e-9 units) and is a suggestion, never an
// automatic pair.

import '../money/currency.dart';
import '../money/money.dart';

/// Window inside which two opposite legs are one transfer (domain §4).
const Duration transferPairWindow = Duration(minutes: 5);

/// Window for a cross-currency suggestion (FR-CUR-06, A-61).
const Duration crossCurrencyWindow = Duration(days: 3);

/// Cross-currency tolerance in basis points of the converted amount (3%).
const int crossCurrencyToleranceBp = 300;

/// A transfer leg that is not yet paired: the facts matching needs.
final class TransferLeg {
  const TransferLeg({
    required this.id,
    required this.accountId,
    required this.isOut,
    required this.amount,
    required this.occurredAt,
  });

  final String id;
  final String accountId;

  /// True for `transfer_out`, false for `transfer_in`.
  final bool isOut;

  /// Always the leg's absolute amount in its account's currency.
  final Money amount;

  /// UTC instant.
  final DateTime occurredAt;
}

/// What to do with a leg that was just stored.
sealed class SameCurrencyOutcome {
  const SameCurrencyOutcome();
}

/// Exactly one candidate, and the leg is that candidate's only candidate.
final class PairWith extends SameCurrencyOutcome {
  const PairWith(this.counterpart);
  final TransferLeg counterpart;
}

/// More than one possible match on either side (EC-16): never auto-pair.
final class AmbiguousMatch extends SameCurrencyOutcome {
  const AmbiguousMatch(this.candidateIds);

  /// Ids of the legs that could match, sorted.
  final List<String> candidateIds;
}

/// No match yet; wait for a late message.
final class NoMatch extends SameCurrencyOutcome {
  const NoMatch();
}

bool _within(TransferLeg a, TransferLeg b, Duration window) =>
    a.occurredAt.difference(b.occurredAt).abs() <= window;

int _byId(TransferLeg a, TransferLeg b) => a.id.compareTo(b.id);

/// Legs in [pool] that could be the other half of [leg]: opposite direction,
/// same currency, same non-zero amount, another account, within
/// [transferPairWindow]. Sorted by id so results never depend on read order.
List<TransferLeg> sameCurrencyCandidates(
  TransferLeg leg,
  Iterable<TransferLeg> pool,
) {
  if (leg.amount.minor <= 0) return const [];
  return [
    for (final c in pool)
      if (c.id != leg.id &&
          c.isOut != leg.isOut &&
          c.accountId != leg.accountId &&
          c.amount == leg.amount &&
          _within(leg, c, transferPairWindow))
        c,
  ]..sort(_byId);
}

/// Decides the pairing of [leg] against the unpaired legs in [pool] (which
/// may contain [leg]; it is ignored). One candidate pairs only when [leg] is
/// also that candidate's one and only candidate: otherwise two transfers
/// could be crossed (EC-16) and the money mis-attributed.
SameCurrencyOutcome decideSameCurrency(
  TransferLeg leg,
  Iterable<TransferLeg> pool,
) {
  final all = pool.toList();
  final candidates = sameCurrencyCandidates(leg, all);
  if (candidates.isEmpty) return const NoMatch();
  if (candidates.length > 1) {
    return AmbiguousMatch([for (final c in candidates) c.id]);
  }
  final other = candidates.single;
  final reverse = sameCurrencyCandidates(other, [...all, leg]);
  if (reverse.length != 1 || reverse.single.id != leg.id) {
    return AmbiguousMatch(
      ([other.id, ...reverse.map((c) => c.id)]..sort()).toSet().toList(),
    );
  }
  return PairWith(other);
}

/// Opposite legs of [leg] in the same account but another currency, within
/// [transferPairWindow]: the two halves of one conversion (fx_conversion).
/// The caller passes only legs of a multi-currency account.
List<TransferLeg> fxConversionCandidates(
  TransferLeg leg,
  Iterable<TransferLeg> pool,
) {
  if (leg.amount.minor <= 0) return const [];
  return [
    for (final c in pool)
      if (c.id != leg.id &&
          c.isOut != leg.isOut &&
          c.accountId == leg.accountId &&
          c.amount.currency != leg.amount.currency &&
          c.amount.minor > 0 &&
          _within(leg, c, transferPairWindow))
        c,
  ]..sort(_byId);
}

/// [amount] converted into [target] at [rateE9] (1 unit of the amount's
/// currency = rateE9 / 1e9 units of [target]), rounded half up to the
/// target's minor unit. Returns null when the result is not a valid [Money].
Money? convertWithRate(Money amount, Currency target, int rateE9) {
  if (rateE9 <= 0 || amount.minor < 0) return null;
  final numerator =
      BigInt.from(amount.minor) *
      BigInt.from(rateE9) *
      BigInt.from(10).pow(target.exponent);
  final denominator =
      BigInt.from(1000000000) * BigInt.from(10).pow(amount.currency.exponent);
  final rounded =
      (numerator * BigInt.two + denominator) ~/ (denominator * BigInt.two);
  if (rounded > BigInt.from(Money.maxMinor)) return null;
  return Money.tryMinor(target, rounded.toInt());
}

/// True when |[expected] − [actual]| ≤ [toleranceBp] / 10000 of [expected].
/// Different currencies are never within tolerance.
bool withinTolerance(Money expected, Money actual, int toleranceBp) {
  if (expected.currency != actual.currency || expected.minor <= 0) {
    return false;
  }
  final diff = (BigInt.from(expected.minor) - BigInt.from(actual.minor)).abs();
  return diff * BigInt.from(10000) <=
      BigInt.from(expected.minor) * BigInt.from(toleranceBp);
}

/// Opposite legs of [leg] in another currency and another account, within
/// [crossCurrencyWindow], whose amount matches [leg]'s converted at the rate
/// from [rateE9For] within [crossCurrencyToleranceBp]. A pair with no known
/// rate is not a candidate. Sorted by id. These are suggestions only.
List<TransferLeg> crossCurrencyCandidates(
  TransferLeg leg,
  Iterable<TransferLeg> pool,
  int? Function(Currency from, Currency to) rateE9For,
) {
  if (leg.amount.minor <= 0) return const [];
  final result = <TransferLeg>[];
  for (final c in pool) {
    if (c.id == leg.id ||
        c.isOut == leg.isOut ||
        c.accountId == leg.accountId ||
        c.amount.currency == leg.amount.currency ||
        c.amount.minor <= 0 ||
        !_within(leg, c, crossCurrencyWindow)) {
      continue;
    }
    final rate = rateE9For(leg.amount.currency, c.amount.currency);
    if (rate == null) continue;
    final expected = convertWithRate(leg.amount, c.amount.currency, rate);
    if (expected != null &&
        withinTolerance(expected, c.amount, crossCurrencyToleranceBp)) {
      result.add(c);
    }
  }
  return result..sort(_byId);
}
