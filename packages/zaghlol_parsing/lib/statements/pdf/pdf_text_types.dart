// T-156: what the PDF text extractor hands to the statement reader.
// Pure Dart: the pdfrx adapter lives in the app and maps into these types.
//
// Nothing here carries a path, a password or a document handle. Text from a
// statement is sensitive: no type prints it in `toString`.

import 'dart:typed_data';

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// One run of text on a page, with its position.
///
/// [x0] and [x1] are in permille of the page width (0..1000, left to right, rounded);
/// [y] is in whole points from the top of the page (larger = lower). Using the page
/// width as the unit keeps a saved column template valid across page sizes.
final class PdfTextFragment {
  const PdfTextFragment({
    required this.page,
    required this.text,
    required this.x0,
    required this.x1,
    required this.y,
  });

  final int page;
  final String text;
  final int x0;
  final int x1;
  final int y;

  int get center => (x0 + x1) ~/ 2;

  @override
  String toString() => 'PdfTextFragment';
}

enum PdfExtractFailureKind {
  /// The file is encrypted and no password was given.
  passwordRequired,

  /// A password was given and it does not open the file.
  wrongPassword,

  /// Not a readable PDF, or too large.
  unreadable,

  /// A PDF with no text layer (a scan). OCR is a different feature.
  noText,
}

final class PdfExtractException extends SafeException {
  PdfExtractException(this.kind)
    : super('PDF_EXTRACT_${kind.name.toUpperCase()}');
  final PdfExtractFailureKind kind;
}

/// Reads the text of a PDF held in memory. Implementations must not write
/// the bytes or the password anywhere and must not use the network.
abstract interface class PdfTextExtractor {
  /// Throws [PdfExtractException]. [password] is used once and not kept.
  Future<List<PdfTextFragment>> extract(Uint8List bytes, {String? password});
}
