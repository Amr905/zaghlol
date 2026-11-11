// T-008 (SPK-01): knobs of the ingestion spike, kept in one place so the open
// PO answers (T-008 Q1-Q4, Q7) can be plugged in without touching the flow.

/// Q7 (PO, open): an automatic inbox catch-up scan (allowlisted senders since
/// the last captured message) on each foreground in `*Sms`. Off until the PO
/// decides; `queryInbox` is NOT_AVAILABLE natively until T-042 anyway.
const bool kInboxCatchUpEnabled = false;

/// Q3 (PO, open): how the battery-optimisation exemption is requested, if a
/// device needs it (decision rule in T-008 design note section 7).
enum BatteryExemptionMode {
  /// Default: open the system list (`ACTION_IGNORE_BATTERY_OPTIMIZATION_
  /// SETTINGS`), no extra permission.
  settingsLink,

  /// The `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog. Play restricts it;
  /// it also needs the permission in the manifest, which is not declared.
  directDialog,
}

const BatteryExemptionMode kBatteryExemptionMode =
    BatteryExemptionMode.settingsLink;

/// Entries per drainSpool call (native caps at 100).
const int kDrainBatchSize = 20;

/// A drain cycle stops starting new batches after this long (the native
/// worker gives a run 60 s in total).
const Duration kCycleBudget = Duration(seconds: 50);

/// The flavour that contains the native spike (`flutter build --flavor`).
const String kSpikeFlavor = 'devSms';
