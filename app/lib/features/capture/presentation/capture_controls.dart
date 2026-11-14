// T-086: the presentation port behind S-61 / S-62. Widgets talk to
// [CaptureControls]; the real one wraps T-078's `IgnoreRulesService` (one
// write path for ignore rules, rewrites the Guard config before it returns)
// and T-048's `InboxScanService`. Tests override [captureControlsProvider]
// with a fake. Nothing here logs; errors are the services' code-only ones.

import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show PaydaySchedule;

import '../../../core/db/app_database.dart' hide Settings;
import '../../../core/db/app_database_providers.dart';
import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../accounts/presentation/edit_card/edit_card_providers.dart'
    show CardCapturePort;
import '../../budget/application/budget_providers.dart'
    show paydayScheduleProvider;
import '../../budget/application/cycle_app_wiring.dart'
    show domainEventBusProvider;
import '../../transactions/application/bulk_edit.dart';
import '../../transactions/application/transfer_pairing.dart';
import '../application/capture_providers.dart';
import '../application/ignore_rules.dart';
import '../application/inbox_scan_service.dart';
import '../domain/scan_plan.dart';

abstract interface class CaptureControls {
  /// Every ignore rule, re-emitted on each change (FR-CAP-06).
  Stream<List<IgnoreRuleRow>> watchRules();

  /// Live transactions a rule for [target] would cover (the "delete N?" count).
  Future<IgnorePreview> preview(IgnoreTarget target);

  Future<AddIgnoreResult> add(
    IgnoreTarget target, {
    ExistingAction existing = const KeepExisting(),
  });

  Future<RemoveIgnoreResult> remove(String ruleId);

  /// Re-scans the SMS inbox for [depthMonths] (FR-CAP-07); one institution
  /// when [institutionCode] is given. Null when the inbox cannot be scanned
  /// on this device.
  Future<ScanProgress>? rescan({
    required int depthMonths,
    String? institutionCode,
  });

  /// Progress of a running scan (empty when there is no scanner).
  Stream<ScanProgress> get scanProgress;

  /// True on Android with SMS live capture (the tools row is shown).
  bool get canRescan;
}

final class ServiceCaptureControls implements CaptureControls {
  ServiceCaptureControls({
    required this._db,
    required this._rules,
    required this.scanService,
    required this._saveDepth,
  });

  final AppDatabase _db;
  final IgnoreRulesService _rules;
  final InboxScanService? scanService;
  final Future<void> Function(int) _saveDepth;

  @override
  Stream<List<IgnoreRuleRow>> watchRules() =>
      (_db.select(_db.ignoreRules)..orderBy([
            (r) => OrderingTerm.asc(r.institutionCode),
            (r) => OrderingTerm.asc(r.last4),
            (r) => OrderingTerm.asc(r.channel),
          ]))
          .watch();

  @override
  Future<IgnorePreview> preview(IgnoreTarget target) =>
      _rules.previewMatches(target);

  @override
  Future<AddIgnoreResult> add(
    IgnoreTarget target, {
    ExistingAction existing = const KeepExisting(),
  }) => _rules.add(target, existing: existing);

  @override
  Future<RemoveIgnoreResult> remove(String ruleId) => _rules.remove(ruleId);

  @override
  bool get canRescan => scanService != null && _rules.rescanAvailable;

  @override
  Future<ScanProgress>? rescan({
    required int depthMonths,
    String? institutionCode,
  }) {
    final s = scanService;
    if (s == null) return null;
    return () async {
      await _saveDepth(depthMonths);
      return institutionCode == null
          ? await s.startFirstRun()
          : await s.rescanInstitution(institutionCode);
    }();
  }

  @override
  Stream<ScanProgress> get scanProgress =>
      scanService?.progress ?? const Stream<ScanProgress>.empty();
}

/// The wired controls; null until the database is open.
final captureControlsProvider = FutureProvider<CaptureControls>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final coordinator = await ref.watch(captureCoordinatorProvider.future);
  final scan = await ref.watch(inboxScanServiceProvider.future);
  Future<PaydaySchedule> schedule() => ref.read(paydayScheduleProvider.future);
  final bus = ref.watch(domainEventBusProvider);
  final bulk = BulkEditUseCase(db, loadSchedule: schedule, events: bus);
  final pairing = TransferPairingUseCase(
    db,
    loadSchedule: schedule,
    events: bus,
  );
  final rules = IgnoreRulesService(
    db,
    bulkEdit: bulk,
    onRemoved: (id) async {
      await pairing.onRemoved(id);
    },
    onRuleChanged: coordinator?.onRuleChanged,
    rescanAvailable: scan != null,
  );
  return ServiceCaptureControls(
    db: db,
    rules: rules,
    scanService: scan,
    saveDepth: (m) async {
      final repo = await ref.read(settingsRepositoryProvider.future);
      await repo.set(Settings.scanDepthMonths, m);
    },
  );
}, name: 'captureControlsProvider');

final ignoreRulesStreamProvider = StreamProvider<List<IgnoreRuleRow>>((
  ref,
) async* {
  final c = await ref.watch(captureControlsProvider.future);
  yield* c.watchRules();
}, name: 'ignoreRulesStreamProvider');

/// Scan progress for S-61 (C-27).
final scanProgressProvider = StreamProvider<ScanProgress>((ref) async* {
  final c = await ref.watch(captureControlsProvider.future);
  yield* c.scanProgress;
}, name: 'scanProgressProvider');

/// The adapter T-085 left: a new card's channel toggles become ignore rules.
/// Wire it in the shell with
/// `cardCapturePortProvider.overrideWith((r) => r.watch(captureCardPortProvider))`.
final captureCardPortProvider = Provider<CardCapturePort>(
  (ref) => _RulesCardPort(() => ref.read(captureControlsProvider.future)),
  name: 'captureCardPortProvider',
);

final class _RulesCardPort implements CardCapturePort {
  _RulesCardPort(this._controls);

  final Future<CaptureControls> Function() _controls;

  @override
  Future<void> turnOff({
    required String institutionCode,
    required String? last4,
    required Set<String> offChannels,
  }) async {
    final c = await _controls();
    for (final ch in offChannels) {
      await c.add(
        IgnoreTarget(
          institutionCode: institutionCode,
          last4: last4,
          channel: ch,
        ),
      );
    }
  }
}
