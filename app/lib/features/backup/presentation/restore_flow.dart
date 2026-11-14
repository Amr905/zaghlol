// T-153 / S-04: the restore state machine. Pure state + ports; no widgets.
//
// Order after a successful swap (FU-139): the database is re-opened
// (`appDatabaseProvider` invalidated), the catalog resync runs and clears its
// flag only on success, the key is recovered with the passphrase just typed
// when the restore could not store it, and the one-time re-grant prompt is
// read and its flag cleared. Sync and capture stay paused from before the
// swap until all of that is done.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../application/snapshot_tables.dart';
import 'backup_ports.dart';

enum RestorePhase {
  chooseProvider,
  searching,
  found,
  empty,
  restoring,
  done,
  error,
}

final class RestoreState {
  const RestoreState({
    this.phase = RestorePhase.chooseProvider,
    this.provider = BackupProviderKind.drive,
    this.entries = const [],
    this.selected = 0,
    this.error,
    this.wrongPassphrase = false,
    this.regrantDue = false,
    this.needsKeyLater = false,
  });

  final RestorePhase phase;
  final BackupProviderKind provider;
  final List<BackupEntryView> entries;
  final int selected;
  final RestoreFailureKind? error;

  /// The last attempt used a wrong passphrase (unlimited retries).
  final bool wrongPassphrase;

  /// FR-BAK-07: show "re-allow capture" once.
  final bool regrantDue;

  /// The key could not be re-stored; the next backup asks for the passphrase.
  final bool needsKeyLater;

  BackupEntryView? get current =>
      selected < entries.length ? entries[selected] : null;

  RestoreState copyWith({
    RestorePhase? phase,
    BackupProviderKind? provider,
    List<BackupEntryView>? entries,
    int? selected,
    RestoreFailureKind? error,
    bool clearError = false,
    bool? wrongPassphrase,
    bool? regrantDue,
    bool? needsKeyLater,
  }) => RestoreState(
    phase: phase ?? this.phase,
    provider: provider ?? this.provider,
    entries: entries ?? this.entries,
    selected: selected ?? this.selected,
    error: clearError ? null : (error ?? this.error),
    wrongPassphrase: wrongPassphrase ?? this.wrongPassphrase,
    regrantDue: regrantDue ?? this.regrantDue,
    needsKeyLater: needsKeyLater ?? this.needsKeyLater,
  );
}

class RestoreFlow extends Notifier<RestoreState> {
  @override
  RestoreState build() => const RestoreState();

  void chooseProvider(BackupProviderKind kind) =>
      state = state.copyWith(provider: kind);

  void select(int index) {
    if (index >= 0 && index < state.entries.length) {
      state = state.copyWith(selected: index, wrongPassphrase: false);
    }
  }

  /// Back to the provider choice ("Try another account").
  void reset() => state = RestoreState(provider: state.provider);

  /// Signs in (the provider's own picker) and lists the backups.
  Future<void> search() async {
    state = state.copyWith(
      phase: RestorePhase.searching,
      clearError: true,
      wrongPassphrase: false,
    );
    try {
      final entries = await ref
          .read(backupRestoreGatewayProvider)
          .list(state.provider);
      state = entries.isEmpty
          ? state.copyWith(phase: RestorePhase.empty, entries: const [])
          : state.copyWith(
              phase: RestorePhase.found,
              entries: entries,
              selected: 0,
            );
    } on Object catch (e) {
      state = state.copyWith(
        phase: RestorePhase.error,
        error: restoreFailureKindOf(e),
      );
    }
  }

  /// Restores the selected backup. [passphrase] is used once and not kept.
  Future<void> restore(String passphrase) async {
    final entry = state.current;
    if (entry == null || state.phase == RestorePhase.restoring) return;
    final gateway = ref.read(backupRestoreGatewayProvider);
    final effects = ref.read(restoreSideEffectsProvider);
    state = state.copyWith(
      phase: RestorePhase.restoring,
      wrongPassphrase: false,
      clearError: true,
    );
    var swapped = false;
    try {
      await effects.pause();
      final keyStored = await gateway.restore(
        state.provider,
        entry,
        passphrase,
      );
      swapped = true;
      ref.invalidate(appDatabaseProvider);
      var needsKeyLater = false;
      if (!keyStored) {
        try {
          await gateway.recoverKey(passphrase);
        } on Object {
          needsKeyLater = true;
        }
      }
      var regrant = false;
      try {
        final flags = await effects.readFlags();
        if (flags.catalogResyncDue) {
          try {
            await effects.resyncCatalog();
            await effects.clearFlag(restoreCatalogResyncDueKey);
          } on Object {
            // The flag stays; the next sync run does it.
          }
        }
        regrant = flags.regrantDue;
        if (regrant) await effects.clearFlag(restoreRegrantDueKey);
      } on Object {
        // Flags unreadable: the restore itself succeeded.
      }
      state = state.copyWith(
        phase: RestorePhase.done,
        regrantDue: regrant,
        needsKeyLater: needsKeyLater,
      );
    } on Object catch (e) {
      final kind = restoreFailureKindOf(e);
      if (swapped) {
        state = state.copyWith(phase: RestorePhase.done);
      } else if (kind == RestoreFailureKind.wrongPassphrase) {
        state = state.copyWith(
          phase: RestorePhase.found,
          wrongPassphrase: true,
        );
      } else {
        state = state.copyWith(phase: RestorePhase.error, error: kind);
      }
    } finally {
      try {
        await effects.resume();
      } on Object {
        // Nothing to undo.
      }
    }
  }

  /// "Try again" after an error: search again, or back to the found backup.
  Future<void> retry() async {
    if (state.entries.isEmpty) return search();
    state = state.copyWith(phase: RestorePhase.found, clearError: true);
  }

  /// Corrupted backup with older versions (Gold): pick the next one.
  void tryOlder() {
    final next = state.selected + 1;
    if (next < state.entries.length) {
      state = state.copyWith(
        phase: RestorePhase.found,
        selected: next,
        clearError: true,
        wrongPassphrase: false,
      );
    }
  }
}

final restoreFlowProvider =
    NotifierProvider.autoDispose<RestoreFlow, RestoreState>(
      RestoreFlow.new,
      name: 'restoreFlowProvider',
    );
