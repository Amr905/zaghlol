# Multi-currency: design options for the PO (2026-11-25)

Fixed rules (CLAUDE.md §2.4, SRS D-28/D-29): amounts are stored in their own currency, never converted silently; cross-currency sums are shown only as "≈" and labelled approximate.

| | Option A — Separate wallets | Option B — One home currency with "≈" | Option C — Hybrid (recommended) |
|---|---|---|---|
| Idea | Each currency is its own world: its own totals, budget and month view; a currency switcher on Home. | Everything is shown in EGP using a rate; the original amount sits underneath. | EGP is the main view; other currencies appear as small cards ("USD 189.66") that open their own view; one optional "≈ total in EGP" line. |
| Salary in USD | Income of the USD wallet. | Shown as ≈ EGP income at the day's rate. | Income in USD on its card; the month's "≈ income" line adds it at the day's rate, labelled approximate. |
| Budgets | Per currency. | In EGP only; foreign spending counts at the day's rate. | In EGP by default; a currency with real activity can get its own budget. |
| Exchange (USD → EGP) | A transfer between wallets with the rate the bank gave. | Not visible; hidden inside the totals. | A transfer pair; the EGP received becomes available to the EGP budget; no double income. |
| Rates | Not needed. | Needed daily (backend FX feed, already planned). | Needed only for the "≈" lines; missing rate → the line is hidden, nothing breaks. |
| Good | Always exact; simplest to trust. | One number to look at. | Exact where it matters, one glance where it helps. |
| Bad | No single picture of the month. | Totals move when the rate moves; easy to mistrust. | More screens to design. |
| Work | Small (most exists). | Medium; risky for trust. | Medium. |

Lead recommendation: **C**. It keeps every stored number exact, shows a USD salary as the salary it is, and counts money only once when it is exchanged to EGP.
Open questions for the PO: (1) when a USD salary is exchanged to EGP, should the month's EGP budget grow by the EGP received (recommended), or by the "≈" value on salary day? (2) which rate for "≈": the bank's rate from the SMS when present, else the daily feed (recommended)?
