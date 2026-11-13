// T-111: session state of the Ask Zaghlol chat (S-50). Held in memory for the
// session only: nothing is persisted, logged or sent anywhere, and the
// question text lives only in the bubble (and in the retry request) until the
// chat is cleared (FR-CHAT-03, CLAUDE.md §2.6).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../data/ask_providers.dart';
import '../domain/ask_models.dart';

/// Longest question the field accepts (S-50 validation).
const int askMaxQuestionChars = 300;

/// One bubble. A user bubble has [text]; a Zaghlol bubble has [answer] (or
/// is [system], a one-line note such as "roast mode on").
final class AskMessage {
  const AskMessage._({
    required this.id,
    this.text,
    this.answer,
    this.system,
    this.retry,
  });

  final int id;
  final String? text;
  final AskAnswer? answer;
  final AskSystemNote? system;

  /// How to ask again when [answer] is [AskUnavailableAnswer].
  final AskRequest? retry;

  bool get fromUser => text != null;

  @override
  String toString() => 'AskMessage(<redacted>)';
}

enum AskSystemNote { roastOn, roastOff }

/// A question to (re)ask: free text or a tapped chip.
final class AskRequest {
  const AskRequest.text(String this.question) : chip = null;
  const AskRequest.chip(AskChip this.chip) : question = null;

  final String? question;
  final AskChip? chip;

  @override
  String toString() => 'AskRequest(<redacted>)';
}

final class AskChatState {
  const AskChatState({
    this.messages = const [],
    this.thinking = false,
    this.roast = false,
  });

  final List<AskMessage> messages;
  final bool thinking;
  final bool roast;

  AskChatState copyWith({
    List<AskMessage>? messages,
    bool? thinking,
    bool? roast,
  }) => AskChatState(
    messages: messages ?? this.messages,
    thinking: thinking ?? this.thinking,
    roast: roast ?? this.roast,
  );
}

final askChatProvider = NotifierProvider<AskChatController, AskChatState>(
  AskChatController.new,
  name: 'askChatProvider',
);

class AskChatController extends Notifier<AskChatState> {
  int _nextId = 0;
  int _seed = 0;
  final Set<RoastKind> _recentRoasts = {};

  @override
  AskChatState build() => const AskChatState();

  /// True when [text] may be sent (1..300 characters after trimming).
  static bool isValid(String text) {
    final n = text.trim().length;
    return n >= 1 && n <= askMaxQuestionChars;
  }

  /// Sends a typed question. Returns false (and does nothing) when invalid
  /// or when an answer is still being worked out.
  Future<bool> sendText(String text) async {
    if (!isValid(text) || state.thinking) return false;
    final q = text.trim();
    await _run(q, AskRequest.text(q));
    return true;
  }

  /// Sends a tapped chip; [label] is the chip's text, shown as the user's
  /// bubble.
  Future<void> sendChip(AskChip chip, String label) async {
    if (state.thinking) return;
    await _run(label, AskRequest.chip(chip));
  }

  /// Asks again without a new user bubble (the error state's retry).
  Future<void> retry(AskMessage failed) async {
    final req = failed.retry;
    if (req == null || state.thinking) return;
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id != failed.id) m,
      ],
      thinking: true,
    );
    await _answer(req);
  }

  void setRoast(bool on) {
    if (on == state.roast) return;
    state = state.copyWith(
      roast: on,
      messages: [
        ...state.messages,
        AskMessage._(
          id: _nextId++,
          system: on ? AskSystemNote.roastOn : AskSystemNote.roastOff,
        ),
      ],
    );
  }

  void clear() {
    _recentRoasts.clear();
    state = AskChatState(roast: state.roast);
  }

  Future<void> _run(String bubble, AskRequest req) async {
    state = state.copyWith(
      messages: [
        ...state.messages,
        AskMessage._(id: _nextId++, text: bubble),
      ],
      thinking: true,
    );
    await _answer(req);
  }

  Future<void> _answer(AskRequest req) async {
    AskAnswer answer;
    try {
      final engine = await ref.read(askEngineProvider.future);
      final seed = _seed++;
      answer = req.chip != null
          ? await engine.askChip(
              req.chip!,
              roastSeed: seed,
              recentRoasts: {..._recentRoasts},
            )
          : await engine.ask(
              req.question!,
              roastSeed: seed,
              recentRoasts: {..._recentRoasts},
            );
    } on Exception {
      answer = const AskUnavailableAnswer();
    }
    if (answer is AskRoastAnswer) _recentRoasts.add(answer.fact.kind);
    state = state.copyWith(
      thinking: false,
      messages: [
        ...state.messages,
        AskMessage._(
          id: _nextId++,
          answer: answer,
          retry: answer is AskUnavailableAnswer ? req : null,
        ),
      ],
    );
  }
}
