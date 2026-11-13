// T-024: the go_router shell. Four tab branches (each keeps its own stack
// and state), the Add sheet as a modal route, deep links via [resolveDeepLink].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/z_tokens.dart';
import '../ui/shell/add_sheet.dart';
import '../ui/shell/app_shell.dart';
import 'app_routes.dart';
import 'deep_links.dart';

/// Root screens of the four tabs and pushed screens the shell owns. Feature
/// tasks (T-054, T-055, T-079, T-082, T-101) override [tabRootsProvider] or
/// replace these defaults; the shell itself never builds tab content.
class TabRoots {
  const TabRoots({
    this.home = _blank,
    this.insights = _blank,
    this.money = _blank,
    this.zaghlol = _blank,
    this.review = _reviewPlaceholder,
    this.transactions = _blank,
    this.addSelected = _closeAdd,
  });

  final WidgetBuilder home;
  final WidgetBuilder insights;
  final WidgetBuilder money;

  /// Called when an entry of the Quick add sheet is chosen; the composition
  /// root routes `type` to S-13 (`quickAddSelected`, T-080).
  final void Function(BuildContext context, AddAction action) addSelected;
  final WidgetBuilder zaghlol;

  /// S-14 Review queue.
  final WidgetBuilder review;

  /// S-11 Transactions list (T-079 supplies `TransactionsListScreen`).
  final WidgetBuilder transactions;
}

Widget _blank(BuildContext context) =>
    ColoredBox(color: ZColors.of(context).bg, child: const SizedBox.expand());

Widget _reviewPlaceholder(BuildContext context) => Scaffold(
  appBar: AppBar(
    title: Text(AppLocalizations.of(context).ingestionReviewTitle),
  ),
  body: const SizedBox.expand(),
);

final tabRootsProvider = Provider<TabRoots>(
  (ref) => const TabRoots(),
  name: 'tabRootsProvider',
);

void _closeAdd(BuildContext context, AddAction action) =>
    Navigator.of(context).maybePop();

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

GoRouter buildAppRouter(TabRoots roots, {String initialLocation = '/home'}) {
  Page<void> addPage(BuildContext context, GoRouterState state) =>
      ModalSheetPage<void>(
        key: state.pageKey,
        child: AddSheet(onSelected: (a) => roots.addSelected(context, a)),
      );

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    // N-01..N-02: deep links arrive as full URIs; map them to locations.
    redirect: (context, state) => resolveDeepLink(state.uri),
    routes: [
      GoRoute(
        path: AppRoutes.add,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: addPage,
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                pageBuilder: (c, s) =>
                    NoTransitionPage(key: s.pageKey, child: roots.home(c)),
                routes: [
                  GoRoute(path: 'review', builder: (c, s) => roots.review(c)),
                  GoRoute(
                    path: 'transactions',
                    builder: (c, s) => roots.transactions(c),
                  ),
                  GoRoute(
                    path: 'add',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: addPage,
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.insights,
                pageBuilder: (c, s) =>
                    NoTransitionPage(key: s.pageKey, child: roots.insights(c)),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.money,
                pageBuilder: (c, s) =>
                    NoTransitionPage(key: s.pageKey, child: roots.money(c)),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.zaghlol,
                pageBuilder: (c, s) =>
                    NoTransitionPage(key: s.pageKey, child: roots.zaghlol(c)),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = buildAppRouter(ref.watch(tabRootsProvider));
  ref.onDispose(router.dispose);
  return router;
}, name: 'appRouterProvider');
