# Automatic category for unknown merchants with an LLM — SRS addendum (LLM-CATEGORISE)

| | |
|---|---|
| Document | `docs/01-requirements/llm-categorise.md` (addendum to `requirements.md` §7.7a; sibling of `ask-llm.md`) |
| Version | 0.1 — DRAFT for PO review |
| Date | 2026-11-26 |
| Source | PO request 2026-11-26 02:36 (Cairo), `docs/workflow/PO_DECISIONS.md` row **LLM-CATEGORISE** |
| Decisions | **D-94** feature & data sent · **D-95** quota · **D-96** BR-SYNC-03 amendment & backend tables |
| Reuses | `ask-llm.md` v0.2: provider terms (FR-LLM-33/34), attestation (FR-LLM-14), rate limits (FR-LLM-15), spend cap (FR-LLM-16), install/account counting (FR-LLM-11), flag rules (FR-LLM-60/61), metrics (FR-LLM-62) |

IDs: **FR-LCAT-##**, **BR-LCAT-##**, **OQ-LCAT-##**. "Lead reading" = the Lead's interpretation of the PO's words, PO to confirm.

**PO's words (binding):** whenever a transaction has an unknown merchant, use the LLM to categorise it and send the category back; 15 auto-categorisations; a small feedback control beside it (correct / not correct); correct → saved to the database; not correct → sent to the backend into a different table for direct review; disabled by default, the app suggests it.

## 1. Trigger and what is sent

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-01 | **Trigger.** After local categorisation (BR-CAT-01: user rule > catalog > keyword > needs classification) ends in "needs classification" for an **eligible merchant** (FR-LCAT-05), and the feature is on (flag + consent, §5), quota is left and the phone is online, the merchant goes to the backend. One request per **distinct merchant**, never per transaction: the answer is kept on the phone as a merchant suggestion and applies to every past and future transaction of that merchant locally, free. | M |
| FR-LCAT-02 | **What is sent.** Only: a list of **normalised merchant name strings** (FR-PAR-05 cleaning + the contribution normalisation of `backend-api.md` §4.2, 2–64 chars, passing `ContributionPrivacy`), app language, **the request ID (ULID, so a retried batch is not counted twice), the version field (`v`), the consent terms the user agreed to (`consent {provider, v}`)**, app version, platform, install ID (+ account token if signed in) for the quota, and the attestation token (FR-LLM-14). *(FU-419, T-364: request ID, version field and consent terms were already in the contract `backend-api.md` §4.9 and are now listed here.)* **Never** amount, currency, date/time, institution, account, card, last-4, balance, SMS/notification text, counterparty, note, or the user's other categories/rules. | M |
| FR-LCAT-03 | **Batching.** Up to 20 merchants per request (remote `cat.batch_max`); the phone sends a batch when ≥ 1 is queued, at most once per 10 min while the app is open, and at app open. | M |
| FR-LCAT-04 | **Queue when it can't send.** Offline, backend down, over quota or `service_paused` → the transactions stay "needs classification" exactly as today. Eligible merchants wait in an encrypted local queue: **cap 100 distinct merchants**, each kept **60 days**, oldest dropped first; retried at next app open/online (BR-SYNC-02 back-off, ≤ 1 attempt/hour after a failure). Order when quota is short: most transactions first, then most recent. At the month's reset queued merchants are sent automatically (the user turned the feature on). Turning the feature off empties the queue. | M |

## 2. Eligibility: no person, no identifier (BR-SYNC-04 rules, made testable)

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-05 | A merchant is **eligible** only if all hold: (a) it comes from the **merchant** field of a card / POS / online / wallet **payment to a business** (expense or refund direction), not a counterparty; (b) the transaction is **not** a transfer (InstaPay, wallet P2P, bank transfer in/out, internal transfer), not an ATM/cash withdrawal, not salary/income; (c) no `person` counterparty kind (T-075 PO-3); (d) the string has no phone number (any 8+ digit run, `+20`/`01x` forms), no IBAN (`EG` + 27 digits, or any 2 letters + 2 digits + ≥ 10 alphanumerics), no `@`/handle/IPA, no e-mail, no URL, no run of ≥ 6 digits (incl. Arabic-Indic, after FR-PAR-04 folding); (e) it does **not look like a person's name**: after removing honorifics (أ/أستاذ/م/د/دكتور/حاج/Mr/Mrs/Ms/Dr/Eng), every remaining token (1–4 tokens) is in the bundled Egyptian given-name list (ar + en transliterations, ≥ 2,000 names, OQ-LCAT-05), unless a business word is present (e.g. صيدلية، مطعم، ماركت، كافيه، معمل، عيادة، شركة، مكتبة، pharmacy, restaurant, market, cafe, clinic, lab, store, co, ltd, llc); (f) not already sent (one send per merchant per install; a re-send only after the user deletes the suggestion and the merchant is unknown again). False positives (a shop named only «محمود») simply stay "needs classification". | M |
| FR-LCAT-06 | The eligibility check runs on the phone **before** queueing; the backend re-checks (d) with `ContributionPrivacy` and drops failures without calling the LLM, not counted. | M |

