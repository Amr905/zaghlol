// WIRE-NAV: the screens the composition opens, as functions. The defaults are
// the real screens; widget tests override [appScreensProvider] with markers so
// they can tap through the shell without building every screen's data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Cycle;

import '../features/accounts/domain/account.dart';
import '../features/accounts/presentation/card_detail/card_navigation.dart';
import '../features/accounts/presentation/edit_card/add_card_flow.dart';
import '../features/ask/presentation/ask_screen.dart';
import '../features/backup/presentation/backup_screen.dart';
import '../features/backup/presentation/restore_screen.dart';
import '../features/budget/presentation/budget_screen.dart';
import '../features/capture/presentation/capture_settings_screen.dart';
import '../features/capture/presentation/card_capture_sheet.dart';
import '../features/capture/presentation/template_builder_screen.dart';
import '../features/categorization/presentation/categories_rules_screen.dart';
import '../features/gold/presentation/paywall_screen.dart';
import '../features/ingestion/presentation/review/review_screen.dart';
import '../features/onboarding/presentation/android_setup.dart';
import '../features/onboarding/presentation/scan_results.dart';
import '../features/settings/presentation/privacy_screen.dart';
import '../features/settings/presentation/settings_main_screen.dart';
import '../features/transactions/presentation/detail/transaction_detail_screen.dart';
import '../features/transactions/presentation/list/transactions_list_screen.dart';
import '../features/wealth/presentation/add_asset_screen.dart';
import '../features/wealth/presentation/prices_screen.dart';

/// A screen opener: pushes [builder]'s screen on the nearest navigator.
Future<T?> pushScreen<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
}) => Navigator.of(context).push<T>(
  MaterialPageRoute<T>(builder: builder, fullscreenDialog: fullscreenDialog),
);

final class AppScreens {
  const AppScreens({
    this.cardDetail = _cardDetail,
    this.compareCards = _compareCards,
    this.startAddCard = _startAddCard,
    this.editCard = _editCard,
    this.cardCaptureSheet = _cardCaptureSheet,
    this.addAsset = _addAsset,
    this.prices = _prices,
    this.paywall = _paywall,
    this.settings = _settings,
    this.backup = _backup,
    this.restore = _restore,
    this.captureSettings = _captureSettings,
    this.templateBuilder = _templateBuilder,
    this.categories = _categories,
    this.privacy = _privacy,
    this.budget = _budget,
    this.ask = _ask,
    this.review = _review,
    this.transactions = _transactions,
    this.transactionDetail = _transactionDetail,
    this.androidSetup = _androidSetup,
    this.scanResults = _scanResults,
    this.scanResultsSheet = _scanResultsSheet,
  });

  final Future<void> Function(
    BuildContext context,
    Account account, {
    VoidCallback? onOpenTransactions,
    ValueChanged<String>? onOpenTransaction,
  })
  cardDetail;
  final Future<void> Function(
    BuildContext context, {
    VoidCallback? onOpenTransactions,
  })
  compareCards;
  final Future<void> Function(
    BuildContext context, {
    void Function(Account account)? onSaved,
    void Function(Account existing)? onOpenExisting,
  })
  startAddCard;
  final Future<void> Function(
    BuildContext context,
    Account account, {
    void Function(Account account)? onOpenCapture,
  })
  editCard;
  final Future<void> Function(BuildContext context, Account account)
  cardCaptureSheet;
  final Future<void> Function(BuildContext context) addAsset;
  final Future<void> Function(BuildContext context) prices;
  final Future<void> Function(BuildContext context) paywall;
  final Future<void> Function(BuildContext context, SettingsDestinations d)
  settings;
  final Future<void> Function(
    BuildContext context, {
    required VoidCallback onOpenRestore,
    required bool iCloud,
  })
  backup;
  final Future<void> Function(
    BuildContext context, {
    required void Function({required bool regrantDue}) onRestored,
    required VoidCallback onStartFresh,
    required VoidCallback onUpdateApp,
    required bool iCloud,
  })
  restore;
  final Future<void> Function(
    BuildContext context, {
    required bool goldActive,
    required VoidCallback onOpenTemplates,
  })
  captureSettings;
  final Future<void> Function(BuildContext context) templateBuilder;
  final Future<void> Function(BuildContext context) categories;
  final Future<void> Function(BuildContext context) privacy;
  final Future<void> Function(
    BuildContext context, {
    required void Function(String categoryId, Cycle cycle) onCategoryTap,
  })
  budget;

  /// Tab roots and pushed routes the router builds.
  final WidgetBuilder ask;
  final WidgetBuilder review;
  final Widget Function(
    BuildContext context, {
    required ValueChanged<String> onOpenTransaction,
  })
  transactions;
  final Future<void> Function(
    BuildContext context,
    String id, {
    required ValueChanged<String> onSplit,
    required ValueChanged<String> onLinkTransfer,
    required ValueChanged<String> onMoneyBackFor,
  })
  transactionDetail;

  /// Onboarding.
  final Widget Function({
    required VoidCallback onDone,
    required void Function(String slug) onSkipped,
  })
  androidSetup;
  final Widget Function({
    required VoidCallback onDone,
    required VoidCallback onOpenReview,
    required void Function(String accountId) onEditCard,
    required void Function(String accountId) onSetupCredit,
  })
  scanResults;
  final Future<void> Function(
    BuildContext context, {
    required VoidCallback onDone,
    required VoidCallback onOpenReview,
    required void Function(String accountId) onEditCard,
    required void Function(String accountId) onSetupCredit,
  })
  scanResultsSheet;
}

