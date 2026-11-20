# Support and operator runbook (T-137)

Owner: the support lead. Scope: the v1 operator tooling (`zaghlol-ops`, D-37) and the interim support path for Gold seat moves (D-52, D-54, D-56, D-57, D-64, R4-6, R4-7, R5-5, R6-1). The contract is `backend/openapi/zaghlol-v1.yaml` (tag Admin) and `docs/03-technical/backend-api.md` section 5.3. Design of the CLI: `docs/03-technical/design-notes/T-137.md`. Privacy-notice and store-disclosure requirements that this path adds: `docs/ops/privacy-disclosures.md`.

Items marked **PO to confirm** are decisions that are still open. They are written down here so nobody has to guess; they are not decided by this document.

## 1. Roles

| Role | Who | What it allows |
|---|---|---|
| `support_viewer` | support staff | `support lookup` (read-only, audited) |
| `support_agent` | named support staff only | `support move`, `support detach` (audited, ownership check live) |
| `support_lead` | named support leads only | `support unfreeze` (audited, ownership check live); reviews and takes escalated tickets |
| `catalog_editor`, `flags_admin`, `prices_admin` | the people who run the catalog, flags and prices | the matching commands in section 2 |

Rules: roles are assigned to named people only, never to a shared or service account (R3-9). Operators are created by running `backend/deploy/db/seed-operator.sql` as `migrator` with the person's IdP `sub`; changes take effect within 30 seconds. An agent who looks users up also needs `support_viewer`. Roles are reviewed every quarter (section 9).

## 2. The tool: `zaghlol-ops`

