// T-269: photos or screenshots of a bank statement. Each picked image is
// written to a temp file only long enough to be moved into the OCR host's
// encrypted spool, read by the on-device engine and deleted; the recognised
// lines go through the same table detector as a PDF.
//
// Privacy rules enforced here:
//  * Nothing leaves the phone: the only engine is the on-device [OcrEngine].
//  * The plain temp file is deleted in a `finally` whatever happens, and the
//    image bytes are zeroed once the file is written.
//  * Failures are typed [PdfExtractException]s; recognised text, paths and
//    file names never appear in an error.

import 'dart:io';
import 'dart:typed_data';

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/ocr/ocr_port.dart';

/// Most images read in one import.
const int statementImageMaxCount = 12;

/// Largest single image accepted.
const int statementImageMaxBytes = 25 * 1024 * 1024;

/// The page height OCR boxes are scaled to (any value works: lines are
/// grouped by relative position).
const int _imageHeightPoints = 1100;

abstract interface class StatementImageReader {
  /// Reads [images] in order (one page each). Zeroes the bytes it was given.
  Future<List<PdfTextFragment>> read(List<Uint8List> images);
}

class OcrStatementImageReader implements StatementImageReader {
  OcrStatementImageReader({
    required this.ocr,
    required this.tempDirectory,
    this.languages = const ['ar', 'en'],
  });

  final OcrEngine ocr;
  final Future<Directory> Function() tempDirectory;
  final List<String> languages;

  @override
  Future<List<PdfTextFragment>> read(List<Uint8List> images) async {
    if (images.isEmpty || images.length > statementImageMaxCount) {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    final out = <PdfTextFragment>[];
    try {
      for (var i = 0; i < images.length; i++) {
        if (out.length >= maxStatementFragments) break;
        out.addAll(await _readOne(images[i], i + 1));
      }
    } finally {
      for (final b in images) {
        b.fillRange(0, b.length, 0);
      }
    }
    if (out.isEmpty) throw PdfExtractException(PdfExtractFailureKind.noText);
    return out;
  }

  Future<List<PdfTextFragment>> _readOne(Uint8List bytes, int page) async {
    if (bytes.isEmpty || bytes.length > statementImageMaxBytes) {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    File? plain;
    try {
      final dir = await tempDirectory();
      plain = File(
        '${dir.path}/stmt_img_${DateTime.now().microsecondsSinceEpoch}_$page',
      );
      await plain.writeAsBytes(bytes, flush: true);
      final sealed = await ocr.sealImage(plain.path);
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
        pageHeightPoints: _imageHeightPoints,
      );
    } on PdfExtractException {
      rethrow;
    } on OcrException {
      // No OCR on this device, or it failed: the photo cannot be read.
      throw PdfExtractException(PdfExtractFailureKind.noText);
    } on Object {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    } finally {
      try {
        if (plain != null && plain.existsSync()) await plain.delete();
      } on Object {
        // Best effort; the OS clears the temp directory.
      }
    }
  }
}
