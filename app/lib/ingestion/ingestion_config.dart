// T-008 (SPK-01) / T-041: knobs of the ingestion path, kept in one place so
// the open PO answers (T-008 Q1-Q4, Q7) can be plugged in without touching
// the flow.

import 'package:flutter/services.dart' show appFlavor;

/// Q7 (PO, 2026-11-11: YES): the Sms build runs an automatic inbox catch-up
/// scan (allowlisted senders since the last captured message) on each app
/// open. Not built in the spike: `queryInbox` is NOT_AVAILABLE natively until
/// its owner task (T-042, follow-up recorded in T-008.md). The owner flips
/// this when the scan exists; until then it must stay false.
const bool kInboxCatchUpEnabled = false;

// Q3 (PO, 2026-11-11): if a device needs the battery-optimisation exemption,
// the app only links to the system settings list
// (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`, no permission). The
// `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` dialog is not used and its permission
// is never declared (AndroidCaptureHostApi.requestIgnoreBatteryOptimizations
// opens the list).

/// Entries per drainSpool call (native caps at 100).
const int kDrainBatchSize = 20;

/// A drain cycle stops starting new batches after this long (the native
/// worker gives a run 60 s in total).
const Duration kCycleBudget = Duration(seconds: 50);

/// The flavour that contains the native spike receiver and latency recorder
/// (`flutter build --flavor`).
const String kSpikeFlavor = 'devSms';

/// True only in the devSms build. A compile-time constant: AOT drops the
/// spike registry and the spike marks from every other build (CI greps the
/// prod `libapp.so` for the synthetic sender).
const bool kIsSpikeBuild = appFlavor == kSpikeFlavor;
