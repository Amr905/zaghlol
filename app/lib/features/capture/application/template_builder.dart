// T-164: state of S-65 (custom message template, Gold; FR-PAR-07).
//
// The pasted sample is a raw message: it lives only in this notifier's state
// (auto-disposed with the screen), is never logged, and only its SHA-256
// goes into `custom_templates.sample_hash`. The template itself is built by
// the pure engine in `zaghlol_parsing` (`buildCustomTemplate`), which keeps
// the generated regex bounded; the user never writes one.

import 'custom_template_reparse.dart';

import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../ingestion/ulid.dart';
import '../../gold/application/gating.dart';
import '../data/drift_template_builder_store.dart';

/// A message offered as a starting point (review queue). Never logged.
final class TemplateSample {
  const TemplateSample({
    required this.sender,
    required this.channel,
    required this.body,
  });

  final String sender;
  final String channel;
  final String body;

  @override
  String toString() => 'TemplateSample(<redacted>)';
}

/// What S-65 reads and writes. Tests fake it.
abstract interface class TemplateBuilderStore {
  /// Recent unrecognized messages (review queue), newest first.
  Future<List<TemplateSample>> reviewSamples();

  /// Recent messages from [sender] on [channel] for the test step, newest
  /// first, at most [maxCustomTestMessages].
  Future<List<String>> senderHistory(String sender, String channel);

  /// Inserts the template row. The Guard config follows from the table
  /// watch (T-047); [sampleHash] is a SHA-256 hex, never the sample.
  Future<void> saveTemplate({
    required String id,
    required String sender,
    required String channel,
    required Map<String, Object?> template,
    required String sampleHash,
    required int createdAt,
  });
}

final templateBuilderStoreProvider = Provider<TemplateBuilderStore>((ref) {
  return DriftTemplateBuilderStore(() => ref.read(appDatabaseProvider.future));
}, name: 'templateBuilderStoreProvider');

/// Called after a template is saved: the T-076 re-parse of the review
/// messages the template now matches (WIRE-SVC). Tests override it.
final customTemplateSavedHookProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await reparseAfterTemplateSaved(ref);
  },
  name: 'customTemplateSavedHookProvider',
);

/// Which message in the history did not match, and why (index only).
typedef TemplateMiss = (int index, CustomTestFailure reason);

enum TemplateSaveError { amount, sender, selfParse, failed }

final class TemplateBuilderState {
  const TemplateBuilderState({
    this.sample = '',
    this.tokens = const [],
    this.selection,
    this.spans = const {},
    this.direction = TemplateDirection.expense,
    this.sender = '',
    this.channel = 'sms',
    this.history = const [],
    this.report,
    this.error,
    this.saving = false,
    this.saved = false,
  });

  final String sample;
  final List<SampleToken> tokens;

  /// Inclusive token index range being picked, or null.
  final (int, int)? selection;
  final Map<CustomTag, TagSpan> spans;
  final TemplateDirection direction;
  final String sender;
  final String channel;
  final List<String> history;
  final CustomTestReport? report;
  final TemplateSaveError? error;
  final bool saving;
  final bool saved;

  bool get hasSample => sample.trim().isNotEmpty;

  TemplateBuilderState copyWith({
    String? sample,
    List<SampleToken>? tokens,
    (int, int)? Function()? selection,
    Map<CustomTag, TagSpan>? spans,
    TemplateDirection? direction,
    String? sender,
    String? channel,
    List<String>? history,
    CustomTestReport? Function()? report,
    TemplateSaveError? Function()? error,
    bool? saving,
    bool? saved,
  }) => TemplateBuilderState(
    sample: sample ?? this.sample,
    tokens: tokens ?? this.tokens,
    selection: selection == null ? this.selection : selection(),
    spans: spans ?? this.spans,
    direction: direction ?? this.direction,
    sender: sender ?? this.sender,
    channel: channel ?? this.channel,
    history: history ?? this.history,
    report: report == null ? this.report : report(),
    error: error == null ? this.error : error(),
    saving: saving ?? this.saving,
    saved: saved ?? this.saved,
  );

  @override
  String toString() => 'TemplateBuilderState(<redacted>)';
}

class TemplateBuilderController extends Notifier<TemplateBuilderState> {
  @override
  TemplateBuilderState build() => const TemplateBuilderState();

  /// A fresh sample clears the tags (their offsets belong to the old text).
  void setSample(String sample, {String? sender, String? channel}) {
    state = TemplateBuilderState(
      sample: sample,
      tokens: tokenizeSample(sample),
      direction: state.direction,
      sender: sender ?? state.sender,
      channel: channel ?? state.channel,
      history: state.history,
    );
    _retest();
  }

