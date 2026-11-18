// T-156: [PdfTextExtractor] over pdfrx (PDFium, MIT). The file is opened
// from memory: no temp file, no network. The password reaches PDFium once
// and is not kept. Text and geometry are returned to the caller only.

import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

/// Largest file read, and most pages (a hostile file cannot exhaust memory).
const int pdfMaxBytes = 32 * 1024 * 1024;
const int pdfMaxPages = 200;

class PdfrxTextExtractor implements PdfTextExtractor {
  const PdfrxTextExtractor();

  @override
  Future<List<PdfTextFragment>> extract(
    Uint8List bytes, {
    String? password,
  }) async {
    if (bytes.isEmpty || bytes.length > pdfMaxBytes) {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    PdfDocument? doc;
    try {
      var offered = false;
      doc = await PdfDocument.openData(
        bytes,
        // The empty password is tried first by the library. After that the
        // supplied password is offered once, then the open gives up.
        passwordProvider: () {
          if (offered || password == null) return null;
          offered = true;
          return password;
        },
      );
      final out = <PdfTextFragment>[];
      final pages = doc.pages.length > pdfMaxPages
          ? doc.pages.sublist(0, pdfMaxPages)
          : doc.pages;
      for (final page in pages) {
        final text = await page.loadStructuredText();
        for (final fr in text.fragments) {
          if (out.length >= maxStatementFragments) break;
          out.add(
            PdfTextFragment(
              page: page.pageNumber,
              text: fr.text,
              x0: (fr.bounds.left / page.width * 1000).round(),
              x1: (fr.bounds.right / page.width * 1000).round(),
              y: (page.height - (fr.bounds.top + fr.bounds.bottom) / 2).round(),
            ),
          );
        }
      }
      if (out.isEmpty) {
        throw PdfExtractException(PdfExtractFailureKind.noText);
      }
      return out;
    } on PdfPasswordException {
      throw PdfExtractException(
        password == null
            ? PdfExtractFailureKind.passwordRequired
            : PdfExtractFailureKind.wrongPassword,
      );
    } on PdfExtractException {
      rethrow;
    } on Object {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    } finally {
      await doc?.dispose();
    }
  }
}