## 3. Backend behaviour

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-10 | **Catalog first.** For each merchant the backend looks it up in the published catalog (aliases, exact then fuzzy per FR-CAT-06 rules) and in the **LLM answer cache** (FR-LCAT-12). A hit returns that category with `source: catalog | cache`, **no LLM call and no quota used** (recommended default, OQ-LCAT-02). Note: a catalog hit here means the phone's catalog is behind; the app also triggers its normal sync later. | M |
| FR-LCAT-11 | **LLM, closed set.** Otherwise the backend asks the provider (same contract and identifier stripping as FR-LLM-33/34: only the fixed prompt, the merchant strings and the language) to choose **one system category code** from the live system list (FR-CAT-01, 16 codes, top level only) **or `unknown`**, with an integer confidence 0–100. The backend validates (code ∈ set, confidence in range); anything else → `unknown`. Reply per merchant: `{merchant, category, confidence, source}`. **No free text from the LLM reaches the app.** Custom categories are never offered to the LLM. | M |
| FR-LCAT-12 | **Answer cache.** LLM answers with confidence ≥ threshold are cached as `{merchantNorm, category, confidence, createdAt, hits}`, **no install ID or hash**, 90 days, so the same shop name costs one LLM call for everyone. A cached answer later contradicted by ≥ 3 corrections (FR-LCAT-31) is dropped. | S |
| FR-LCAT-13 | **Threshold.** Confidence < 60 (remote `cat.min_confidence`) or `unknown` → the phone treats it as no answer: the merchant stays "needs classification", marked "tried" (not re-sent), and **not counted** against quota. | M |
| FR-LCAT-14 | Reuses: attestation (FR-LLM-14), rate limits (FR-LLM-15; per install ≤ 2 requests/min, ≤ 30/day for this endpoint), the **shared** monthly provider spend cap (FR-LLM-16) with a per-feature alert, timeout 12 s and 5xx → queue kept, not counted (FR-LLM-51). | M |

