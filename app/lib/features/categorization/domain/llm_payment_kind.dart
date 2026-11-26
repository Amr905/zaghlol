// T-357: what kind of payment a stored transaction is, for the auto-category
// eligibility rule (FR-LCAT-05 a/b, llm-categorise.md §2 rules 1–3). Pure
// Dart. Conservative: only a clear card / POS / online / wallet payment to a
// business is `businessPayment`; anything unclear is `unknown`, which the
// rule refuses. Nothing here logs.

import 'package:zaghlol_parsing/zaghlol_parsing.dart' show LlmPaymentKind;

/// Capture sources whose merchant field comes from a bank, wallet or
/// receipt, not from the user's own typing (manual, voice) or a file
/// (csv). Unknown codes are refused.
const Set<String> llmAutomatedSources = {
  'sms',
  'notification',
  'shortcut',
  'apple_pay',
  'share',
  'ocr',
  'pdf',
};

/// The payment kind of one stored row.
LlmPaymentKind llmPaymentKindOf({
  required String direction,
  required String source,
  required String? counterpartyKind,
  required bool isInternal,
  required bool hasTransferPair,
}) {
  if (isInternal || hasTransferPair) return LlmPaymentKind.transfer;
  switch (direction) {
    case 'transfer_out':
    case 'transfer_in':
      return LlmPaymentKind.transfer;
    case 'income':
      return LlmPaymentKind.income;
    case 'expense':
    case 'refund':
      break;
    default: // fee, or an unknown code
      return LlmPaymentKind.unknown;
  }
  if (counterpartyKind != null && counterpartyKind != 'merchant') {
    return LlmPaymentKind.transfer;
  }
  if (!llmAutomatedSources.contains(source)) return LlmPaymentKind.unknown;
  return LlmPaymentKind.businessPayment;
}
