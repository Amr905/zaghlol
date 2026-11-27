# Google Play Data safety answers (draft, T-176)

Source of truth: `docs/03-technical/security-model.md` section 2 and 2a, SRS BR-SYNC-03. Rule used: Play counts only data **sent off the device** as collected; data processed only on the phone is not collected (Play Console Help, Data safety). So SMS and notification text, transactions, amounts, budgets, assets, contacts and location are **not collected**: they never leave the phone except in the user's own encrypted Drive backup or a user-initiated export (both user-initiated transfers to the user's own account; confirm with the form wording at submission).

Draft for the PO and legal to confirm in Play Console. Items marked (confirm) are classifications the form lets you argue either way.

## Overview questions

| Question | Answer |
|---|---|
| Does the app collect or share any of the required user data types? | Yes (the items below) |
| Is all collected data encrypted in transit? | Yes (TLS 1.2+ to the backend only; `BackendClient` is the only HTTP client). **No certificate pinning** (ADR-018, security-model §6): release builds trust system CAs only, and security-relevant responses are ES256-signed and verified against public keys embedded in the app. |
| Do you provide a way for users to request data deletion? | Yes: in-app account deletion (FR-ACCT-04) and "Delete everything"; support request for purchase-linked records. Privacy policy URL: `https://zaghlol.app/privacy` (draft in `site/privacy/`, pending legal review, FU-195-legal). |
| Data shared with third parties | **None** (no ads, analytics or crash SDKs). Google Play Billing and the user's own Drive are the platform / the user, not third-party sharing (confirm). The AI provider that receives Ask question text and auto-category shop names (only after the user's consent) acts as our service provider processing on our behalf, so the draft answer stays "not shared" (**confirm with legal**; if legal disagrees, the two LLM rows below become "shared"). |

## Data types collected (all: not shared, app functionality, collection required unless noted)