final appScreensProvider = Provider<AppScreens>(
  (ref) => const AppScreens(),
  name: 'appScreensProvider',
);

Future<void> _cardDetail(
  BuildContext c,
  Account a, {
  VoidCallback? onOpenTransactions,
  ValueChanged<String>? onOpenTransaction,
}) => openCardDetail(
  c,
  a,
  onOpenTransactions: onOpenTransactions,
  onOpenTransaction: onOpenTransaction,
);

Future<void> _compareCards(
  BuildContext c, {
  VoidCallback? onOpenTransactions,
}) => openCompareCards(c, onOpenTransactions: onOpenTransactions);

Future<void> _startAddCard(
  BuildContext c, {
  void Function(Account)? onSaved,
  void Function(Account)? onOpenExisting,
}) => startAddCard(c, onSaved: onSaved, onOpenExisting: onOpenExisting);

Future<void> _editCard(
  BuildContext c,
  Account a, {
  void Function(Account)? onOpenCapture,
}) => openEditCard(c, a, onOpenCapture: onOpenCapture);

Future<void> _cardCaptureSheet(BuildContext c, Account a) =>
    showCardCaptureSheet(
      c,
      institutionCode: a.institutionCode ?? '',
      last4: a.last4,
      cardName: a.label,
    );

Future<void> _addAsset(BuildContext c) =>
    pushScreen<void>(c, (_) => const AddAssetScreen());

Future<void> _prices(BuildContext c) =>
    pushScreen<void>(c, (_) => const PricesScreen());

Future<void> _paywall(BuildContext c) =>
    pushScreen<bool>(c, (_) => const PaywallScreen(), fullscreenDialog: true);

Future<void> _settings(BuildContext c, SettingsDestinations d) =>
    pushScreen<void>(c, (_) => SettingsMainScreen(destinations: d));

Future<void> _backup(
  BuildContext c, {
  required VoidCallback onOpenRestore,
  required bool iCloud,
}) => pushScreen<void>(
  c,
  (_) => BackupScreen(onOpenRestore: onOpenRestore, iCloudAvailable: iCloud),
);

Future<void> _restore(
  BuildContext c, {
  required void Function({required bool regrantDue}) onRestored,
  required VoidCallback onStartFresh,
  required VoidCallback onUpdateApp,
  required bool iCloud,
}) => pushScreen<void>(
  c,
  (_) => RestoreScreen(
    onRestored: onRestored,
    onStartFresh: onStartFresh,
    onUpdateApp: onUpdateApp,
    iCloudAvailable: iCloud,
  ),
);

Future<void> _captureSettings(
  BuildContext c, {
  required bool goldActive,
  required VoidCallback onOpenTemplates,
}) => pushScreen<void>(
  c,
  (_) => CaptureSettingsScreen(
    goldActive: goldActive,
    onOpenTemplates: onOpenTemplates,
  ),
);

Future<void> _templateBuilder(BuildContext c) =>
    pushScreen<void>(c, (_) => const TemplateBuilderScreen());

Future<void> _categories(BuildContext c) =>
    pushScreen<void>(c, (_) => const CategoriesRulesScreen());

Future<void> _privacy(BuildContext c) =>
    pushScreen<void>(c, (_) => const PrivacyScreen());

Future<void> _budget(
  BuildContext c, {
  required void Function(String categoryId, Cycle cycle) onCategoryTap,
}) => pushScreen<void>(
  c,
  (_) => BudgetScreen(onCategoryTap: (id, cycle) => onCategoryTap(id, cycle)),
);

Widget _ask(BuildContext c) => const AskScreen();

Widget _review(BuildContext c) => const ReviewScreen();

Widget _transactions(
  BuildContext c, {
  required ValueChanged<String> onOpenTransaction,
}) => TransactionsListScreen(onOpenTransaction: onOpenTransaction);

Future<void> _transactionDetail(
  BuildContext c,
  String id, {
  required ValueChanged<String> onSplit,
  required ValueChanged<String> onLinkTransfer,
  required ValueChanged<String> onMoneyBackFor,
}) => pushScreen<void>(
  c,
  (_) => TransactionDetailScreen(
    transactionId: id,
    onSplit: onSplit,
    onLinkTransfer: onLinkTransfer,
    onMoneyBackFor: onMoneyBackFor,
  ),
);

Widget _androidSetup({
  required VoidCallback onDone,
  required void Function(String slug) onSkipped,
}) => AndroidSetupScreen(onDone: onDone, onSkipped: onSkipped);

Widget _scanResults({
  required VoidCallback onDone,
  required VoidCallback onOpenReview,
  required void Function(String accountId) onEditCard,
  required void Function(String accountId) onSetupCredit,
}) => ScanResultsScreen(
  onDone: onDone,
  onOpenReview: onOpenReview,
  onEditCard: onEditCard,
  onSetupCredit: onSetupCredit,
);

Future<void> _scanResultsSheet(
  BuildContext c, {
  required VoidCallback onDone,
  required VoidCallback onOpenReview,
  required void Function(String accountId) onEditCard,
  required void Function(String accountId) onSetupCredit,
}) => showScanResultsSheet(
  c,
  onDone: onDone,
  onOpenReview: onOpenReview,
  onEditCard: onEditCard,
  onSetupCredit: onSetupCredit,
);
