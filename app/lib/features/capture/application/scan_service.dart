// T-161 (S-32): image or shared text to a [ScanDraft]. OCR text and parse
// results are financial data: never logged, never put in an error; every
// failure is a code. The OCR host deletes the image file itself.

import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';
import '../domain/scan_draft.dart';
import 'scan_diagnostics.dart';

sealed class ScanOutcome {
  const ScanOutcome();
}

final class ScanFound extends ScanOutcome {
  const ScanFound(this.draft);
  final ScanDraft draft;
}

/// The image gave (almost) no text: nothing to read.
final class ScanNoText extends ScanOutcome {
  const ScanNoText();
}

/// Text was read but holds no total. [merchant] and [date] are what could
/// still be read, to prefill manual entry.
final class ScanNoTotal extends ScanOutcome {
  const ScanNoTotal({this.merchant, this.date});
  final String? merchant;
  final CivilDate? date;

  @override
  String toString() => 'ScanNoTotal(<redacted>)';
}

/// No OCR on this phone (yet).
final class ScanUnavailable extends ScanOutcome {
  const ScanUnavailable();
}

/// OCR or the file failed; [code] is a fixed code only.
final class ScanFailed extends ScanOutcome {
  const ScanFailed(this.code);
  final OcrFailureCode code;
}

final class ScanService {
  ScanService({
    required this.engine,
    required this.pipeline,
    required this.wallClock,
    this.diagnostics,
  });

  /// Outcome counters for dev builds; null records nothing.
  final ScanDiagnostics? diagnostics;

  /// Fewer letters and digits than this is "no text" (the OCR read noise).
  static const int minReadableChars = 10;

  final OcrEngine engine;
  final ParsingPipeline pipeline;

  /// The phone's wall clock as a UTC-flagged [DateTime] (parser convention).
  final DateTime Function() wallClock;

  /// True when the engine can read at least one language.
  Future<bool> isAvailable() async {
    try {
      return (await engine.supportedLanguages()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Reads the image at [encryptedPath] (a spool path the host owns) and
  /// parses its text. Never throws.
  Future<ScanOutcome> scanImage(String encryptedPath) async {
    final OcrOutcome ocr;
    try {
      ocr = await engine.recognize(encryptedPath);
    } on OcrException catch (e) {
      if (e.code == OcrFailureCode.notAvailable) {
        return const ScanUnavailable();
      }
      diagnostics?.record(ScanCounter.ocrFailed);
      return ScanFailed(e.code);
    } on Object {
      diagnostics?.record(ScanCounter.ocrFailed);
      return const ScanFailed(OcrFailureCode.ocrFailed);
    }
    final text = ocr.fullText;
    if (!_readable(text)) {
      diagnostics?.record(ScanCounter.noText);
      return const ScanNoText();
    }
    final result = pipeline.parseOcr(text, wallClock());
    final draft = scanDraftFromParse(result, ScanOrigin.image);
    return draft == null ? _noTotal(text) : _found(draft);
  }

  ScanOutcome _found(ScanDraft draft) {
    diagnostics?.record(
      draft.templateId == receiptFallbackTemplateId
          ? ScanCounter.foundFallback
          : ScanCounter.foundLabel,
    );
    return ScanFound(draft);
  }

  ScanOutcome _noTotal(String text) {
    diagnostics?.record(ScanCounter.noTotal);
    final h = pipeline.readOcrHints(text);
    final d = h.date;
    return ScanNoTotal(
      merchant: h.merchant?.display,
      date: d == null ? null : CivilDate(d.year, d.month, d.day),
    );
  }

  static bool _readable(String text) {
    var n = 0;
    for (final r in text.runes) {
      if ((r >= 0x30 && r <= 0x39) ||
          (r >= 0x41 && r <= 0x5A) ||
          (r >= 0x61 && r <= 0x7A) ||
          (r >= 0x0621 && r <= 0x064A) ||
          (r >= 0x0660 && r <= 0x0669)) {
        if (++n >= minReadableChars) return true;
      }
    }
    return false;
  }

  /// Parses shared text like a pasted message: the share channel first (the
  /// generic reader), then the screen templates for text copied from an app.
  ScanOutcome scanText(String text) {
    final now = wallClock();
    var result = pipeline.parse(
      ParseRequest(
        body: text,
        source: '',
        channel: RegistryChannel.share,
        receivedAt: now,
      ),
    );
    var draft = scanDraftFromParse(result, ScanOrigin.text);
    if (draft == null) {
      result = pipeline.parseOcr(text, now);
      draft = scanDraftFromParse(result, ScanOrigin.text);
    }
    if (draft != null) return _found(draft);
    if (!_readable(text)) {
      diagnostics?.record(ScanCounter.noText);
      return const ScanNoText();
    }
    return _noTotal(text);
  }
}
