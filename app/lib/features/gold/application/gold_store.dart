// T-145: the store port (Play Billing / StoreKit 2) and its `in_app_purchase`
// adapter. Everything above this file works on [StorePurchase] values, so the
// purchase and restore logic is tested with a fake store; no real store
// account is needed.
//
// Nothing here logs. A purchase token or signed transaction is held only in
// [StorePurchase.reference] and never printed ([toString] shows no value).

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

import '../../../core/backend/backend_client.dart' show ClientPlatform;

/// The Gold products (backend-api §4.3 product table).
abstract final class GoldProducts {
  static const String monthly = 'zaghlol_gold_monthly';
  static const String yearly = 'zaghlol_gold_yearly';
  static const String lifetime = 'zaghlol_gold_lifetime';
  static const Set<String> all = {monthly, yearly, lifetime};
}

enum StorePurchaseState { pending, purchased, restored, error, canceled }

/// One purchase as the store reports it.
final class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.state,
    required this.reference,
    this.purchaseId,
    this.needsCompletion = true,
  });

  final String productId;
  final StorePurchaseState state;

  /// Android: the purchase token. iOS: the StoreKit 2 signed transaction
  /// (JWS). Empty while there is none (pending, error).
  final String reference;

  /// Store transaction/order ID, used only to finish an iOS transaction.
  final String? purchaseId;

  /// False when the store already considers the purchase acknowledged.
  final bool needsCompletion;

  @override
  String toString() => 'StorePurchase(${state.name})';
}

/// A purchase the store says this account owns (restore input).
final class OwnedPurchase {
  const OwnedPurchase({required this.productId, required this.reference});
  final String productId;
  final String reference;

  @override
  String toString() => 'OwnedPurchase';
}

abstract interface class GoldStore {
  /// Purchase updates, including those redelivered at start (unacknowledged
  /// Play purchases, unfinished StoreKit transactions).
  Stream<List<StorePurchase>> get updates;

  /// Starts listening. Must run at app start (Play redelivers then).
  Future<void> start();

  Future<void> dispose();

  /// Opens the store sheet; the result arrives on [updates]. [bindingRef] is
  /// `StoreBindingRef(installId)`: Play `obfuscatedAccountId`, Apple
  /// `appAccountToken`. False when the flow could not start.
  Future<bool> buy(String productId, {required String bindingRef});

  /// Acknowledges (Play) or finishes (StoreKit) [purchase]. Called only after
  /// the backend verified it.
  Future<void> complete(StorePurchase purchase);

  /// Android: `queryPurchases`; iOS: current StoreKit entitlements. Purchased
  /// items only, at most 20.
  Future<List<OwnedPurchase>> queryOwned();

  /// R5-3(b): true only when this device's Apple ID has a StoreKit
  /// transaction for [productId] (`Transaction.currentEntitlements` /
  /// `Transaction.all`). Always false on Android.
  Future<bool> hasStoreKitTransactionFor(String productId);
}

/// The production store over `in_app_purchase` 3.3 (PBL 8, pending purchases
/// on by default; StoreKit 2 is the plugin's default on iOS).
final class InAppPurchaseGoldStore implements GoldStore {
  InAppPurchaseGoldStore({required this._platform, InAppPurchase? iap})
    : _iapOrNull = iap;

  final ClientPlatform _platform;
  final InAppPurchase? _iapOrNull;
  late final InAppPurchase _iap = _iapOrNull ?? InAppPurchase.instance;

  final StreamController<List<StorePurchase>> _out =
      StreamController<List<StorePurchase>>.broadcast();
  final Map<String, PurchaseDetails> _live = {};
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  Stream<List<StorePurchase>> get updates => _out.stream;

  @override
  Future<void> start() async {
    if (_sub != null) return;
    _sub = _iap.purchaseStream.listen(
      (details) {
        final mapped = <StorePurchase>[];
        for (final d in details) {
          final p = _map(d);
          _live[_key(p)] = d;
          mapped.add(p);
        }
        _out.add(mapped);
      },
      // A stream error carries no purchase; the next start redelivers.
      onError: (Object _) {},
    );
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _out.close();
  }

  @override
  Future<bool> buy(String productId, {required String bindingRef}) async {
    if (!GoldProducts.all.contains(productId)) return false;
    final res = await _iap.queryProductDetails({productId});
    if (res.error != null || res.productDetails.isEmpty) return false;
    final param = PurchaseParam(
      productDetails: res.productDetails.first,
      applicationUserName: bindingRef,
    );
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    final live = _live[_key(purchase)];
    if (live == null) return; // redelivered (and completed) at the next start
    if (live.pendingCompletePurchase) await _iap.completePurchase(live);
    _live.remove(_key(purchase));
  }

  @override
  Future<List<OwnedPurchase>> queryOwned() async {
    if (_platform == ClientPlatform.android) {
      final addition = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final res = await addition.queryPastPurchases();
      if (res.error != null) throw const StoreQueryException();
      return [
        for (final d in res.pastPurchases)
          if (d.status == PurchaseStatus.purchased ||
              d.status == PurchaseStatus.restored)
            OwnedPurchase(
              productId: d.productID,
              reference: d.verificationData.serverVerificationData,
            ),
      ].where(_ownedShape).take(20).toList();
    }
    try {
      final owned = await SK2Transaction.currentEntitlements();
      return [
        for (final t in owned)
          if (GoldProducts.all.contains(t.productId) &&
              (t.receiptData ?? '').isNotEmpty)
            OwnedPurchase(productId: t.productId, reference: t.receiptData!),
      ].take(20).toList();
    } on Object {
      throw const StoreQueryException();
    }
  }

  @override
  Future<bool> hasStoreKitTransactionFor(String productId) async {
    if (_platform != ClientPlatform.ios) return false;
    try {
      final current = await SK2Transaction.currentEntitlements();
      if (current.any((t) => t.productId == productId)) return true;
      final all = await SK2Transaction.transactions();
      return all.any((t) => t.productId == productId);
    } on Object {
      return false;
    }
  }

  static bool _ownedShape(OwnedPurchase p) =>
      GoldProducts.all.contains(p.productId) && p.reference.isNotEmpty;

  static String _key(StorePurchase p) => '${p.productId}|${p.reference}';

  StorePurchase _map(PurchaseDetails d) {
    final state = switch (d.status) {
      PurchaseStatus.pending => StorePurchaseState.pending,
      PurchaseStatus.purchased => StorePurchaseState.purchased,
      PurchaseStatus.restored => StorePurchaseState.restored,
      PurchaseStatus.error => StorePurchaseState.error,
      PurchaseStatus.canceled => StorePurchaseState.canceled,
    };
    final isGold = GoldProducts.all.contains(d.productID);
    return StorePurchase(
      productId: d.productID,
      state: isGold ? state : StorePurchaseState.error,
      reference: d.verificationData.serverVerificationData,
      purchaseId: d.purchaseID,
      needsCompletion: d.pendingCompletePurchase,
    );
  }
}

/// The store could not list the account's purchases. Code only.
final class StoreQueryException implements Exception {
  const StoreQueryException();
  @override
  String toString() => 'StoreQueryException';
}
