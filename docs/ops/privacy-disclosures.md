# Privacy-notice and store-disclosure requirements (T-137)

Source: `docs/03-technical/security-model.md` section 2a (D-62, R4-7(2), R4-8, R4-2, R5-7). This page is the checklist for the writers of the in-app notice ("What Zaghlol's server knows about you", FR-ONB-07, T-028 and T-162), the Google Play data-safety form (T-176) and the App Store privacy details (T-177). The copy itself is UX-owned (`docs/02-design/06-voice-and-tone.md`: Egyptian colloquial summary, standard Arabic for the legal text).

Each item must be stated in plain words. A release that leaves one out does not pass review.

| # | Disclosure | What must be said | Platform | Notice / form |
|---|---|---|---|---|
| 1 | Same-iPhone seat keys (D-62) | On iPhone, restore and sign-in send a key proof from this install and from up to 4 earlier Zaghlol installs on the same iPhone, so the server can tell those installs were on the same iPhone. The server keeps only a keyed-hash (scrambled) form, per purchase and per install, and never logs the keys | iOS (the in-transit linkability goes in the App Store privacy details) | T-028, T-162, T-177 |
| 2 | "Delete everything" on iPhone (R4-8) | It keeps the seat keys on the phone, so Gold can come back to this iPhone without using the monthly move. The server keeps a keyed hash of the key with the purchase until the purchase is deleted. Erasing the iPhone removes the keys | iOS | T-028, T-162, T-177 |
| 3 | Time nonce (R4-2) | Some requests carry a random one-time number used to check the time. It contains nothing about the phone or the user and is not stored | both | T-028, T-162, T-176, T-177 |
| 4 | Support links (R4-7(2), R5-7) | If support links Gold to an account, the phone that bought it is told when it next connects. The server repeats the notice until that phone's next sync proves it stored it, so a lost response does not lose it | both | T-028, T-162, T-176, T-177 |
| 5 | Helpdesk link (OQ-16) | When you contact support, your support code (the install ID) and the store order ID you give are linked to your contact details in our helpdesk tool. Order IDs are deleted from the ticket once the request is done. The vendor, its PDPL status and the ticket retention period are open (**PO to confirm**, `docs/ops/support-runbook.md` section 10); the notice and the data-safety forms must name the final values before release | both | T-028, T-162, T-176, T-177 |

Notes:
- Item 5 is not in security-model section 2a; it comes from the helpdesk decision in the runbook and must be reflected in the same notice. Do not state a vendor, a country or a retention period in copy until the PO has confirmed them.
- The support path never gives the server an order ID to keep: the backend checks it live with the store and does not store it (D-57). Say "we do not keep it" only about the server database, not about the helpdesk.
- Never write "no server" in copy; the claim is "your financial data never leaves your phone" (CLAUDE.md section 9).
- Copy for items 1 to 4 is generated from the same allow-list as the screen (security-model section 2 item 5), so the notice and the forms cannot drift apart.
