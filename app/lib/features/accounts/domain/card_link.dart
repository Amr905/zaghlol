// T-266: the pure rules of linking a debit card to its bank account (design
// note in docs/04-tasks/tasks/T-266.md). Pure Dart; nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

import 'account.dart';

/// An account a card could be linked to, with why it ranks where it does.
final class LinkTarget {
  const LinkTarget(
    this.account, {
    required this.sameBank,
    this.sameBalance = false,
  });

  final Account account;

  /// Same institution as the card.
  final bool sameBank;

  /// The account's latest reported balance equals the card's (same
  /// currency): the messages show the same balance sequence.
  final bool sameBalance;

  /// Worth asking "Is this card on your (bank) account?" about.
  bool get isSuggestion => sameBank;
}

/// The latest reported balance of an account in one currency.
typedef ReportedFigure = ({Money amount, DateTime asOf});

/// Orders the accounts [card] could be linked to. Only a debit card has
/// targets; a target is a live account that can hold cards (account, wallet,
/// multi-currency), not the card itself and not hidden. Same bank and same
/// balance first, then same bank, then the rest; ties keep [accounts]' order.
/// [reported] gives each account's latest reported balances by currency code
/// (an absent entry is "none").
List<LinkTarget> orderLinkTargets({
  required Account card,
  required List<Account> accounts,
  Map<String, Map<String, ReportedFigure>> reported = const {},
}) {
  if (!card.kind.canBeLinked || card.isMerged) return const [];
  final mine = reported[card.id] ?? const {};
  final out = <LinkTarget>[];
  for (final a in accounts) {
    if (a.id == card.id || a.isMerged || a.isHidden || !a.kind.canHoldCards) {
      continue;
    }
    final sameBank =
        card.institutionCode != null &&
        a.institutionCode == card.institutionCode;
    var sameBalance = false;
    final theirs = reported[a.id] ?? const {};
    for (final e in mine.entries) {
      final t = theirs[e.key];
      if (t != null && t.amount == e.value.amount) sameBalance = true;
    }
    out.add(
      LinkTarget(a, sameBank: sameBank, sameBalance: sameBank && sameBalance),
    );
  }
  int rank(LinkTarget t) => t.sameBalance ? 0 : (t.sameBank ? 1 : 2);
  final indexed = [for (var i = 0; i < out.length; i++) (i, out[i])]
    ..sort((x, y) {
      final r = rank(x.$2).compareTo(rank(y.$2));
      return r != 0 ? r : x.$1.compareTo(y.$1);
    });
  return [for (final (_, t) in indexed) t];
}
