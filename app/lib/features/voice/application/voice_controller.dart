// T-120: the S-31 state machine. Listen, understand, let the user edit,
// save on confirmation only (FR-VOI-03). Rules it enforces:
//  * on-device recognition first; the online recognizer only after the user
//    agrees in this session (D-42, OQ-06); never silently;
//  * a Free user with 15 logs this month never reaches the mic (A-15);
//  * one confirmed recording = one counted log, however many items (A-14);
//    "Try again" and closing without saving count nothing.
// Audio and transcripts live only in this state and are dropped with it:
// nothing here logs, persists or sends them.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/application/budget_providers.dart';
import '../../gold/application/gating.dart';
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/edit/txn_edit_providers.dart';
import '../../transactions/presentation/list/txn_list_providers.dart';
import 'speech_port.dart';
import 'voice_models.dart';
import 'voice_providers.dart';

/// UX-A-02: auto-stop after 2 s of silence, 30 s at most.
const Duration voicePauseFor = Duration(seconds: 2);
const Duration voiceListenFor = Duration(seconds: 30);

const int _msPerDay = 86400000;

final class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.checking,
    this.transcript = '',
    this.level = 0,
    this.drafts = const [],
    this.accountId,
    this.date,
    this.online = false,
    this.saveFailed = false,
    this.savedIds = const [],
    this.itemAccounts = const {},
  });

  final VoicePhase phase;
  final String transcript;

  /// Input level 0..1.
  final double level;
  final List<VoiceDraft> drafts;
  final String? accountId;

  /// Chosen day; null = today.
  final CivilDate? date;

  /// The user agreed to the online recognizer for this session.
  final bool online;
  final bool saveFailed;
  final List<String> savedIds;

  /// Per-item account the user picked on a row (draft key -> account id).
  final Map<int, String> itemAccounts;

  bool get canSave => drafts.isNotEmpty && drafts.every((d) => d.ready);

  VoiceState copyWith({
    VoicePhase? phase,
    String? transcript,
    double? level,
    List<VoiceDraft>? drafts,
    String? accountId,
    CivilDate? date,
    bool clearDate = false,
    bool? online,
    bool? saveFailed,
    List<String>? savedIds,
    Map<int, String>? itemAccounts,
  }) => VoiceState(
    phase: phase ?? this.phase,
    transcript: transcript ?? this.transcript,
    level: level ?? this.level,
    drafts: drafts ?? this.drafts,
    accountId: accountId ?? this.accountId,
    date: clearDate ? null : (date ?? this.date),
    online: online ?? this.online,
    saveFailed: saveFailed ?? this.saveFailed,
    savedIds: savedIds ?? this.savedIds,
    itemAccounts: itemAccounts ?? this.itemAccounts,
  );
}

final voiceControllerProvider =
    NotifierProvider.autoDispose<VoiceController, VoiceState>(
      VoiceController.new,
      name: 'voiceControllerProvider',
    );

class VoiceController extends Notifier<VoiceState> {
  String _localeId = 'ar_EG';
  bool _disposed = false;
  int _session = 0;
  final Set<int> _savedKeys = {};