### 2.1 Setup (once per workstation)
1. Install the build of `zaghlol-ops` for the OS (Windows, macOS, Linux).
2. Set the three public settings, as environment variables or in a JSON file (`--config FILE`, `ZAGHLOL_OPS_CONFIG`, or `~/.config/zaghlol-ops/config.json`; `%APPDATA%\zaghlol-ops\config.json` on Windows): `ZAGHLOL_OPS_API_URL` (`https://...`; a path such as `https://host/api/` is kept, so the CLI calls `https://host/api/admin/v1/...`), `ZAGHLOL_OPS_ISSUER` (the IdP issuer, `https`), `ZAGHLOL_OPS_CLIENT_ID` (the `zaghlol-ops` client). Values come from `docs/03-technical/operator-idp-setup.md` for the IdP chosen (**PO to confirm: Entra or Google, T-136 Q1**). Optional: `ZAGHLOL_OPS_SCOPES`, `ZAGHLOL_OPS_TOKEN_USE` (`id_token` is the default and the only choice for Google), `ZAGHLOL_OPS_REDIRECT_HOST` (`localhost`, or `127.0.0.1` if the IdP app is registered that way), `ZAGHLOL_OPS_TOKEN_CACHE` (`os` or `memory`), and `ZAGHLOL_OPS_CLIENT_SECRET` (environment only; needed only if Google's desktop client type asks for one, which Google does not treat as confidential). The file never accepts a secret.
3. Run `zaghlol-ops login`. The browser opens the IdP's page (authorization code with PKCE and a loopback redirect; there is no device-code flow). Complete the sign-in, with the security key for `support_agent` and `support_lead`.
4. Run `zaghlol-ops status`: it shows the settings, the token store in use and whether a token is stored. It never prints the token.

### 2.2 Where the token lives
The token (valid at most 60 minutes, no refresh token) is kept in the OS credential store: Windows Credential Manager, macOS Keychain, Linux Secret Service (`secret-tool`, needs `libsecret-tools` and a running keyring). If there is none (a headless server), it stays in memory for that run and you sign in again on the next one; the CLI says so once. It is never written to a file. Another program run by the same OS user can read the credential store, so do not run the tool on a shared or unlocked machine. `zaghlol-ops logout` deletes it; if the store does not confirm the delete, remove the `zaghlol-ops` entry by hand. The Windows and macOS stores are not exercised by the automated tests (only Linux is): on each new OS, the first operator runs `login`, then `status` from a second terminal, then `logout` and `status` again, and records that on the setup ticket.

### 2.3 Commands (every Admin operation has one)

| Command | Operation | Role |
|---|---|---|
| `catalog draft list <entity> [--all]` | adminListCatalogDraft | catalog_editor |
| `catalog draft create-merchant --canonical --name-ar --category` | adminCreateDraftMerchant | catalog_editor |
| `catalog draft put <entity> <key> --file F` (or `--merchant/--alias`, `--lang/--keyword`) | adminPutCatalogDraftEntry | catalog_editor |
| `catalog draft delete <entity> <key>` | adminDeleteCatalogDraftEntry | catalog_editor |
| `catalog import FILE [--dry-run]` | the put, create and delete calls above, in order, stop at the first failure | catalog_editor |
| `catalog publish [--note]` | adminPublishCatalog | catalog_editor |
| `contributions list`, `promote`, `reject` | adminListContributions, adminPromoteContribution, adminRejectContribution | catalog_editor |
| `bank-requests list` | adminListBankRequests | catalog_editor |
| `flags get <key>`, `flags set <key> --value ...` | adminGetFlag, adminPutFlag | flags_admin |
| `prices override ...` | adminOverridePrice | prices_admin |
| `support lookup --install UUID` or `support lookup --email` (the address is typed at a prompt, never on the command line, so it stays out of shell history and `ps`) | adminLookupEntitlement | support_viewer |
| `support move`, `support detach` | adminMoveSeat, adminDetachPurchase | support_agent |
| `support unfreeze` | adminUnfreezePurchase | support_lead |
| `metrics daily-active [--days N]` | adminDailyActive | any operator role |
| `login`, `logout`, `status` | none (local) | - |

Output is JSON on stdout. Errors are one line on stderr: `error: <HTTP status> <CODE>`, plus the server's title, detail, retry delay and a correlation id to quote in a ticket. Exit codes: 0 done, 1 the API refused (4xx/5xx other than 401/403), 2 a usage error (nothing was sent), 3 sign in again or the role is missing (401/403), 4 the API could not be reached. Run `zaghlol-ops <command> --help` for the options.

## 3. Ownership proof: the store order ID (D-57)

No support move, detach or unfreeze happens without a passing live check of the store order ID. The backend checks it with Google Play or the App Store and never stores it.

1. **Ask for the order ID of the latest receipt.** Google Play: the `GPA.` order number in the Play purchase e-mail or in Google Play, Account, Order history. App Store: the Order ID of the Apple receipt e-mail or in the purchase history. Ask for the **latest** receipt: where the backend can only compare against the purchase's current and chained orders, an old renewal order of the same subscription does not pass (backend-api 5.3).
2. **Where the order ID goes.** Only into the CLI's order-ID prompt. The three commands (`support move`, `support detach`, `support unfreeze`) have **no option and no environment variable for it**. They ask for it with the terminal's echo off, print nothing for what you type (not even stars), refuse to run if input is piped or redirected, and never write it to history, a file or the output. Paste or type it, then press Enter (Escape cancels). Check the arguments first: a mistake is reported before the sign-in and before the prompt.
3. **Never** put the order ID in the ticket's public text, a chat, a commit or a spreadsheet beyond what section 10 allows. If the user wrote it into the ticket or an e-mail, it is handled under the retention rule in section 10.
4. A failed check (`422 OWNERSHIP_CHECK_FAILED`) means the order does not belong to this purchase or is refunded; do not retry with guessed order IDs. Five failed checks by one operator in a day raise an alert (section 7). A store outage (`503`) is retried later.
5. The audit row records only that the check passed, failed or did not run, the ticket reference, the purchase and the install IDs. It never holds an e-mail, an order ID or free text. Use the ticket reference (`--ticket`) for the helpdesk ticket number; it is not free text.

## 4. Choosing who gets the seat (R4-7(3))

The target of a move (`--to`) must be one of the purchase's **pending claimants** (an install whose own restore or sign-in was refused only by the 30-day cooldown in the last 7 days; at most 3), or, for a correction, the install the seat was moved away from. The API does not list installs: the user gives their **support code** (the install ID shown in the app's help screen).

