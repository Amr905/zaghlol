/// Which card-purchase templates prove the payee is a business (B95-M1).
///
/// The queue filler treats a row as a business payment, and so skips the
/// business-word check of `LlmEligibility`, only when its template is in
/// [llmBusinessPurchaseTemplates]. The list is an explicit allowlist decided
/// template by template and it fails closed: a template that is in neither
/// set is not evidence. A registry-wide test fails when a card-purchase
/// template is added without a decision here.
///
/// Allowed: bank / issuer card notifications ("at" / "لدى" merchant) where
/// the payee is the merchant descriptor registered by the acquirer.
/// Refused: wallets, InstaPay, QR / "paid to" products and OCR text, where
/// the payee can be a private person.
library;

/// Card-purchase templates whose payee is a merchant by construction.
const Set<String> llmBusinessPurchaseTemplates = {
  'aaib.card_purchase.ar',
  'aaib.card_purchase.en',
  'abe.card_purchase.ar',
  'abe.card_purchase.en',
  'abk.card_purchase.ar',
  'abk.card_purchase.en',
  'adcb.card_purchase.ar',
  'adcb.card_purchase.en',
  'adib.card_purchase.ar',
  'adib.card_purchase.en',
  'aib.card_purchase.ar',
  'aib.card_purchase.en',
  'aibk.card_purchase.ar',
  'aibk.card_purchase.en',
  'al_baraka.card_purchase.ar',
  'al_baraka.card_purchase.en',
  'alexbank.card_purchase.ar',
  'alexbank.card_purchase.en',
  'alrajhi.card_purchase.ar',
  'alrajhi.card_purchase.en',
  'arab_bank.card_purchase.ar',
  'arab_bank.card_purchase.en',
  'arab_bank.card_trx.en',
  'arab_bank.debit_card_purchase.ar',
  'attijariwafa.card_purchase.ar',
  'attijariwafa.card_purchase.en',
  'bank_abc.card_purchase.ar',
  'bank_abc.card_purchase.en',
  'bank_nxt.card_purchase.ar',
  'bank_nxt.card_purchase.en',
  'banque_du_caire.card_purchase.ar',
  'banque_du_caire.card_purchase.en',
  'banque_misr.card_purchase.ar',
  'banque_misr.card_purchase.en',
  'banque_misr.card_purchase_fx.ar',
  'banque_misr.card_purchase_fx.en',
  'banque_misr.card_purchase_fx_charged.ar',
  'banque_misr.card_purchase_fx_charged.en',
  'blom.card_purchase.ar',
  'blom.card_purchase.en',
  'bunq.card_purchase.en',
  'cib.card_purchase.ar',
  'cib.card_purchase.en',
  'cib.card_purchase_fx.ar',
  'cib.card_purchase_fx.en',
  'cib.card_purchase_fx_charged.ar',
  'cib.card_purchase_fx_charged.en',
  'citibank.card_purchase.ar',
  'citibank.card_purchase.en',
  'citibank.card_purchase_limit.ar',
  'citibank.card_purchase_limit.en',
  'credit_agricole.card_purchase.ar',
  'credit_agricole.card_purchase.en',
  'ealb.card_purchase.ar',
  'ealb.card_purchase.en',
  'ebank.card_purchase.ar',
  'ebank.card_purchase.en',
  'egbank.card_purchase.ar',
  'egbank.card_purchase.en',
  'emirates_nbd.card_purchase.ar',
  'emirates_nbd.card_purchase.en',
  'enbd.card_purchase.ar',
  'enbd.card_purchase.en',
  'fabmisr.card_purchase.ar',
  'fabmisr.card_purchase.en',
  'faisal_bank.card_purchase.ar',
  'faisal_bank.card_purchase.en',
  'hdb.card_purchase.ar',
  'hdb.card_purchase.en',
  'hdfc.card_purchase.en',
  'hsbc.card_purchase.ar',
  'hsbc.card_purchase.en',
  'hsbc.card_purchase_limit.ar',
  'hsbc.card_purchase_limit.en',
  'hsbc.card_used_limit.en',
  'idb.card_purchase.ar',
  'idb.card_purchase.en',
  'kfh.card_purchase.ar',
  'kfh.card_purchase.en',
  'kfh.card_purchase_limit.ar',
  'kfh.card_purchase_limit.en',
  'liv.card_purchase.ar',
  'liv.card_purchase.en',
  'mashreq.card_purchase.ar',
  'mashreq.card_purchase.en',
  'mashreq.card_purchase_used.ar',
  'midbank.card_purchase.ar',
  'midbank.card_purchase.en',
  'monzo.card_purchase.en',
  'n26.card_purchase.en',
  'nbe.card_purchase.ar',
  'nbe.card_purchase.en',
  'nbe.card_purchase_fx.ar',
  'nbe.card_purchase_fx.en',
  'nbe.card_purchase_fx_charged.ar',
  'nbe.card_purchase_fx_charged.en',
  'nbk.card_purchase.ar',
  'nbk.card_purchase.en',
  'payoneer.card_purchase.en',
  'qnb.card_purchase.ar',
  'qnb.card_purchase.en',
  'qnb.card_purchase_fx.ar',
  'qnb.card_purchase_fx.en',
  'qnb.card_purchase_fx_charged.ar',
  'qnb.card_purchase_fx_charged.en',
  'saib.card_purchase.ar',
  'saib.card_purchase.en',
  'suez_canal_bank.card_purchase.ar',
  'suez_canal_bank.card_purchase.en',
  'united_bank.card_purchase.ar',
  'united_bank.card_purchase.en',
  'warba.card_purchase.ar',
  'warba.card_purchase.en',
  'wise.card_purchase.en',
  'wise.card_purchase_fx.en',
};