  Future<void> useReviewSample(TemplateSample s) async {
    setSample(s.body, sender: s.sender, channel: s.channel);
    await _loadHistory();
  }

  Future<void> setSender(String sender) async {
    state = state.copyWith(sender: sender, error: () => null);
    await _loadHistory();
  }

  void setDirection(TemplateDirection d) {
    state = state.copyWith(direction: d, error: () => null);
    _retest();
  }

  /// Tap a word: the first tap starts a range, the second ends it; a tap
  /// with a range already picked starts a new one.
  void tapToken(int i) {
    if (i < 0 || i >= state.tokens.length) return;
    final sel = state.selection;
    if (sel == null || sel.$1 != sel.$2) {
      state = state.copyWith(selection: () => (i, i));
    } else {
      final a = sel.$1 < i ? sel.$1 : i;
      final b = sel.$1 < i ? i : sel.$1;
      state = state.copyWith(selection: () => (a, b));
    }
  }

  void clearSelection() => state = state.copyWith(selection: () => null);

  /// Gives the picked words to [tag] (replacing the tag's earlier span and
  /// any span the new one overlaps).
  void assign(CustomTag tag) {
    final sel = state.selection;
    if (sel == null) return;
    final start = state.tokens[sel.$1].start;
    final end = state.tokens[sel.$2].end;
    final next = <CustomTag, TagSpan>{
      for (final e in state.spans.entries)
        if (e.key != tag && (e.value.end <= start || e.value.start >= end))
          e.key: e.value,
    };
    next[tag] = TagSpan(tag, start, end);
    state = state.copyWith(
      spans: next,
      selection: () => null,
      error: () => null,
    );
    _retest();
  }

  void removeTag(CustomTag tag) {
    final next = {...state.spans}..remove(tag);
    state = state.copyWith(spans: next);
    _retest();
  }

  Future<void> _loadHistory() async {
    final sender = state.sender.trim();
    if (sender.isEmpty) {
      state = state.copyWith(history: const []);
      _retest();
      return;
    }
    try {
      final h = await ref
          .read(templateBuilderStoreProvider)
          .senderHistory(sender, state.channel);
      state = state.copyWith(history: h);
    } on Object {
      state = state.copyWith(history: const []);
    }
    _retest();
  }

  CustomTemplateBuild? _build() {
    if (!state.hasSample || !state.spans.containsKey(CustomTag.amount)) {
      return null;
    }
    if (!validSender(state.sender.trim())) return null;
    return buildCustomTemplate(
      sample: state.sample,
      spans: state.spans.values.toList(),
      direction: state.direction,
      sender: state.sender,
      channel: state.channel,
    );
  }

  void _retest() {
    final built = _build();
    final spec = built?.spec;
    state = state.copyWith(
      report: () => spec == null
          ? null
          : testCustomTemplate(spec, state.history, receivedAt: DateTime.now()),
    );
  }

  /// Gold only. Validates, builds, stores. Returns true when saved.
  Future<bool> save() async {
    if (state.saving) return false;
    if (!gateOrPaywall(ref, GoldCapability.customSmsRegex)) return false;
    if (!state.spans.containsKey(CustomTag.amount)) {
      state = state.copyWith(error: () => TemplateSaveError.amount);
      return false;
    }
    if (!validSender(state.sender.trim())) {
      state = state.copyWith(error: () => TemplateSaveError.sender);
      return false;
    }
    final built = _build();
    final spec = built?.spec;
    if (spec == null) {
      state = state.copyWith(error: () => TemplateSaveError.selfParse);
      return false;
    }
    state = state.copyWith(saving: true, error: () => null);
    try {
      await ref
          .read(templateBuilderStoreProvider)
          .saveTemplate(
            id: UlidGenerator().next(),
            sender: spec.sender,
            channel: spec.channel,
            template: spec.toJson(),
            sampleHash: sha256
                .convert(utf8.encode(foldKey(state.sample)))
                .toString(),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
      // The sample leaves memory with the state.
      state = const TemplateBuilderState(saved: true);
      try {
        await ref.read(customTemplateSavedHookProvider)();
      } on Object {
        // Re-parse is best effort; the next registry change retries it.
      }
      return true;
    } on Object {
      state = state.copyWith(
        saving: false,
        error: () => TemplateSaveError.failed,
      );
      return false;
    }
  }
}

final templateBuilderProvider =
    NotifierProvider.autoDispose<
      TemplateBuilderController,
      TemplateBuilderState
    >(TemplateBuilderController.new, name: 'templateBuilderProvider');