1. Look up each candidate's support code: `zaghlol-ops support lookup --install <code>`. The answer shows, per purchase, `seat` (`holder` or `claimant`), `isBuyingInstall`, `buyingInstallSilent`, `accountLinked` and `linkedBy`, and `disputeFrozenUntil`.
2. **Prefer the purchase's buying install** (`isBuyingInstall: true`, the install the store binding names) when several claimants could be the owner. Move to another claimant only when the buying install is not a claimant, is gone or silent (`buyingInstallSilent: true`), or the user's account of events shows it is not theirs; write the reason on the ticket.
3. For an account-linked purchase the target must be linked to the same account (`409 ADMIN_CONFLICT` otherwise).
4. Linking a purchase to an account (`--attach`) is allowed only when the purchase has no account, the target is linked to an account and the buying install is gone or silent for 30 days. Otherwise the owner links from the buying phone. A support link makes the buying phone show a one-time "linked by support" notice if it reappears; tell the user.
5. A move restarts the 30-day window and the losing install is told "moved by support" with the support contact. Say so to the user before you move.

## 5. Corrections, the dispute freeze and the unfreeze (D-64, R5-5, R6-1)

**Correction.** Any support move or link can be reversed:
- Move back: `zaghlol-ops support move --purchase P --to <the install the seat came from> --reason correction --corrects <audit id of the move> --ticket T`. The audit id is printed as `auditId` by the move.
- Remove a support link: `zaghlol-ops support detach --purchase P --ticket T --corrects <audit id of the attach>`. A link the owner made from the buying phone cannot be detached.
Corrections are allowed during a freeze.

**Freeze.** After a correction that moved the seat or detached a link, the purchase is frozen for 30 days (each correction restarts it): every other support move or link on it is refused (`409 ADMIN_CONFLICT`, audited as `dispute_frozen`, no store call) and raises an alert. The user's self-service restore and sign-in are not affected. `support lookup` shows `disputeFrozenUntil`.

**Unfreeze (R6-1, enforced by the server, PO decision).** Needed when an owner loses the phone during a freeze. A `support_lead` runs `zaghlol-ops support unfreeze --purchase P --ticket T`; the server then requires, in this order:
1. a running freeze (otherwise it changes nothing and audits `noop`);
2. a **different operator** than the one who made the correction that started the freeze and than the operator of the row that correction reversed, and **at least 24 hours** since that correction (otherwise `409`, audited `refused`);
3. a passing live ownership check;
and it only clears the freeze: no seat, link or window changes. After an unfreeze, the **unfreezing operator cannot make the next ordinary move** on that purchase for 24 hours; another `support_agent` can. A **second support lead checks the ticket within 2 business days** (alert `support_unfreeze`, section 7). If the freeze has no correction row the server cannot identify, it refuses (fails closed).

**Only one operator exists (break-glass).** With a single support operator the server always refuses the unfreeze, and there is no API bypass. The break-glass procedure, only when all of these hold: (a) the owner is a real, urgent case on a ticket, (b) the lead has checked the order in the store console (Google Play Console order management or App Store Connect), (c) the **product owner** (a person other than the requesting operator) approves on the ticket. Then a database administrator runs `backend/deploy/db/break-glass-unfreeze.sql` as `migrator` with the purchase UUID, the ticket reference and the requesting operator's IdP `sub`. It clears the freeze only, writes one `support_unfreeze` audit row marked `break_glass: true`, and starts the same 24-hour lock for that operator. It raises no alert by itself: the lead posts the ticket in the support-lead channel the same day, and the second check of section 7 (`support_unfreeze`) applies. The order ID is checked by hand and never written down: the ticket records "order checked in the store console by <name>, passed". Record each use in the quarterly review (section 9). Hiring a second named support lead removes the need for this procedure.

**R5-5(a) residual: correction ping-pong under single-agent support.** One agent can move a seat, correct it, and move again, and each correction restarts the freeze; the freeze alone does not stop an agent who alternates moves and corrections between the same two installs. It is accepted and contained by alerts and review, not by the API: the `support_moves_per_purchase_90d` alert (more than 2 support moves for one purchase in 90 days) sends a lead other than the acting agent to review the tickets and audit rows within 2 business days; `dispute_frozen_refusal` hands the ticket to a lead; `support_actions_per_operator_day` (more than 20 actions by one operator in a day) suspends the role; each move also costs the user the 30-day window. A lead who finds error or abuse reverses it through the correction path and writes the finding on the ticket.

