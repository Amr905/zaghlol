# Public SMS wording search (T-031-public, 2026-11-18)

Goal: find publicly posted Egyptian bank / InstaPay / wallet / Fawry / BNPL SMS wording to check templates marked `synthetic-unverified`.

Result: **no verbatim SMS wording was found**, so no template was changed and none was re-marked `public-sample`. Inventing "public" wording would be worse than leaving the PO-sample-based templates as they are.

| Source (URL) | What it offers | Usable wording |
|---|---|---|
| https://www.egypt.hsbc.com/ways-to-bank/mobile/text-alerts/faq/ | Alerts are English only, sent above a per-product minimum | none (confirms HSBC EN-only) |
| https://ahli.com/article/short-message-service-sms-keep-track-of-your-transactions/?lang=ar | Lists alert types (salary, ATM/teller withdrawal, debit card purchase, reversal) | none |
| https://qnb.com/sites/qnb/qnbegypt/page/en/enportabank.html | PortaBank SMS content list | none |
| https://www.eg-bank.com/En/E_cardsTips | Advice to enable SMS, never share OTP | none |
| https://www.bankygate.com/43938/ | InstaPay statuses: successful / rejected / pending | none |
| https://mobilemasr.com/blogs/how-to-transfer-money-from-vodafone-cash | Says a text confirms a *9# transfer | none |
| https://almaal.org/كود-استلام-فودافون-كاش | ATM one-time PIN text; deposit confirmation | none |
| https://www.nbe.com.eg/AssetsManager/5ad00bdb-f1b2-4dcd-8da5-c054b5733906.pdf | Card-activation SMS mentioned | none |
| https://www.cibeg.com/en/personal/faqs?pageno=25 | page body empty | none |

Not found: any forum/Reddit/Facebook post quoting SMS text (searches returned only offers, fee and limit articles). Open-source trackers surfaced (pennywiseai, hisabi) cover other countries. Facebook/Reddit content is not reachable by the search tool.

Next step: real samples from the PO (OQ-04/18) remain the only reliable source. Confirmed from public pages: alert *types* per bank (salary, ATM, card purchase, reversal), which match existing event types; HSBC Egypt alerts are English only (check `hsbc.json` has no Arabic template that would be dead weight).
