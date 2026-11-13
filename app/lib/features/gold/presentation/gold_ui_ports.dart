// T-146: the seams the Gold screens read through. Widgets never touch the
// store, the backend or storage directly; tests override these providers.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/backend/backend_client.dart' show ClientPlatform;
import '../application/entitlement.dart';
import '../application/gold_providers.dart';
import '../application/gold_store.dart';
import '../domain/purchase_outcome.dart';
import '../domain/restore_outcome.dart';

enum GoldPlan {
  monthly,
  yearly,
  lifetime;

  /// The select value used by the `goldPaywall*`/`goldAccount*` strings.
  String get key => name;

  String get productId => switch (this) {
    GoldPlan.monthly => GoldProducts.monthly,
    GoldPlan.yearly => GoldProducts.yearly,
    GoldPlan.lifetime => GoldProducts.lifetime,
  };

  static String selectKey(GoldPlan? p) => p?.key ?? 'other';

  bool get renews => this != GoldPlan.lifetime;

  static GoldPlan? fromWire(String? s) {
    for (final p in values) {
      if (p.name == s) return p;
    }
    return null;
  }
}

/// The `platform` select value of `goldPaywallRenewal`.
String goldPlatformKey(ClientPlatform p) =>
    p == ClientPlatform.ios ? 'ios' : 'android';

/// One plan with the store's own formatted price (never computed here).
@immutable
final class GoldPlanOffer {
  const GoldPlanOffer({required this.plan, required this.storePrice});
  final GoldPlan plan;
  final String storePrice;
}

/// The offers from the store. Throws when the store has none (prices failed).
final goldOffersProvider = FutureProvider.autoDispose<List<GoldPlanOffer>>((
  ref,
) async {
  final r = await InAppPurchase.instance.queryProductDetails(GoldProducts.all);
  if (r.error != null) throw StateError('store');
  final out = <GoldPlanOffer>[];
  for (final p in GoldPlan.values) {
    for (final d in r.productDetails) {
      if (d.id == p.productId) {
        out.add(GoldPlanOffer(plan: p, storePrice: d.price));
      }
    }
  }
  if (out.isEmpty) throw StateError('no products');
  return out;
}, name: 'goldOffersProvider');

/// What the screens do. The default wires T-145 and T-144.
abstract interface class GoldActions {
  Future<bool> buy(GoldPlan plan);
  Stream<PurchaseOutcome> get outcomes;
  Future<RestoreOutcome> restore();
  Future<void> dismissSupportNotice();
}

final class _ServiceGoldActions implements GoldActions {
  _ServiceGoldActions(this._ref);
  final Ref _ref;

  @override
  Future<bool> buy(GoldPlan plan) =>
      _ref.read(purchaseServiceProvider).buy(plan.productId);

  @override
  Stream<PurchaseOutcome> get outcomes =>
      _ref.read(purchaseServiceProvider).outcomes;

  @override
  Future<RestoreOutcome> restore() =>
      _ref.read(restoreServiceProvider).restore();

  @override
  Future<void> dismissSupportNotice() =>
      _ref.read(entitlementServiceProvider).dismissSupportNotice();
}

final goldActionsProvider = Provider<GoldActions>(
  _ServiceGoldActions.new,
  name: 'goldActionsProvider',
);

/// What the status messages need beyond the phase (verified cached claims).
@immutable
final class GoldStatusInfo {
  const GoldStatusInfo({
    this.plan,
    this.nextMoveAt,
    this.supportNoticePending = false,
  });
  final GoldPlan? plan;
  final DateTime? nextMoveAt;
  final bool supportNoticePending;
}

final goldStatusInfoProvider = FutureProvider.autoDispose<GoldStatusInfo>((
  ref,
) async {
  final svc = ref.watch(entitlementServiceProvider);
  final claims = await svc.cachedClaims();
  return GoldStatusInfo(
    plan: GoldPlan.fromWire(claims?.plan),
    nextMoveAt: claims?.nextMoveAt,
    supportNoticePending: await svc.hasPendingSupportNotice(),
  );
}, name: 'goldStatusInfoProvider');

enum GoldLink { terms, privacy, manageSubscription }

/// Opens an external page (terms, privacy, the store's subscription page).
final goldLinkOpenerProvider = Provider<void Function(GoldLink)>(
  (ref) => (_) {},
  name: 'goldLinkOpenerProvider',
);

/// Opens sign-in (S-69). Null: the entry point is not wired, so no Sign in
/// button is shown.
final goldSignInOpenerProvider = Provider<VoidCallback?>(
  (ref) => null,
  name: 'goldSignInOpenerProvider',
);

/// Persistence of the last unsolicited prompt (A-22).
abstract interface class UpsellCapStore {
  Future<DateTime?> lastShown();
  Future<void> markShown(DateTime at);
}

final class MemoryUpsellCapStore implements UpsellCapStore {
  DateTime? _at;
  @override
  Future<DateTime?> lastShown() async => _at;
  @override
  Future<void> markShown(DateTime at) async => _at = at;
}

final upsellCapStoreProvider = Provider<UpsellCapStore>(
  (ref) => MemoryUpsellCapStore(),
  name: 'upsellCapStoreProvider',
);

final upsellClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
  name: 'upsellClockProvider',
);