## 6. IdP control record: phishing-resistant MFA (R4-6)

The API cannot prove FIDO2 from every IdP's token, so the **IdP's conditional-access policy is the control**, and this table records it. Fill it in when the IdP is chosen and re-check it in each quarterly review.

| Item | Value |
|---|---|
| Identity provider | **PO to confirm** (Entra ID or Google Workspace, T-136 Q1) |
| Policy name and where it lives | to record at setup |
| Scope | the `zaghlol-ops` and admin-app clients; the group of `support_agent` and `support_lead` holders |
| Requirement | phishing-resistant MFA (security key or passkey). Entra: an authentication-strength policy, ideally bound to an authentication context so the token carries `acrs`. Google: security-key-only 2-Step Verification for the support organisational unit |
| API check | `OperatorAuth:PhishingResistantMode`: `Enforced` (Entra with `RequiredAcrs`) or `Advisory` (Google; Entra without a context). In Advisory the alert `ZaghlolOperatorPhishingResistantMfaUnproven` counts requests without the proving claim |
| Evidence | screenshot or export of the policy, stored with the T-136 evidence |
| Last checked, by whom | at each quarterly review |

If the policy is removed or narrowed, treat all `support_agent` and `support_lead` sessions as unprotected: suspend those roles until it is restored.

## 7. Alerts: one action each

Alert rules are in `backend/deploy/observability/alerts/seats.yaml`. Alerts carry a purchase or operator UUID, never an order ID, token or install ID. Find the matching log line with the `log_query` of the alert.

