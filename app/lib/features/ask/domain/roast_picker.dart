// T-110: picks the roast fact (FR-CHAT-04). Pure and deterministic: the same
// facts and seed give the same pick, so tests and the screen agree. It
// prefers a kind the user has not just seen. The facts are numbers and
// names from the user's own spending; the jokes are ARB templates that only
// tease the spending (A-18), so nothing here can produce an insult.

import 'ask_models.dart';

/// Picks one of [facts] (never empty: the caller always includes
/// [RoastKind.calm] as the last resort). [seed] varies the pick between
/// requests; [recent] are kinds shown lately and are skipped while another
/// fact is available.
RoastFact pickRoastFact(
  List<RoastFact> facts,
  int seed, {
  Set<RoastKind> recent = const {},
}) {
  if (facts.isEmpty) return const RoastFact(RoastKind.calm);
  final ordered = [...facts]..sort((a, b) => a.kind.index - b.kind.index);
  // `calm` is the last resort: only used when it is all there is, or when
  // everything else was just shown.
  final real = [
    for (final f in ordered)
      if (f.kind != RoastKind.calm) f,
  ];
  final fresh = [
    for (final f in real)
      if (!recent.contains(f.kind)) f,
  ];
  final pool = fresh.isNotEmpty ? fresh : (real.isNotEmpty ? real : ordered);
  return pool[seed.abs() % pool.length];
}