## 4. On the phone: chip and feedback

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-20 | **Apply.** The suggested category is stored as a local **AI merchant suggestion** (merchant → category, state `unconfirmed`) and applied to that merchant's "needs classification" transactions and future ones. Precedence becomes: user rule > catalog > keyword > **AI suggestion** > needs classification. A later catalog sync that covers the merchant replaces an unconfirmed suggestion (FR-SYNC-05); it never replaces a confirmed one (that is a user rule). | M |
| FR-LCAT-21 | **Visible mark.** Wherever the category shows (transaction row, details, needs-classification queue, category drill-down), an unconfirmed suggestion carries a small "AI" chip («اقتراح زغلول» / "Zaghlol's guess") — icon + text, not colour only. | M |
| FR-LCAT-22 | **Two controls** beside the chip on transaction details and the queue: ✓ «صح» / "Right" and ✗ «مش صح» / "Wrong". Feedback is **per merchant** (applies to all its transactions); once given, the controls disappear for that merchant. | M |
| FR-LCAT-23 | **Right** → saved as a **user merchant rule** (FR-CAT-05/08, top precedence, never uploaded as a rule); suggestion state `confirmed`; a confirmation `{merchantNorm, category, source}` goes to the outbox (FR-LCAT-30). | M |
| FR-LCAT-24 | **Wrong** → category picker (system + the user's custom categories). On pick: saved as a user rule, applied to all that merchant's transactions, and a correction `{merchantNorm, aiCategory, userCategory}` goes to the outbox; a custom category is sent as `"custom"`, never its name. Picker cancelled → nothing changes (still unconfirmed). Undo (snackbar, 5 s) reverts both the rule and the outbox row. | M |
| FR-LCAT-25 | **No answer.** An unconfirmed suggestion counts in budgets, charts, safe-to-spend, Ask answers and exports **like any category** (recommended, OQ-LCAT-03), with the AI mark until confirmed. Exports add a column `category_source` = `ai_unconfirmed` / `user` / `catalog` / … | M |
| FR-LCAT-26 | Editing one transaction's category by hand (FR-TXN-02) changes that transaction only and asks the usual "always for this merchant?" (FR-CAT-05); "yes" counts as Wrong (correction sent) if it differs from the suggestion, Right if equal. | S |

## 5. Quota, off by default, discovery, consent

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-40 | **Quota:** **15 auto-categorisations per calendar month on Free** (PO "15"; per month is the Lead reading) and **150 on Gold** (proposed); Africa/Cairo calendar month; remote `cat.quota_free`, `cat.quota_gold`. One unit = one merchant **sent to the LLM whose answer is applied** (catalog/cache hits, `unknown`, low confidence, errors don't count). **Separate counter** from the 5/50 Ask-LLM questions. Counted by the backend per install and per account (FR-LLM-11 rules, Gold seat holder only, paused Gold = Free). A batch larger than what is left is trimmed by the backend to the remainder (in request order); the rest stays queued. | M |
| FR-LCAT-41 | **Shown:** Settings → Privacy row and the queue header show "12 of 15 left this month" (last backend reply; "—" before first contact); at 0: "Zaghlol will guess again on 1 December" + a non-intrusive Gold hint for Free (FR-GOLD-05 frequency rules). | M |
| FR-LCAT-42 | **Off by default.** Remote flag `llm_categorise` (default OFF, OFF after 14 days without sync, independent of `ask_llm`; added to the backend's closed flag set) **and** user consent are both required. Backend enforces the flag on every request (`service_paused`), the kill switch (FR-LLM-61 semantics). Flag off → no card, chip controls stay for existing suggestions (local), nothing sent. | M |
| FR-LCAT-43 | **Discovery.** A one-time suggestion card (Home feed or needs-classification queue) when the user has **≥ 3 distinct eligible uncategorised merchants**: «عندك ٣ محلات مش عارف أصنفها، تحب زغلول يخمّن؟» / "3 shops I couldn't sort — want Zaghlol to guess?". Frequency cap: at most once per 30 days, at most 3 times ever; "Not now" counts as a showing; "Don't ask again" stops it. A passive row in the queue header ("Let Zaghlol guess categories") is always available while off. Never a modal or push notification. | M |
| FR-LCAT-44 | **Consent sheet** before the first send: exactly what is sent — «اسم المحل بس — من غير المبلغ ولا التاريخ ولا الكارت ولا الرسالة» / "only the shop's name — no amount, date, card or message"; transfers and people's names are never sent; to whom (Zaghlol's server and the named AI provider); that shop names and your right/wrong answers are kept on our server **without anything that identifies you** to improve the catalog; the monthly limit. Stored as `cat.llm_consent` (encrypted settings). Revocable: Settings → Privacy switch «زغلول يخمّن التصنيف» / "Let Zaghlol guess categories"; off clears consent, empties the queue; local suggestions and rules stay. Cleared by "Delete everything". | M |

## 6. Privacy, BR-SYNC-03, backend tables

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-30 | **Feedback upload.** Confirmations and corrections travel in the existing **sync outbox** (daily, ≤ 50 per call, architect may share the `contributions` limit), not with the LLM request. The `llm_categorise` consent covers them; the D-16 contribution toggle is not needed (recommended, OQ-LCAT-04). | M |
| FR-LCAT-31 | **Two tables (PO).** `llm_cat_confirmations` {merchantNorm, category, source, install_hash, createdAt} and **separate** `llm_cat_corrections` (review table) {merchantNorm, aiCategory, userCategory or `custom`, source, install_hash, createdAt, status `open/promoted/rejected/prompt_issue`, operator, resolvedAt}. `install_hash` = KMS HMAC as in contribution intake (one vote per install per merchant, not reversible to the install ID, never joined with the quota counter); **no install ID, account, IP, app version**. Server re-runs `ContributionPrivacy`; failures dropped. | M |
| FR-LCAT-32 | **Promotion.** A merchant with **≥ 3 independent confirmations** of the same category (distinct `install_hash`, remote `cat.confirm_n`, OQ-LCAT-06) and no open correction appears in the contributions review queue (FR-BE-07) as "AI-confirmed"; an operator still promotes it (no automatic catalog change). | S |
| FR-LCAT-33 | **No logs:** merchant names never appear in request logs, traces, errors or metrics (FR-LLM-32 rule and test); quota counters hold only install/account + month + count, deleted after the following month. | M |
| FR-LCAT-34 | **Retention:** corrections: open until resolved, deleted 90 days after resolution or 180 days after creation, whichever first; confirmations: 365 days or at promotion/rejection; answer cache: 90 days. Stated in the privacy policy. | M |

**BR-SYNC-03 amendment (D-96), text to add:** *"(Auto-category, D-94…D-96) Only after the user's consent: normalised **merchant names** of card/online payments to businesses that the phone could not categorise (never transfers, people's names, phone numbers, IBANs, handles or any digits run ≥ 6), plus the app language; and the user's **right/wrong feedback** on a suggested category (merchant name, suggested and chosen system category, or "custom"). The backend may keep these without the install ID (a keyed install hash only to count independent votes) for catalog review, and a monthly counter per install/account for the quota. Never: amounts, dates, accounts, cards, messages, the user's rules or custom category names."* Store labels: Play Data safety "App activity → Other actions/user-generated content: collected, optional, not linked" and the App Store label to be confirmed by legal; privacy-consistency row when built.

## 7. Operator review

| ID | Requirement | Pri |
|---|---|---|
| FR-LCAT-50 | Operators (`catalog_editor`) review corrections through `zaghlol-ops` on new admin endpoints (shape by the architect; web admin later, D-37): list **grouped** by (merchantNorm, aiCategory, userCategory) with vote count and first/last seen, open first, sort by count; actions: **promote** (adds/updates the merchant in the catalog draft with the chosen category, then normal publish), **reject**, **mark prompt issue** (feeds the provider evaluation set). Every action audited (`audit_log`). No endpoint returns rows per install. | M |
| FR-LCAT-51 | Daily metrics (counts only, FR-LLM-62 style): requests, merchants sent, catalog/cache hits, LLM calls, `unknown`, low confidence, confirmations, corrections, correction rate per category, quota-limit hits, cost. | M |

## 8. Acceptance criteria (synthetic data)

| Req | Given / When / Then |
|---|---|
| FR-LCAT-01/02 | **Given** flag on, consent, 15 left, Ahmed pays **EGP 185.00** with CIB •••• 4321 at `ZAWYA COFFEE NASR CITY EG 0412` (not in catalog), **when** categorisation finds nothing, **then** one request is sent whose merchant list is `["zawya coffee"]`; the captured body/headers/URL contain no `185`, no `4321`, no `CIB`, no date, no SMS text (inspection test over the fixture set). |
| FR-LCAT-01 | **Given** the reply `dining`, 88, **then** that transaction and Ahmed's 2 earlier Zawya ones show Dining with the AI chip; a 4th Zawya payment next week is categorised locally with no request. |
| FR-LCAT-03 | 25 eligible merchants queued → 2 requests (20 + 5). |
| FR-LCAT-04 | Airplane mode → transaction stays «محتاج تصنيف», merchant queued; back online → sent once. 101st distinct queued merchant drops the oldest. |
| FR-LCAT-05 (excluded) | Not sent: InstaPay transfer to "Mohamed Ahmed Ali"; wallet transfer to «أحمد محمود»; «حاج سيد»; "01012345678"; "EG380019000500000000263180002"; "mona.s@instapay"; "REF 1234567"; ATM withdrawal; salary. **Sent:** "Dr Hany Clinic", «صيدلية الشفاء», "Koshary Abou Tarek". Table-driven test, ar + en. |
| FR-LCAT-10/40 | **Given** `talabat` is in the server catalog, **then** reply `source: catalog`, counter unchanged. **Given** `unknown` or confidence 40 → stays uncategorised, counter unchanged, not re-sent. |
| FR-LCAT-11 | Provider returns `"Food & Drinks"` or `"dining; also try groceries"` → backend replies `unknown`; with backend bypassed in test, the phone also rejects any code not in its system list. |
| FR-LCAT-22/23 | Ahmed taps «صح» on Zawya → user rule saved, chip gone on all 3 transactions, one confirmation row in outbox; after sync, `llm_cat_confirmations` holds `zawya coffee / dining` with an install hash, no install ID. |
| FR-LCAT-24 | AI said `groceries` for «مكتبة النور»; Ahmed taps "Wrong", picks Education → rule saved; one `llm_cat_corrections` row {`مكتبة النور`, groceries, education, open}. Picks his custom «كتب» → row has `custom`, no «كتب» anywhere in the body. Undo within 5 s → no row sent. |
| FR-LCAT-25 | Unconfirmed Dining suggestion of EGP 185.00 → counted in the EGP Dining budget and donut; export row `category_source = ai_unconfirmed`. |
| FR-LCAT-40/41 | Free install with 15 applied this November; on 30 Nov 23:50 Cairo a new merchant → not sent, queued, "guess again on 1 December"; 1 Dec 00:05 → sent. Batch of 5 with 2 left → 2 sent, 3 stay queued. Ask-LLM counter unchanged throughout. Gold seat holder → 150. |
| FR-LCAT-42/43/44 | Flag off → no card, no request. 2 eligible merchants → no card; 3rd → card once; dismissed → not shown again for 30 days, never after 3 showings. Consent "Not now" → nothing sent; Settings switch off → queue emptied, no request. Flag off at backend with stale app flag → `service_paused`, not counted. |
| FR-LCAT-33 | Backend integration test with a marker merchant name: absent from all logs, traces and metrics; present only in the cache/feedback tables. |
| A11y | ✓/✗ each ≥ 48×48 dp (44 pt iOS), separate targets ≥ 8 dp apart; labels «التصنيف ده صح» / "This category is right", «التصنيف ده غلط» / "This category is wrong"; AI chip announced «اقتراح من زغلول، لسه متأكدتش» / "Zaghlol's guess, not confirmed"; RTL order mirrored; 130 % text scale; result announced after tap. |

**Hide amounts (D-67):** not affected — no amount is sent or shown by this feature; screens it appears on keep masking as usual.

## 9. Decisions and open questions

| ID | Decision (proposed for PO approval) |
|---|---|
| D-94 | *(PO, 2026-11-26, LLM-CATEGORISE)* Unknown merchants of business payments may be categorised by an LLM: only the normalised merchant name (+ language) is sent after opt-in consent; closed set of system categories or `unknown`; one call per merchant, answer kept on the phone; AI chip with Right/Wrong; Right → local rule + confirmation; Wrong → local rule + correction to a separate review table. Off by default (`llm_categorise`), suggested once by a card. Transfers and person-like names never sent. Amends D-06/OOS-05 for this feature only. |
| D-95 | Quota: 15 per calendar month on Free (Lead reading of "15"), 150 on Gold (proposed); separate from the Ask-LLM 5/50; only applied LLM answers count; remote-configurable. |
| D-96 | BR-SYNC-03 amended (text §6); backend keeps an answer cache (90 d, no install data), `llm_cat_confirmations` and `llm_cat_corrections` (install HMAC only), operator review via `zaghlol-ops`. |

| ID | Question | Recommended default | Blocking? |
|---|---|---|---|
| OQ-LCAT-01 | Is "15" per calendar month (vs. 15 ever)? Gold 150? | 15/month Free, 150/month Gold | BLOCKING (copy, backend) |
| OQ-LCAT-02 | Catalog/cache hits free of quota? | Yes | NON-BLOCKING |
| OQ-LCAT-03 | Unconfirmed suggestions count in budgets/charts? | Yes, with AI mark | NON-BLOCKING |
| OQ-LCAT-04 | One consent for sending names **and** feedback (no D-16 toggle)? | Yes | NON-BLOCKING |
| OQ-LCAT-05 | Source of the Egyptian given-name list (licence) | Compile from public-domain lists; UX/legal check | NON-BLOCKING (build) |
| OQ-LCAT-06 | Confirmations needed before a merchant reaches operator review | N = 3 distinct installs | NON-BLOCKING |
| OQ-LCAT-07 | Shared provider spend cap with Ask-LLM? | Shared cap, per-feature alerts | NON-BLOCKING |
| OQ-LCAT-08 | Retention (§6 FR-LCAT-34) and store labels | As proposed; legal confirms with OQ-ASK-03 (provider region, PDPL) | BLOCKING for flag ON, not for build |