| Alert (`rule` or alert name) | Meaning | Action |
|---|---|---|
| `support_moves_per_purchase_90d` (`ZaghlolAuditSupportMovesPerPurchase90d`) | More than 2 support moves for one purchase in 90 days | A support lead **other than the acting agent** reviews the tickets and audit rows within 2 business days; if they find error or abuse they reverse it through the correction path and record the finding |
| `support_actions_per_operator_day` (`ZaghlolAuditSupportActionsPerOperatorDay`) | More than 20 support actions by one operator in a day | **Suspend that operator's `support_agent` role** until reviewed (set `disabled_at` or remove the role, section 9) |
| `ownership_failures_per_operator_day` (`ZaghlolAuditOwnershipFailuresPerOperatorDay`) | More than 5 failed ownership checks by one operator in a day | Review the operator's recent actions and tickets for social-engineering attempts |
| `dispute_frozen_refusal` (`ZaghlolAuditDisputeFrozenRefusal`) | A move or link was refused by the freeze | **The support lead takes the ticket** (D-64) |
| `support_unfreeze` (`ZaghlolAuditSupportUnfreeze`) | A `support_unfreeze` call was made (or a break-glass run was reported) | **A second support lead checks the ticket within 2 business days** (R5-5(b)); an unfreeze followed by a move is also reviewed under the more-than-2-moves rule |
| `seat_rebind_over_cap` (`seat_rebind`) (`ZaghlolAuditSeatRebindOverCap`) | An over-cap same-iPhone rebind (D-63, D-65(a)) | Check the purchase's events for a relay pattern (rebinds alternating between the same installs); if found, note it on any ticket for that purchase. No automatic action |
| `ZaghlolMoveCooldownSpike` | `MOVE_COOLDOWN` refusals above 3 times the 7-day hourly baseline | Look for one channel or one app version causing repeated move attempts; open a defect if it is a release problem |
| `ZaghlolAttestationFailureSpike` | Attestation failures spiking for one platform and reason | By reason: `hash_mismatch` or `app_unrecognized` points to a release problem (check the latest build's hashes); `replayed` or `chain` points to an attack (look for one source) |
| `ZaghlolPlayIntegrityQuotaHigh` | Play Integrity calls above 50 % of the daily quota | Request a quota increase in Google Play Console, or reduce restore attempts |
| `ZaghlolSupportLookupVolume` | More than 60 support lookups in an hour | Check the audit log (`support_lookup`) for who ran them and confirm each matches a ticket |
| `ZaghlolOperatorPhishingResistantMfaUnproven` | Requests from `support_agent` or `support_lead` without the proving claim (Advisory mode) | Confirm the IdP policy of section 6 still covers the group |

## 8. Daily practice
- One ticket per action; its number goes into `--ticket`. The ticket records who asked, what proof was checked and which of the section 4 rules applied, but not the order ID after the action (section 10).
- Look up before you act: `support lookup` shows what the server holds (status, seat, link, freeze). Do not ask users for tokens or other installs' IDs; the lookup returns none.
- Read the answer of every write: `moved`, `attached`, `detached`, `unfrozen`, `nextMoveAt`, `auditId`. Note `auditId` on the ticket; a correction needs it.
- If a command fails, do not retry blindly: `409 ADMIN_CONFLICT` is a rule (freeze, gate, account), `422` a failed proof, `503` a store outage (retry later), `401` a lapsed sign-in (`zaghlol-ops login`).

## 9. Quarterly review of operator roles (R3-9, R6-1)

Every quarter the support lead and the product owner review the operator list and record the result (a dated ticket or page, kept with the IdP evidence). Run it as `migrator` (the schema owner, by the database administrator), because the read-only login `zaghlol_ops_ro` is break-glass only and has no credentials until T-140 decides the read path (when it does, use that):

```sql
SELECT id, display_name, roles, disabled_at FROM zaghlol.operators ORDER BY display_name;
-- holders of both support roles:
SELECT id, display_name FROM zaghlol.operators
 WHERE 'support_agent' = ANY(roles) AND 'support_lead' = ANY(roles) AND disabled_at IS NULL;
```

Checklist:
1. Every `support_agent` and `support_lead` is a **named, current member of staff**; no shared or service accounts. Remove leavers: `UPDATE zaghlol.operators SET disabled_at = now() WHERE oidc_subject = '<sub>'` as `migrator` (takes effect within 30 seconds; the row and its audit history stay).
2. **Record which operators hold both `support_agent` and `support_lead`** (the second query) and why. The server (R6-1) already stops one operator from unfreezing a purchase they froze or whose move they made, and from redoing the protected move within 24 hours, so holding both roles is allowed; the PO chose the server-side rule over disjoint roles. If the PO later chooses disjoint roles, the two assignments must be disjoint and this review enforces it.
3. Everyone who holds a support role is covered by the IdP policy of section 6; re-check the policy itself.
4. Count of operators with `support_lead`: if fewer than 2, the unfreeze depends on break-glass (section 5); list each break-glass use since the last review.
5. Audit-row spot check: pick five `support_seat_move`, `support_detach` and `support_unfreeze` rows and match each to a ticket.
6. Last quarter's alerts: every one has the action of section 7 recorded.

## 10. Helpdesk, PDPL and retention (OQ-16)

A support ticket links the **support code** (install ID) and the **order ID** to the user's contact details in the helpdesk tool. The privacy notice says so (`docs/ops/privacy-disclosures.md`, item 5).

| Item | State |
|---|---|
| Helpdesk vendor | **PO to confirm.** Not chosen; none is assumed here |
| Is the vendor a processor under the Egyptian PDPL (does it process personal data on Zaghlol's behalf)? | **PO to confirm**, with the legal advice on the PDPL licence (BLK-04, OQ-16). If it is a processor, a processing agreement is signed **before** any real ticket is handled in it; until then tickets are handled only in the channel the PO names |
| Region and sub-processors of the vendor | **PO to confirm**, recorded with the agreement |
| Retention rule for order IDs (applies whatever the vendor) | An order ID is kept **no longer than the ticket needs**: once the support action has passed or failed, the agent deletes or redacts every message and attachment that contains it **the same working day**, and in any case when the ticket is closed. The ticket keeps the ticket reference, the purchase UUID, the audit id and the outcome |
| Retention of the ticket itself | **PO to confirm** (a proposed default is to delete or anonymise a closed ticket 90 days after it closes; this is a proposal, not a decision) |
| Who can see tickets | Support staff with a named account only; no shared logins |

Until the PO confirms the vendor and its PDPL status, the retention rule for order IDs above still applies in full.

## 11. Records this runbook expects
- The IdP control record (section 6) and its evidence.
- The quarterly review (section 9) of every quarter.
- Each break-glass use (section 5): ticket, approver, date, operator.
- The helpdesk decision (section 10) once the PO makes it.
