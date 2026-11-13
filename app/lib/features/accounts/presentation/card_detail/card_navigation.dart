// T-084: entry points the shell wires to the Money tab (T-083):
// `onOpenAccount` -> [openCardDetail], `onCompare` -> [openCompareCards].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/application/card_filter.dart';
import '../../../transactions/presentation/list/txn_list_providers.dart';
import '../../domain/account.dart';
import 'card_detail.dart';
import 'compare.dart';

/// Opens S-41. [onOpenTransactions] shows S-11 (the card filter is set).
Future<void> openCardDetail(
  BuildContext context,
  Account account, {
  VoidCallback? onOpenTransactions,
  ValueChanged<String>? onOpenTransaction,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => CardDetailScreen(
      accountId: account.id,
      onSeeAll: onOpenTransactions,
      onOpenTransaction: onOpenTransaction,
    ),
  ),
);

/// Opens S-42. A cell sets the card and category filters and calls
/// [onOpenTransactions] (S-11).
Future<void> openCompareCards(
  BuildContext context, {
  VoidCallback? onOpenTransactions,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => _CompareHost(onOpenTransactions: onOpenTransactions),
  ),
);

class _CompareHost extends ConsumerStatefulWidget {
  const _CompareHost({this.onOpenTransactions});
  final VoidCallback? onOpenTransactions;

  @override
  ConsumerState<_CompareHost> createState() => _CompareHostState();
}

class _CompareHostState extends ConsumerState<_CompareHost> {
  // The list filter is auto-disposed; hold it while S-11 is on top.
  ProviderSubscription<Object?>? _keep;

  @override
  void dispose() {
    _keep?.close();
    super.dispose();
  }

  void _open(String accountId, String? categoryId) {
    _keep ??= ref.listenManual(txnListFilterProvider, (_, _) {});
    ref.read(cardFilterProvider.notifier).selectOnly(accountId);
    final f = ref.read(txnListFilterProvider);
    ref
        .read(txnListFilterProvider.notifier)
        .set(
          f.copyWith(
            period: TxnPeriod.thisCycle,
            categoryIds: categoryId == null ? const {} : {categoryId},
          ),
        );
    widget.onOpenTransactions?.call();
  }

  @override
  Widget build(BuildContext context) => CompareCardsScreen(onOpenCell: _open);
}