  @override
  VoiceState build() {
    final port = ref.read(speechPortProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(port.cancel());
    });
    return const VoiceState();
  }

  void _set(VoiceState s) {
    if (!_disposed) state = s;
  }

  /// Opens the logger: checks the quota, then listens.
  Future<void> begin({required String languageCode}) async {
    _localeId = languageCode == 'ar' ? 'ar_EG' : 'en_US';
    _set(const VoiceState());
    if (!ref.read(entitlementStateProvider).isGold) {
      final usage = await ref.read(voiceUsageProvider.future);
      final used = await usage.countThisMonth();
      if (used >= FreeLimits.voiceEntriesPerMonth) {
        _set(state.copyWith(phase: VoicePhase.limit));
        return;
      }
    }
    await _startFirst();
  }

  /// On-device only when the OS confirms it (D-42): otherwise the consent
  /// sheet comes first and the recognizer is never started before "Allow".
  Future<void> _startFirst() async {
    var supported = false;
    try {
      supported = await ref
          .read(speechPortProvider)
          .supportsOnDevice(_localeId);
    } on Object {
      supported = false;
    }
    if (_disposed) return;
    if (supported) {
      await _listen(onDevice: true);
    } else {
      _set(state.copyWith(phase: VoicePhase.needConsent));
    }
  }

  Future<void> _listen({required bool onDevice}) async {
    final id = ++_session;
    _set(
      state.copyWith(
        phase: VoicePhase.listening,
        transcript: '',
        level: 0,
        drafts: const [],
        itemAccounts: const {},
      ),
    );
    final err = await ref
        .read(speechPortProvider)
        .start(
          localeId: _localeId,
          onDevice: onDevice,
          pauseFor: voicePauseFor,
          listenFor: voiceListenFor,
          sink: SpeechSink(
            onText: (t, {required isFinal}) {
              if (id == _session && state.phase == VoicePhase.listening) {
                _set(state.copyWith(transcript: t));
              }
            },
            onLevel: (v) {
              if (id == _session && state.phase == VoicePhase.listening) {
                _set(state.copyWith(level: v));
              }
            },
            onEnded: () {
              if (id == _session) unawaited(_finish());
            },
            onError: (e) {
              if (id == _session) unawaited(_failed(e));
            },
          ),
        );
    if (err != null && id == _session) await _failed(err);
  }

  Future<void> _failed(SpeechError e) async {
    if (state.phase != VoicePhase.listening) return;
    switch (e) {
      case SpeechError.permissionDenied:
        _set(state.copyWith(phase: VoicePhase.micDenied));
      case SpeechError.unavailable:
        // No on-device Arabic: ask first; if the online recognizer was
        // already allowed and still failed, there is nothing left to offer.
        _set(
          state.copyWith(
            phase: state.online
                ? VoicePhase.unavailable
                : VoicePhase.needConsent,
          ),
        );
      case SpeechError.noSpeech:
        if (state.transcript.trim().isEmpty) {
          _set(state.copyWith(phase: VoicePhase.empty));
        } else {
          await _finish();
        }
      case SpeechError.other:
        if (state.transcript.trim().isEmpty) {
          _set(state.copyWith(phase: VoicePhase.unavailable));
        } else {
          await _finish();
        }
    }
  }

  /// The "Done" button.
  Future<void> stopListening() async {
    await ref.read(speechPortProvider).stop();
    await _finish();
  }

  /// Consent sheet: "Allow".
  Future<void> allowOnline() async {
    _set(state.copyWith(online: true));
    await _listen(onDevice: false);
  }

  /// "Try again": discards everything, nothing counted.
  Future<void> tryAgain() async {
    _session++;
    await ref.read(speechPortProvider).cancel();
    _savedKeys.clear();
    if (state.online) {
      await _listen(onDevice: false);
    } else {
      await _startFirst();
    }
  }

  Future<void> _finish() async {
    if (state.phase != VoicePhase.listening) return;
    _session++;
    final text = state.transcript.trim();
    if (text.isEmpty) {
      _set(state.copyWith(phase: VoicePhase.empty));
      return;
    }
    _set(state.copyWith(phase: VoicePhase.understanding));
    try {
      final lookups = await ref.read(txnLookupsProvider.future);
      final cash = await ref.read(defaultCashAccountIdProvider.future);
      final accountId =
          cash ?? (lookups.accounts.isEmpty ? null : lookups.accounts.first.id);
      final accountCurrency = accountId == null
          ? null
          : Currency.tryOf(lookups.account(accountId)?.currencyCode ?? '');
      final interpreter = await ref.read(voiceInterpreterProvider.future);
      final drafts = await interpreter.interpret(
        text,
        accountCurrency ?? ref.read(voiceDefaultCurrencyProvider),
      );
      if (drafts.isEmpty) {
        _set(state.copyWith(phase: VoicePhase.empty));
        return;
      }
      _set(
        state.copyWith(
          phase: VoicePhase.parsed,
          drafts: drafts,
          accountId: accountId,
        ),
      );
    } on Object {
      _set(state.copyWith(phase: VoicePhase.empty));
    }
  }

  // ---- edits (FR-VOI-03) ----

  void remove(int key) {
    final next = [
      for (final d in state.drafts)
        if (d.key != key) d,
    ];
    _set(
      next.isEmpty
          ? state.copyWith(phase: VoicePhase.empty, drafts: next)
          : state.copyWith(drafts: next),
    );
  }

  void update(
    int key, {
    String? text,
    Money? amount,
    bool clearAmount = false,
    String? categoryId,
  }) => _set(
    state.copyWith(
      drafts: [
        for (final d in state.drafts)
          if (d.key == key)
            d.copyWith(
              text: text,
              amount: amount,
              clearAmount: clearAmount,
              categoryId: categoryId,
            )
          else
            d,
      ],
    ),
  );

  void setAccount(String id) => _set(state.copyWith(accountId: id));

  /// The user picked the account for one item (its currency must match).
  void setItemAccount(int key, String id) =>
      _set(state.copyWith(itemAccounts: {...state.itemAccounts, key: id}));

  void setDate(CivilDate? date) => _set(
    date == null ? state.copyWith(clearDate: true) : state.copyWith(date: date),
  );

  /// The account an item is stored on: the one picked on its row, else the
  /// chip's when its currency matches the spoken amount's, else the first
  /// live account in that currency; null when there is none (nothing is
  /// converted, D-28). The row shows it whenever it differs from the chip.
  String? accountFor(VoiceDraft d, TxnLookups lookups) {
    final amount = d.amount;
    if (amount == null) return state.accountId;
    final picked = state.itemAccounts[d.key];
    if (picked != null &&
        lookups.account(picked)?.currencyCode == amount.currency.code) {
      return picked;
    }
    final chosen = state.accountId == null
        ? null
        : lookups.account(state.accountId!);
    if (chosen?.currencyCode == amount.currency.code) return chosen!.id;
    for (final a in lookups.accounts) {
      if (a.currencyCode == amount.currency.code) return a.id;
    }
    return null;
  }

  // ---- save (the only place anything is written) ----

  Future<void> save() async {
    if (state.phase != VoicePhase.parsed || !state.canSave) return;
    if (state.drafts.any((d) => d.categoryId == null)) return;
    final gold = ref.read(entitlementStateProvider).isGold;
    final usage = await ref.read(voiceUsageProvider.future);
    if (!gold &&
        await usage.countThisMonth() >= FreeLimits.voiceEntriesPerMonth) {
      _set(state.copyWith(phase: VoicePhase.limit));
      return;
    }
    _set(state.copyWith(phase: VoicePhase.saving, saveFailed: false));
    try {
      final lookups = await ref.read(txnLookupsProvider.future);
      final editor = await ref.read(transactionEditorProvider.future);
      final nowMs = ref.read(clockProvider)().toUtc().millisecondsSinceEpoch;
      final offset = ref.read(localZoneProvider).offsetAtInstant(nowMs);
      final today = ref.read(todayProvider);
      final date = state.date ?? today;
      final at = date.epochDay == today.epochDay
          ? ref.read(clockProvider)().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(
              date.epochDay * _msPerDay + 12 * 3600000 - offset * 60000,
              isUtc: true,
            );
      final ids = [...state.savedIds];
      for (final d in state.drafts) {
        if (_savedKeys.contains(d.key)) continue;
        final account = accountFor(d, lookups);
        if (account == null) throw StateError('no account');
        final saved = await editor.add([
          NewTransaction(
            accountId: account,
            direction: TxnDirection.expense,
            amount: d.amount!,
            occurredAt: at,
            occurredTzOffsetMin: offset,
            categoryId: d.categoryId,
            merchant: d.text.trim().isEmpty ? null : d.text.trim(),
            source: TxnSource.voice,
          ),
        ]);
        _savedKeys.add(d.key);
        ids.addAll(saved);
        _set(state.copyWith(savedIds: ids));
      }
      await usage.countOne();
      _set(state.copyWith(phase: VoicePhase.saved, savedIds: ids));
    } on Object {
      _set(state.copyWith(phase: VoicePhase.parsed, saveFailed: true));
    }
  }
}
