// T-156b: scanned statements. A PDF whose pages are pictures has no text
// layer, so [ScannedPdfTextExtractor] renders each page on the phone, reads
// it with the on-device OCR engine and hands the recognised lines, with their
// positions, to the same table detector as a text PDF.
//
// Privacy rules enforced here:
//  * Nothing leaves the phone: rendering is local and the OCR host is the
//    on-device engine behind [OcrEngine] (ML Kit + Tesseract on Android,
//    Vision on iOS). There is no network code in this file.
//  * A rendered page is a plain image of a bank statement. It exists only
//    between [PdfRasterSession.render] and the end of that page's OCR, and is
//    deleted in a `finally` whatever happens (the OCR host also deletes the
//    sealed copy). No path, text or file name is logged or put in an error.
//  * Failures are typed [PdfExtractException]s; recognised text is never in
//    a message.

import 'dart:io';
import 'dart:typed_data';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';

/// One rendered page: a PNG in the app's temp directory.
final class RenderedPdfPage {
  const RenderedPdfPage({required this.path, required this.heightPoints});
  final String path;

  /// The page height in PDF points (OCR boxes are relative to the page).
  final int heightPoints;

  @override
  String toString() => 'RenderedPdfPage';
}

abstract interface class PdfRasterSession {
  int get pageCount;

  /// Renders page [page] (1-based) to a temp PNG. The caller deletes it.
  Future<RenderedPdfPage> render(int page);

  Future<void> close();
}

/// Opens a PDF held in memory and renders its pages (pdfrx on the phone).
/// Throws [PdfExtractException] for a wrong or missing password and for an
/// unreadable file. The password is used once and not kept.
abstract interface class PdfPageRasterizer {
  Future<PdfRasterSession> open(Uint8List bytes, {String? password});
}

/// Most pages read by OCR in one import (each page takes seconds).
const int scannedPdfMaxPages = 30;

class ScannedPdfTextExtractor implements PdfTextExtractor {
  ScannedPdfTextExtractor({
    required this.textLayer,
    required this.rasterizer,
    required this.ocr,
    this.maxPages = scannedPdfMaxPages,
    this.languages = const ['ar', 'en'],
    Future<void> Function(String path)? deleteFile,
  }) : _delete = deleteFile ?? _deletePlain;

  final PdfTextExtractor textLayer;
  final PdfPageRasterizer rasterizer;
  final OcrEngine ocr;
  final int maxPages;
  final List<String> languages;
  final Future<void> Function(String path) _delete;

  static Future<void> _deletePlain(String path) async {
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  @override
  Future<List<PdfTextFragment>> extract(
    Uint8List bytes, {
    String? password,
  }) async {
    try {
      return await textLayer.extract(bytes, password: password);
    } on PdfExtractException catch (e) {
      // Only "no text layer" means "try the pictures"; a password problem or
      // an unreadable file is reported as it is.
      if (e.kind != PdfExtractFailureKind.noText) rethrow;
    }
    return _readByOcr(bytes, password);
  }

  Future<List<PdfTextFragment>> _readByOcr(
    Uint8List bytes,
    String? password,
  ) async {
    final PdfRasterSession session;
    try {
      session = await rasterizer.open(bytes, password: password);
    } on PdfExtractException {
      rethrow;
    } on Object {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    final out = <PdfTextFragment>[];
    try {
      final pages = session.pageCount < maxPages ? session.pageCount : maxPages;
      for (var p = 1; p <= pages; p++) {
        if (out.length >= maxStatementFragments) break;
        out.addAll(await _readPage(session, p));
      }
    } finally {
      try {
        await session.close();
      } on Object {
        // Nothing to do: the document is gone either way.
      }
    }
    if (out.isEmpty) {
      throw PdfExtractException(PdfExtractFailureKind.noText);
    }
    return out;
  }

  Future<List<PdfTextFragment>> _readPage(
    PdfRasterSession session,
    int page,
  ) async {
    RenderedPdfPage? image;
    try {
      image = await session.render(page);
      final sealed = await ocr.sealImage(image.path);
      final outcome = await ocr.recognize(sealed, languages: languages);
      return ocrLinesToFragments(
        [
          for (final l in outcome.lines)
            OcrLineBox(
              text: l.text,
              x0: (l.x * 1000).round(),
              x1: ((l.x + l.width) * 1000).round(),
              yCenter: ((l.y + l.height / 2) * 10000).round(),
            ),
        ],
        page: page,
        pageHeightPoints: image.heightPoints,
      );
    } on PdfExtractException {
      rethrow;
    } on OcrException {
      // No OCR on this device, or it failed: the scan cannot be read.
      throw PdfExtractException(PdfExtractFailureKind.noText);
    } on Object {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    } finally {
      final path = image?.path;
      if (path != null) {
        try {
          await _delete(path);
        } on Object {
          // Best effort; the OS clears the temp directory.
        }
      }
    }
  }
}
