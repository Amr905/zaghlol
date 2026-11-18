# Google Play Data safety answers (draft, T-176)

Source of truth: `docs/03-technical/security-model.md` section 2 and 2a, SRS BR-SYNC-03. Rule used: Play counts only data **sent off the device** as collected; data processed only on the phone is not collected (Play Console Help, Data safety). So SMS and notification text, transactions, amounts, budgets, assets, contacts and location are **not collected**: they never leave the phone except in the user's own encrypted Drive backup or a user-initiated export (both user-initiated transfers to the user's own account; confirm with the form wording at submission).

Draft for the PO and legal to confirm in Play Console. Items marked (confirm) are classifications the form lets you argue either way.

## Overview questions

| Question | Answer |
|---|---|
| Does the app collect or share any of the required user data types? | Yes (the items below) |
| Is all collected data encrypted in transit? | Yes (TLS to the backend only; `BackendClient` is the only HTTP client). Pinning per ADR-018. |
| Do you provide a way for users to request data deletion? | Yes: in-app account deletion (FR-ACCT-04) and "Delete everything"; support request for purchase-linked records. Privacy policy URL: real URL pending (FU-195). |
| Data shared with third parties | **None** (no ads, analytics or crash SDKs). Google Play Billing and the user's own Drive are the platform / the user, not third-party sharing (confirm). |

## Data types collected (all: not shared, app functionality, collection required unless noted)

| Play category > type | What is sent | Optional? | Purpose | Notes |
|---|---|---|---|---|
| Device or other IDs > Device or other IDs | Anonymous install ID (random, not derived from the device); attestation token (Play Integrity, D-45) with a per-request random time nonce (R4-2) | Required for backend features | App functionality, fraud prevention / security | The attestation token carries no other device data (D-45). The time nonce is random, one-time, stored nowhere. |
| Financial info > Purchase history | Purchase tokens / transactions for Gold verification and restore | Required for Gold | App functionality | Gold is granted only by backend verification (constraint 2a). Order IDs are never sent by the app. |
| Personal info > Email address | Only through the optional Google sign-in ID token (carries Gold across platforms, ADR-016) | **Optional** | Account management | The server uses the token; the e-mail claim is kept only as the keyed pseudonym described in NFR-PRIV-07 (support audit, 1 year). |
| App activity > Other user-generated content (confirm) | Merchant-name contributions: merchant text and category only, **only if the user opts in** (off by default), filtered on the phone and again on the server (BR-SYNC-04) | **Optional** | App functionality (shared merchant catalog) | No amounts, dates, card digits, IPA or phone. |
| App activity > Other actions (confirm) | "Request my bank": institution name, country, channel type (FR-PAR-14), only when the user asks | **Optional** | App functionality | Never the message. |
| App info and performance | Platform, app version, catalog version, registry version | Required | App functionality | Classified by D-48 as "catalog/app version". |

Not collected, answer "no" for each: location, contacts, calendar, photos and videos (the Share/OCR input stays on the phone), audio (RECORD_AUDIO is for on-device speech to text only, ADR-010, nothing is uploaded), SMS or MMS content, call logs, web browsing, health, files, any analytics or diagnostics.

## Permissions that must match the form

| Permission | Flavor | Declared use |
|---|---|---|
| `INTERNET` | all | backend calls above (T-001 review F16) |
| `POST_NOTIFICATIONS` | all | reminders and alerts |
| `RECORD_AUDIO` | all | voice entry, on-device recognition |
| `READ_SMS`, `RECEIVE_SMS` | prodSms only | SMS-based money management, see `play-sms-declaration.md` |
| Notification access (`BIND_NOTIFICATION_LISTENER_SERVICE`, user-granted in Settings) | all | reading allowlisted bank / wallet notifications on the phone |

## Items from the security model section 2a that the form and policy must also say

1. Play Integrity attestation (D-45): a token proving the app is genuine is sent for purchase restore.
2. The time nonce (R4-2): a random one-time number used to check the time; nothing about the phone or user; not stored.
3. Support links (R4-7(2)): if support links Gold to an account, the phone that bought it is told when it next connects, and the notice repeats until that phone's next sync proves it stored it.
(The same-iPhone seat keys and "Delete everything" items are iOS-only: `app-store-privacy.md`.)

## Release AAB facts the form relies on

System-CA-only `network_security_config` (T-178), `allowBackup=false` with both backup rule files excluding all data (T-165), no third-party SDK that collects data. The release workflow asserts each on the AAB.
