import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Gold gate matrix and local entitlement state (T-119, SRS §5.2, BR-GOLD-04).
///
/// The app never grants Gold from local state alone: [EntitlementState.gold]
/// is only produced by [EntitlementNotifier.applyVerified], which T-144 calls
/// after it has verified the backend-signed token against trusted time.
/// Everything else (never loaded, expired, unverifiable, unknown) is Free.

enum Tier { free, gold }

/// Every capability that differs between Free and Gold (SRS §5.2).
enum GoldCapability {
  customSmsRegex,
  customCategories,
  voiceEntry,
  allCharts,
  deepCoaching,
  foreignAssets,
  csvExport,
  csvImport,
  pdfStatementImport,
  onlineStatementImport,
  autoBackupSchedule,
  backupHistory,
  crossPlatformGold,
}

/// What the user is trying to do with a capability's data.
enum GateAction {
  /// Viewing data already created (always allowed, BR-GOLD-04).
  read,

  /// Creating or using the feature anew.
  create,
}

/// Free-tier numbers from SRS §5.2.
abstract final class FreeLimits {
  static const int voiceEntriesPerMonth = 15;
  static const int coreCharts = 4;
  static const int totalCharts = 12;
  static const int backupSlots = 1;
  static const int goldBackupVersions = 5;
}

@immutable
final class EntitlementState {
  const EntitlementState._(this.tier);

  static const EntitlementState free = EntitlementState._(Tier.free);

  static const EntitlementState _gold = EntitlementState._(Tier.gold);

  final Tier tier;

  bool get isGold => tier == Tier.gold;

  @override
  bool operator ==(Object other) =>
      other is EntitlementState && other.tier == tier;

  @override
  int get hashCode => tier.hashCode;
}

@immutable
final class GateDecision {
  const GateDecision._(this.allowed, this.paywall);
  static const GateDecision allow = GateDecision._(true, false);

  /// Blocked; the caller should offer the paywall.
  static const GateDecision needsGold = GateDecision._(false, true);

  final bool allowed;
  final bool paywall;
}

/// Pure matrix. Reads are never blocked (BR-GOLD-04); creating needs Gold,
/// except where Free has a quota, handled by the `*Allowed` helpers below.
abstract final class GoldGate {
  static const Set<GoldCapability> _quotaed = {
    GoldCapability.voiceEntry,
    GoldCapability.allCharts,
    GoldCapability.backupHistory,
  };

  static GateDecision check(
    EntitlementState state,
    GoldCapability capability, {
    GateAction action = GateAction.create,
  }) {
    if (action == GateAction.read) return GateDecision.allow;
    if (state.isGold) return GateDecision.allow;
    // Quota-limited capabilities are allowed for Free only through the
    // dedicated helpers, so the plain check fails closed.
    return GateDecision.needsGold;
  }

  static bool isQuotaed(GoldCapability c) => _quotaed.contains(c);

  /// Voice entry: Free gets 15 per month, Gold unlimited. [usedThisMonth]
  /// is counted in the user's local month by the caller.
  static GateDecision voiceEntry(EntitlementState state, int usedThisMonth) {
    if (state.isGold || usedThisMonth < FreeLimits.voiceEntriesPerMonth) {
      return GateDecision.allow;
    }
    return GateDecision.needsGold;
  }

  /// Charts: Free sees [FreeLimits.coreCharts] (core indexes 0..3 of the
  /// ordered chart list); Gold all 12. Viewing is by chart index.
  static GateDecision chart(EntitlementState state, int chartIndex) {
    if (state.isGold ||
        (chartIndex >= 0 && chartIndex < FreeLimits.coreCharts)) {
      return GateDecision.allow;
    }
    return GateDecision.needsGold;
  }

  /// Backup versions kept: Free 1 slot, Gold last 5.
  static int backupVersionsKept(EntitlementState state) =>
      state.isGold ? FreeLimits.goldBackupVersions : FreeLimits.backupSlots;

  /// Export: Free gets a preview only.
  static bool exportPreviewOnly(EntitlementState state) => !state.isGold;
}

/// Called when a gate blocks; the UI layer registers the paywall opener.
typedef PaywallTrigger = void Function(GoldCapability capability);

final paywallTriggerProvider = Provider<PaywallTrigger>((ref) => (_) {});

/// Free by default; Gold only via [applyVerified].
class EntitlementNotifier extends Notifier<EntitlementState> {
  @override
  EntitlementState build() => EntitlementState.free;

  /// Called by T-144 with the result of verifying the signed token against
  /// trusted time. Gold for `active` and `grace` (backend-api 4.3); anything else is Free.
  void applyVerified({required bool verified, required String? status}) {
    state = (verified && (status == 'active' || status == 'grace'))
        ? EntitlementState._gold
        : EntitlementState.free;
  }

  /// Dev builds only; ignored in profile/release.
  void debugOverride(bool gold) {
    if (!kDebugMode) return;
    state = gold ? EntitlementState._gold : EntitlementState.free;
  }

  void reset() => state = EntitlementState.free;
}

final entitlementStateProvider =
    NotifierProvider<EntitlementNotifier, EntitlementState>(
      EntitlementNotifier.new,
    );

/// Checks [capability] and fires the paywall hook when blocked.
bool gateOrPaywall(
  Ref ref,
  GoldCapability capability, {
  GateAction action = GateAction.create,
}) {
  final d = GoldGate.check(
    ref.read(entitlementStateProvider),
    capability,
    action: action,
  );
  if (!d.allowed) ref.read(paywallTriggerProvider)(capability);
  return d.allowed;
}
