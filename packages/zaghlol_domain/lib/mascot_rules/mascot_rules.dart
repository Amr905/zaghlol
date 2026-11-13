/// Mascot trigger policy (T-098, BR-MAS-01/02/03). Pure Dart, integer money.
///
/// Facts in, at most one banner out. Priority: shocked > detective > proud >
/// tourGuide. Message ids are `kind:subject:cycle`; each fires once per cycle
/// and never again after the user dismissed it. Essential categories (Q-25)
/// are never roasted: they produce no shocked banner.
library;

enum MascotPose { shocked, detective, proud, tourGuide }

/// Lower index = higher priority.
const List<MascotPose> mascotPriority = [
  MascotPose.shocked,
  MascotPose.detective,
  MascotPose.proud,
  MascotPose.tourGuide,
];

/// One candidate banner. [id] is stable per (kind, subject, cycle).
final class MascotCandidate {
  const MascotCandidate({required this.id, required this.pose, this.subject});
  final String id;
  final MascotPose pose;

  /// Category / merchant id the copy may name; null when none.
  final String? subject;
}

/// Seed set from Q-25 (category ids); callers may pass their own.
const Set<String> defaultEssentialCategoryIds = {
  'rent',
  'bills',
  'groceries',
  'health',
  'education',
  'fees',
  'debt',
  'work_transport',
};

/// BR-MAS-01: category passed 85% of its limit before day 20 of the cycle.
/// [dayOfCycle] is 1-based. Essential categories are never roasted.
MascotCandidate? budgetShocked({
  required String categoryId,
  required int spentMinor,
  required int limitMinor,
  required int dayOfCycle,
  required String cycleId,
  Set<String> essentialCategoryIds = defaultEssentialCategoryIds,
}) {
  if (essentialCategoryIds.contains(categoryId)) return null;
  if (limitMinor <= 0 || spentMinor <= 0) return null;
  if (dayOfCycle >= 20) return null;
  if (spentMinor * 100 <= limitMinor * 85) return null;
  return MascotCandidate(
    id: 'shocked:budget:$categoryId:$cycleId',
    pose: MascotPose.shocked,
    subject: categoryId,
  );
}

/// BR-MAS-01 (second clause): dining/delivery spend more than 30% above the
/// 3-cycle average. All amounts are minor units of one currency.
MascotCandidate? diningSpike({
  required String categoryId,
  required int spentMinor,
  required List<int> previousCyclesMinor,
  required String cycleId,
  Set<String> essentialCategoryIds = defaultEssentialCategoryIds,
}) {
  if (essentialCategoryIds.contains(categoryId)) return null;
  if (previousCyclesMinor.length < 3) return null;
  final last3 = previousCyclesMinor.sublist(previousCyclesMinor.length - 3);
  final sum = last3.fold<int>(0, (a, b) => a + b);
  if (sum <= 0 || spentMinor <= 0) return null;
  // spent > avg * 1.3  <=>  spent * 3 * 10 > sum * 13
  if (spentMinor * 30 <= sum * 13) return null;
  return MascotCandidate(
    id: 'shocked:spike:$categoryId:$cycleId',
    pose: MascotPose.shocked,
    subject: categoryId,
  );
}

/// A POS debit used for duplicate detection (A-34).
final class PosDebit {
  const PosDebit({
    required this.merchantId,
    required this.cardId,
    required this.currency,
    required this.amountMinor,
    required this.atUtcMs,
  });
  final String merchantId;
  final String cardId;
  final String currency;
  final int amountMinor;
  final int atUtcMs;
}

/// BR-MAS-03: same merchant, amount, currency and card within 10 minutes of
/// an earlier debit. Returns the candidate for [latest], or null.
MascotCandidate? duplicatePos(PosDebit latest, Iterable<PosDebit> earlier) {
  const windowMs = 10 * 60 * 1000;
  for (final e in earlier) {
    final gap = latest.atUtcMs - e.atUtcMs;
    if (gap < 0 || gap > windowMs) continue;
    if (e.merchantId == latest.merchantId &&
        e.cardId == latest.cardId &&
        e.currency == latest.currency &&
        e.amountMinor == latest.amountMinor) {
      return MascotCandidate(
        id: 'detective:dup:${latest.merchantId}:${latest.atUtcMs}',
        pose: MascotPose.detective,
        subject: latest.merchantId,
      );
    }
  }
  return null;
}

/// BR-MAS-03: self-transfer paired (T-089 auto pairs).
MascotCandidate selfTransferPaired(String pairId) =>
    MascotCandidate(id: 'detective:pair:$pairId', pose: MascotPose.detective);

/// BR-MAS-03: subscription renewal detected / confirmed (T-096).
MascotCandidate subscriptionDetected(String subscriptionId, String cycleId) =>
    MascotCandidate(
      id: 'detective:sub:$subscriptionId:$cycleId',
      pose: MascotPose.detective,
      subject: subscriptionId,
    );

/// BR-MAS-02: under the ideal burn line, or a monthly goal met.
MascotCandidate? proud({
  required String cycleId,
  required int spentMinor,
  required int idealBurnMinor,
  String? metGoalId,
}) {
  if (metGoalId != null) {
    return MascotCandidate(
      id: 'proud:goal:$metGoalId:$cycleId',
      pose: MascotPose.proud,
    );
  }
  if (spentMinor >= 0 && idealBurnMinor > 0 && spentMinor < idealBurnMinor) {
    return MascotCandidate(id: 'proud:burn:$cycleId', pose: MascotPose.proud);
  }
  return null;
}

/// FR-MAS-01 hello: first launch, setup and empty states.
const MascotCandidate tourGuideHello = MascotCandidate(
  id: 'tourGuide:hello',
  pose: MascotPose.tourGuide,
);

/// Memory the policy needs. Persist [shownIds] per cycle and [dismissedIds]
/// for good; the policy itself holds no state.
final class MascotMemory {
  const MascotMemory({
    this.shownIds = const {},
    this.dismissedIds = const {},
    this.lastShownUtcMs,
  });
  final Set<String> shownIds;
  final Set<String> dismissedIds;
  final int? lastShownUtcMs;
}

/// The single banner to show now.
final class MascotDecision {
  const MascotDecision(this.candidate, {required this.stillOnly});
  final MascotCandidate candidate;

  /// Reduce motion: still pose plus its line, no animation or confetti.
  final bool stillOnly;
}

/// Minimum gap between two banners.
const int mascotMinGapMs = 60 * 1000;

/// Picks at most one banner. Skips already-shown or dismissed ids, honours
/// the rate limit, then takes the highest priority pose (ties: input order).
MascotDecision? decideMascot({
  required Iterable<MascotCandidate> candidates,
  required MascotMemory memory,
  required int nowUtcMs,
  required bool reduceMotion,
}) {
  final last = memory.lastShownUtcMs;
  if (last != null && nowUtcMs - last < mascotMinGapMs) return null;
  MascotCandidate? best;
  for (final c in candidates) {
    if (memory.shownIds.contains(c.id) || memory.dismissedIds.contains(c.id)) {
      continue;
    }
    if (best == null ||
        mascotPriority.indexOf(c.pose) < mascotPriority.indexOf(best.pose)) {
      best = c;
    }
  }
  return best == null ? null : MascotDecision(best, stillOnly: reduceMotion);
}
