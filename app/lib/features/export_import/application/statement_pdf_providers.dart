// T-156b: the PDF reader the statement import uses: the text layer first,
// on-device OCR for scanned files.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../capture/application/scan_providers.dart' show ocrEngineProvider;
import '../data/pdfrx_page_rasterizer.dart';
import '../data/pdfrx_text_extractor.dart';
import 'scanned_pdf_text_extractor.dart';

final statementPdfExtractorProvider = Provider<PdfTextExtractor>(
  (ref) => ScannedPdfTextExtractor(
    textLayer: const PdfrxTextExtractor(),
    rasterizer: PdfrxPageRasterizer(),
    ocr: ref.watch(ocrEngineProvider),
  ),
  name: 'statementPdfExtractorProvider',
);