| Play category > type | What is sent | Optional? | Purpose | Notes |
|---|---|---|---|---|
| Device or other IDs > Device or other IDs | Anonymous install ID (random, not derived from the device); attestation token (Play Integrity, D-45) with a per-request random time nonce (R4-2) | Required for backend features | App functionality, fraud prevention / security | The attestation token carries no other device data (D-45). The time nonce is random, one-time, stored nowhere. |
| Financial info > Purchase history | Purchase tokens / transactions for Gold verification and restore | Required for Gold | App functionality | Gold is granted only by backend verification (constraint 2a). Order IDs are never sent by the app. |
| Personal info > Email address | Only through the optional sign-in ID token: **Google sign-in or Sign in with Apple** (on Android Apple's web flow, D-44, `scope=email`, D-49); carries Gold across platforms (ADR-016) | **Optional** | Account management | The server **stores** the token's `email` claim, if the provider returns one (Apple may return a private relay address), in `accounts.email` next to the provider subject ID, for support lookup only; it is deleted with the account (FR-ACCT-04). Support-lookup audit rows keep only a keyed pseudonym of it for 1 year (NFR-PRIV-07). |
| Personal info > User IDs (confirm) | The provider's account subject ID (`sub`) from the same optional ID token | **Optional** | Account management | Stored in `accounts.provider_subject` until the account is deleted. |
| App activity > Other user-generated content (confirm) | Merchant-name contributions: the normalized merchant text, the **institution code** (e.g. `nbe`) and the chosen system category (BR-SYNC-04), **only if the user opts in** (off by default), filtered on the phone and again on the server | **Optional** | App functionality (shared merchant catalog) | No amounts, dates, card digits, IPA or phone. |
| App activity > Other actions (confirm) | "Request my bank": institution name, country, channel type (FR-PAR-14), only when the user asks | **Optional** | App functionality | Never the message. |
| App info and performance | Platform, app version, catalog version, registry version | Required | App functionality | Classified by D-48 as "catalog/app version". |
| Messages > Other in-app messages (confirm, **legal to confirm**) | **Online helper (Ask Zaghlol, D-88…D-90):** the question the user typed, after the phone's scrub of phone numbers, e-mails, InstaPay addresses and card/account numbers and after known accounts, cards, banks and merchants are replaced by placeholders; the app language; a random request ID; the consent terms (provider id, consent version); the attestation (above). Sent to our backend, which forwards the text and language to the named AI provider. Alternative classification: App activity > Other user-generated content | **Optional** (off until the user consents; revocable in Settings) | App functionality | Our backend does not store or log the text (monthly counter only, per install and per account, kept to the end of the following month). The provider may keep requests up to 30 days for abuse monitoring until zero retention is granted. The text can contain anything the user types, including person names the phone does not tag and category, budget and goal names (OQ-ASK-11, PENDING PO). Claiming the "ephemeral processing" exemption (data held in memory only and not stored) is possible for our server but not for the provider: **legal to confirm**; the draft answer is "collected". Not "shared" if the provider counts as a service provider acting on our behalf (**confirm**) |
| App activity > Other user-generated content (confirm, **legal to confirm**) | **Automatic categories (D-94…D-96, draft):** normalised names of eligible business payees (up to 20 per request), the app language, a random request ID, the consent terms, the attestation. Never amount, date, account, card, last-4, institution, message text, transfers, person names, phones, IBANs, handles, digit runs of 6 or more. Alternative classification: Financial info > Other financial info (a merchant name of a payment) | **Optional** (off until the user consents) | App functionality | The request carries the install ID next to the name; the shared answer cache (name, category, confidence; 90 days) and the review tables hold no install ID (a keyed hash only, to count independent votes). Right/Wrong feedback is **not sent today**; if the PO approves it (PENDING PO, FU-412, FU-441), this row gains "feedback: shop name, suggested and chosen category" and the policy says Undo only works until the next sync |

**Never leaves the phone, also for the two LLM features:** transactions, amounts, balances, budgets, assets, SMS or notification text, accounts, cards and institutions as data from the app's records. The only free text is what the user types into an Ask question (see the row above). Not collected, answer "no" for each: location, contacts, calendar, photos and videos (the Share/OCR input stays on the phone), SMS or MMS content, call logs, web browsing, health, files, any analytics or diagnostics.

**Audio (confirm with legal):** voice entry (T-120) uses the OS speech recognizer, on-device first. If on-device Egyptian Arabic recognition isn't available, the app may use the OS **online** recognizer, only after the user's explicit consent (D-42, ADR-010): the audio then goes from the OS service to Google, never to Zaghlol's server, and the app never stores it. Zaghlol collects no audio, so the draft answer is "no"; whether the form must still list audio because the app starts that transfer is the classification to confirm. If voice entry is not in the submitted build, the answer is plainly "no".

**Support e-mails** are not app data and not in this form, but the privacy policy states them: a user who writes to support gives an e-mail address and possibly the support code (install ID) and a store order ID; the order ID is checked live and never stored on the backend (D-57), but stays in the helpdesk ticket (security-model §6) for the ticket retention period.

## Retention (privacy policy; the form itself has no retention field)

| Data | Kept |
|---|---|
| Install record (install ID, platform, versions) | Deleted after 12 months of inactivity (NFR-PRIV-06), or 30 days after "Delete everything" (tombstone) |
| Request logs | ≤ 30 days, truncated IP, no bodies (NFR-PRIV-06) |
| Account (provider subject, e-mail) | Until the user deletes the account (FR-ACCT-04); hard delete |
| Support-lookup and support-action audit rows | 1 year from creation (NFR-PRIV-07) |
| Ask question text | Not stored or logged by our backend. At the AI provider: up to 30 days for abuse monitoring until zero retention is granted **[LEGAL]**; no training on the data |
| LLM monthly counters (`llm_quota_counters`) | Current and previous Cairo month; deleted with the install or account |
| Auto-category answer cache (shop name, category, confidence) | 90 days (`expires_at`), no install data; **as built no job deletes expired rows** (backend-schema §4, follow-up) |
| LLM spend ledger (token counts and cost only) | 13 months |
| Purchases, bank requests, helpdesk tickets | Not yet set: PO/legal (placeholders `PURCHASE_RETENTION`, `BANK_REQUEST_RETENTION`, `TICKET_RETENTION` in `site/`) |

## Permissions that must match the form

| Permission | Flavor | Declared use |
|---|---|---|
| `INTERNET` | all | backend calls above (T-001 review F16) |
| `POST_NOTIFICATIONS` | all | reminders and alerts |
| `RECORD_AUDIO` | all | voice entry; on-device recognition first, the OS online recognizer only with explicit consent (D-42) |
| `READ_SMS`, `RECEIVE_SMS` | prodSms only | SMS-based money management, see `play-sms-declaration.md` |
| Notification access (`BIND_NOTIFICATION_LISTENER_SERVICE`, user-granted in Settings) | all | reading allowlisted bank / wallet notifications on the phone |

## Items from the security model section 2a that the form and policy must also say

1. Play Integrity attestation (D-45): a token proving the app is genuine is sent for purchase restore.
2. The time nonce (R4-2): a random one-time number used to check the time; nothing about the phone or user; not stored.
3. Support links (R4-7(2)): if support links Gold to an account, the phone that bought it is told when it next connects, and the notice repeats until that phone's next sync proves it stored it.
(The same-iPhone seat keys and "Delete everything" items are iOS-only: `app-store-privacy.md`.)

## Release AAB facts the form relies on

System-CA-only `network_security_config` (T-178), `allowBackup=false` with both backup rule files excluding all data (T-165), no third-party SDK that collects data. The release workflow asserts each on the AAB.
