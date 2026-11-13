// T-147: wiring and the seam the account screen (S-69) reads through.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_client.dart'
    show ClientPlatform, SignInRequestProvider;
import '../../catalog_sync/application/sync_providers.dart';
import '../../gold/application/entitlement.dart';
import '../../gold/application/gold_providers.dart';
import '../../gold/domain/restore_outcome.dart';
import '../domain/sign_in_outcome.dart';
import 'account_service.dart';
import 'apple_state.dart';
import 'id_token_source.dart';
import 'protect_suggestion.dart';

final idTokenSourceProvider = Provider<IdTokenSource>((ref) {
  final platform = ref.watch(clientPlatformProvider);
  return RoutingIdTokenSource(
    google: GoogleIdTokenSource(
      port: PluginGoogleSignInPort(),
      isIos: platform == ClientPlatform.ios,
    ),
    apple: AppleIdTokenSource(
      platform: platform,
      port: PluginApplePort(isAndroid: platform == ClientPlatform.android),
      guard: AppleStateGuard(),
    ),
  );
}, name: 'idTokenSourceProvider');

final accountServiceProvider = Provider<AccountService>(
  (ref) => AccountService(
    backend: BackendClientAccountBackend(ref.watch(backendClientProvider)),
    entitlement: ref.watch(entitlementServiceProvider),
    seats: ref.watch(seatProverProvider),
    tokens: ref.watch(idTokenSourceProvider),
    platform: ref.watch(clientPlatformProvider),
    hasStoreKitTransaction: ref
        .watch(goldStoreProvider)
        .hasStoreKitTransactionFor,
  ),
  name: 'accountServiceProvider',
);

final protectGoldSuggestionProvider = Provider<ProtectGoldSuggestion>(
  (ref) => ProtectGoldSuggestion(
    store: ref.watch(backendStateStoreProvider),
    installId: ref.watch(backendClientProvider).installId,
    signedIn: ref.watch(accountServiceProvider).isSignedIn,
  ),
  name: 'protectGoldSuggestionProvider',
);

/// Read once at app start (sync lifecycle): records the D-54 suggestion when a
/// purchase made on this phone is verified.
final protectSuggestionRecorderProvider = Provider<void>((ref) {
  final s = ref.watch(protectGoldSuggestionProvider);
  final sub = ref
      .watch(purchaseServiceProvider)
      .outcomes
      .listen((o) => unawaited(s.onPurchaseOutcome(o)));
  ref.onDispose(sub.cancel);
}, name: 'protectSuggestionRecorderProvider');

/// What S-69 shows about the account.
final class AccountStatus {
  const AccountStatus({required this.signedIn, this.linkedGold = false});
  final bool signedIn;

  /// The cached entitlement covers an account-linked purchase (sign-out then
  /// pauses Gold here).
  final bool linkedGold;
}

abstract interface class AccountActions {
  Future<AccountStatus> status();
  Future<bool> protectPending();
  Future<void> dismissProtect();
  Future<SignInOutcome> signIn(
    SignInRequestProvider provider, {
    bool replaceLink = false,
  });
  Future<SignOutOutcome> signOut();
  Future<DeleteAccountOutcome> deleteAccount();
  Future<RestoreOutcome> restore();
}

final class _ServiceAccountActions implements AccountActions {
  _ServiceAccountActions(this._ref);
  final Ref _ref;

  AccountService get _svc => _ref.read(accountServiceProvider);

  @override
  Future<AccountStatus> status() async {
    final claims = await _ref.read(entitlementServiceProvider).cachedClaims();
    return AccountStatus(
      signedIn: await _svc.isSignedIn(),
      linkedGold: claims?.acct != null,
    );
  }

  @override
  Future<bool> protectPending() =>
      _ref.read(protectGoldSuggestionProvider).pending();

  @override
  Future<void> dismissProtect() =>
      _ref.read(protectGoldSuggestionProvider).clear();

  @override
  Future<SignInOutcome> signIn(
    SignInRequestProvider provider, {
    bool replaceLink = false,
  }) async {
    final o = await _svc.signIn(provider, replaceLink: replaceLink);
    if (o is SignedIn) await dismissProtect();
    return o;
  }

  @override
  Future<SignOutOutcome> signOut() => _svc.signOut();

  @override
  Future<DeleteAccountOutcome> deleteAccount() => _svc.deleteAccount();

  @override
  Future<RestoreOutcome> restore() =>
      _ref.read(restoreServiceProvider).restore();
}

final accountActionsProvider = Provider<AccountActions>(
  _ServiceAccountActions.new,
  name: 'accountActionsProvider',
);

final accountStatusProvider = FutureProvider.autoDispose<AccountStatus>(
  (ref) => ref.watch(accountActionsProvider).status(),
  name: 'accountStatusProvider',
);

final protectPendingProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(accountActionsProvider).protectPending(),
  name: 'protectPendingProvider',
);
