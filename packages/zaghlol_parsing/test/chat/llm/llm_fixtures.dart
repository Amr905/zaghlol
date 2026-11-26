// Synthetic sources for the T-278 tests (Ahmed fixture of SRS §10). Fake
// names, fake last-4s; nothing here is real user data.

import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const cib = MaskInstitution('cib', [
  MaskAlias('CIB'),
  MaskAlias('سي آي بي'),
  MaskAlias('Commercial International Bank'),
  MaskAlias('البنك التجاري الدولي'),
]);
const nbe = MaskInstitution('nbe', [
  MaskAlias('NBE'),
  MaskAlias('National Bank of Egypt'),
  MaskAlias('البنك الأهلي المصري'),
  MaskAlias('الأهلي', ordinaryWord: true),
]);
const misr = MaskInstitution('misr', [
  MaskAlias('Banque Misr'),
  MaskAlias('بنك مصر'),
  MaskAlias('مصر', ordinaryWord: true),
]);
const voda = MaskInstitution('voda', [
  MaskAlias('فودافون كاش'),
  MaskAlias('Vodafone Cash'),
]);
const liv = MaskInstitution('liv', [MaskAlias('Liv', ordinaryWord: true)]);
const wise = MaskInstitution('wise', [MaskAlias('Wise', ordinaryWord: true)]);

const cibCredit = MaskAccount(
  id: 'acc-cib-credit',
  label: 'CIB Platinum',
  institutionId: 'cib',
  type: MaskAccountType.creditCard,
  last4: '4321',
);
const nbeSavings = MaskAccount(
  id: 'acc-nbe-savings',
  label: 'NBE Main',
  nickname: 'حساب التوفير',
  extraNames: ['Savings'],
  institutionId: 'nbe',
  type: MaskAccountType.savings,
  last4: '8765',
);
const cibDebit = MaskAccount(
  id: 'acc-cib-debit',
  label: 'CIB Debit Gold',
  institutionId: 'cib',
  type: MaskAccountType.debitCard,
  last4: '1234',
);

const carrefour = MaskMerchant('carrefour', ['Carrefour', 'كارفور']);
const talabat = MaskMerchant('talabat', ['Talabat', 'طلبات']);
const spinneys = MaskMerchant('spinneys', ['Spinneys', 'سبينس']);

const ahmed = StaticMaskSources(
  accounts: [cibCredit, nbeSavings],
  institutions: [cib, nbe, misr, voda, liv, wise],
  merchants: [carrefour, talabat, spinneys],
);

/// Ahmed plus a second CIB card ending 1234.
const ahmedPlus1234 = StaticMaskSources(
  accounts: [cibCredit, nbeSavings, cibDebit],
  institutions: [cib, nbe, misr, voda, liv, wise],
  merchants: [carrefour, talabat, spinneys],
);

/// Scrub then mask, as the app does.
MaskOutcome pipeline(String question, MaskSources sources) =>
    ReferenceMasker.mask(ClientScrub.apply(question).text, sources);

/// The text a request would carry: the placeholdered text, or null when the
/// question stays on the phone.
String? sentTextOf(String question, MaskSources sources) {
  final o = pipeline(question, sources);
  return o is MaskResult ? o.sentText : null;
}
