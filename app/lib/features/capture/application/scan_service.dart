// T-161 (S-32): image or shared text to a [ScanDraft]. OCR text and parse
// results are financial data: never logged, never put in an error; every
// failure is a code. The OCR host deletes the image file itself.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';
import '../domain/scan_draft.dart';

sealed class ScanOutcome {
  const ScanOutcome();
}

final class ScanFound extends ScanOutcome {
  const ScanFound(this.draft);
  final ScanDraft draft;
}

/// Read fine, but no payment in it.
final class ScanEmpty extends ScanOutcome {
  const ScanEmpty();
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
  });

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
      return e.code == OcrFailureCode.notAvailable
          ? const ScanUnavailable()
          : ScanFailed(e.code);
    } on Object {
      return const ScanFailed(OcrFailureCode.ocrFailed);
    }
    final result = pipeline.parseOcr(ocr.fullText, wallClock());
    final draft = scanDraftFromParse(result, ScanOrigin.image);
    return draft == null ? const ScanEmpty() : ScanFound(draft);
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
    return draft == null ? const ScanEmpty() : ScanFound(draft);
  }
}
