// T-052 (FR-CARD-01): the global Home card filter. An empty set means all
// cards. It lives in a provider that is never auto-disposed, so it persists
// while the user navigates; it is in-memory and resets on process restart.

import 'package:flutter_riverpod/flutter_riverpod.dart';

final cardFilterProvider = NotifierProvider<CardFilterNotifier, Set<String>>(
  CardFilterNotifier.new,
  name: 'cardFilterProvider',
);

class CardFilterNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Single-select: exactly [accountId].
  void selectOnly(String accountId) => state = Set.unmodifiable({accountId});

  /// Multi-select: add or remove [accountId].
  void toggle(String accountId) {
    final next = {...state};
    if (!next.remove(accountId)) next.add(accountId);
    state = Set.unmodifiable(next);
  }

  void setAll(Iterable<String> accountIds) =>
      state = Set.unmodifiable(accountIds);

  /// Back to all cards.
  void clear() => state = const {};
}
