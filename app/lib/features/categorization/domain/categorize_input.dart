// T-075: the categorizer input of one transaction's fields. Pure Dart (no
// Flutter, no Drift), so the ingest use case (T-046) and the re-categorizer
// build the input the same way. Moved here from `data/categorizer_ports.dart`
// (still re-exported there). Nothing here logs.

import 'package:zaghlol_parsing/zaghlol_parsing.dart'
    show CategorizeInput, PartyKind, cleanMerchant, foldKey;

/// The categorizer input of one transaction's stored fields. The merchant
/// key is the stored `merchant_norm`; the keyword text is derived from
/// `merchant_raw` (Arabic is lost in the key).
CategorizeInput categorizeInputFor({
  String? merchantRaw,
  String? merchantNorm,
  String? counterpartyKind,
  String? counterpartyValue,
}) {
  final cleaned = cleanMerchant(merchantRaw ?? '').cleaned;
  return CategorizeInput(
    merchantNorm: merchantNorm ?? '',
    merchantText: foldKey(cleaned),
    counterpartyKind: PartyKind.tryParse(counterpartyKind),
    counterpartyValue: counterpartyValue,
  );
}
