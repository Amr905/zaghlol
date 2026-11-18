// T-156b: [PdfPageRasterizer] over pdfrx (PDFium). Pages are rendered from
// memory to a PNG in the app's temp directory, only for the on-device OCR
// that follows, and deleted by the caller right after. The password reaches
// PDFium once and is not kept. No network.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../application/scanned_pdf_text_extractor.dart';
import 'pdfrx_text_extractor.dart' show pdfMaxBytes, pdfMaxPages;

/// Width in pixels of a rendered page: about 190 dpi on a letter page, enough
/// for statement text without a large bitmap.
const int scanRenderWidth = 1600;

class PdfrxPageRasterizer implements PdfPageRasterizer {
  PdfrxPageRasterizer({Future<Directory> Function()? tempDirectory})
    : _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _tempDirectory;

  @override
  Future<PdfRasterSession> open(Uint8List bytes, {String? password}) async {
    if (bytes.isEmpty || bytes.length > pdfMaxBytes) {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    try {
      var offered = false;
      final doc = await PdfDocument.openData(
        bytes,
        passwordProvider: () {
          if (offered || password == null) return null;
          offered = true;
          return password;
        },
      );
      return _Session(doc, await _tempDirectory());
    } on PdfPasswordException {
      throw PdfExtractException(
        password == null
            ? PdfExtractFailureKind.passwordRequired
            : PdfExtractFailureKind.wrongPassword,
      );
    } on Object {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
  }
}

class _Session implements PdfRasterSession {
  _Session(this._doc, this._dir);
  final PdfDocument _doc;
  final Directory _dir;
  var _n = 0;

  @override
  int get pageCount =>
      _doc.pages.length > pdfMaxPages ? pdfMaxPages : _doc.pages.length;

  @override
  Future<RenderedPdfPage> render(int page) async {
    final p = _doc.pages[page - 1];
    final height = scanRenderWidth * p.height / p.width;
    final image = await p.render(
      fullWidth: scanRenderWidth.toDouble(),
      fullHeight: height,
      backgroundColor: 0xffffffff,
    );
    if (image == null) {
      throw PdfExtractException(PdfExtractFailureKind.unreadable);
    }
    ui.Image? decoded;
    try {
      decoded = await image.createImage();
      final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw PdfExtractException(PdfExtractFailureKind.unreadable);
      }
      // A neutral name: nothing of the document in the path.
      final file = File(
        '${_dir.path}/zsp_${DateTime.now().microsecondsSinceEpoch}_${_n++}.png',
      );
      await file.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      return RenderedPdfPage(path: file.path, heightPoints: p.height.round());
    } finally {
      decoded?.dispose();
      image.dispose();
    }
  }

  @override
  Future<void> close() => _doc.dispose();
}