/// Card-purchase templates that are refused as evidence, with the reason.
const Map<String, String> llmRefusedPurchaseTemplates = {
  'arab_bank.account_purchase.ar': 'account debit, no merchant group',
  'cib.ocr_purchase.ar':
      'OCR of a screenshot, payee text not a bank descriptor',
  'cib.ocr_purchase.en':
      'OCR of a screenshot, payee text not a bank descriptor',
  'instapay.bill.ar': 'InstaPay (P2P-capable)',
  'instapay.bill.en': 'InstaPay (P2P-capable)',
  'myfawry.card_purchase.ar': 'Fawry wallet (wallet-to-person)',
  'myfawry.card_purchase.en': 'Fawry wallet (wallet-to-person)',
  'onebank_yalla.card_purchase.ar': 'digital wallet-style app, P2P-capable',
  'onebank_yalla.card_purchase.en': 'digital wallet-style app, P2P-capable',
  'orange_cash.card_purchase.ar': 'wallet',
  'orange_cash.card_purchase.en': 'wallet',
  'paytm.card_purchase.en': 'wallet / UPI pay-to-anyone',
  'revolut.card_purchase.en': '"paid to" is also P2P',
  'telda.card_purchase.ar': 'P2P-capable prepaid-card app',
  'telda.card_purchase.en': 'P2P-capable prepaid-card app',
  'vodafone_cash.bill.ar': 'wallet; payee of "paid to" can be a person',
  'vodafone_cash.ocr_payment.ar': 'wallet; payee of "paid to" can be a person',
  'vodafone_cash.ocr_payment.en': 'wallet; payee of "paid to" can be a person',
  'vodafone_cash.payment.ar': 'wallet; payee of "paid to" can be a person',
  'we_pay.card_purchase.ar': 'wallet',
  'we_pay.card_purchase.en': 'wallet',
};

/// Institution code of a template id (`code.name.lang`).
String templateInstitution(String templateId) {
  final i = templateId.indexOf('.');
  return i < 0 ? templateId : templateId.substring(0, i);
}

/// A refund template counts only when its purchase sibling is allowed: some
/// allowed card-purchase template of the same institution.
bool isBusinessRefundTemplate(
  String templateId,
  Set<String> allowedPurchaseTemplates,
) {
  final inst = templateInstitution(templateId);
  return allowedPurchaseTemplates.any((p) => templateInstitution(p) == inst);
}
