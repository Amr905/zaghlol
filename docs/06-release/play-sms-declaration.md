# Play "SMS-based money management" declaration package (draft, T-176)

Policy basis (Play Console Help, "Use of SMS or Call Log permission groups"): the exception covers apps that "track and manage budget" and are not the default SMS handler; it is granted only when the permission enables the core function and there is no alternative method; it is temporary and case by case; non-financial or personal SMS history may not be shared; resubmit the form when the use changes. ADR-004 already plans for refusal: ship `prodNoSms` unchanged (same applicationId, no SMS permissions) the same day.

## Submission checklist (Play Console, App content > Sensitive app permissions)

- [ ] Declare `READ_SMS` and `RECEIVE_SMS` only (the prodSms manifest requests exactly these; the release job fails on any other restricted SMS permission).
- [ ] Core-function statement (below).
- [ ] Demo video (script below), unlisted YouTube link.
- [ ] Privacy policy URL that states the SMS handling: `https://zaghlol.app/privacy` (draft in `site/privacy/` §4, pending legal review, FU-195-legal).
- [ ] Upload prodSms to the internal track first; the declaration is per app, the build that carries it is prodSms.

## Core function statement (English, for the form; PO to review)

Zaghlol is a personal-finance app for users in Egypt. Its core function is automatic expense and income tracking from the user's bank, InstaPay, wallet and BNPL transaction messages. The app reads an incoming SMS only to check whether the sender is on a built-in allowlist of financial senders. Messages from any other sender are discarded in memory immediately and are never stored, logged, uploaded or shown. For allowlisted senders, the message is parsed on the phone into a transaction (amount, merchant, date) that is kept in an encrypted database on the phone. The raw message text is not sent to any server. Zaghlol's server never receives messages, transactions, amounts or balances. The user can use the app without granting SMS access (notification capture, share/paste and manual entry exist) and can revoke the permission at any time. There is no alternative to SMS for a bank that sends only SMS and for importing past transactions, so the permission is needed for the core function. We do not sell, share or use SMS data for advertising, research or profiling, and SMS data is never used to influence another user's experience.

Consistency note (batch 54, `privacy-consistency.md`): "Zaghlol's server never receives messages" stays true with merchant contributions on, because a contribution carries only the normalized merchant text, the institution code and the system category (BR-SYNC-04), never the message. If the submitted build lets the user add their own phone-number senders (T-048, PO_DECISIONS FU-109 M-1), add to the statement: "The user can also add a sender explicitly; for such senders only new messages that look financial are read, and an older-message scan needs a separate opt-in."

## Facts reviewers will check (all true in the codebase, each has an owner task)

| Claim | Where it is enforced |
|---|---|
| Only allowlisted financial senders are read; non-financial SMS never reach storage | Capture Guard (T-035/T-038), native inbox query filtered by sender in SQL (security-model section 1 and ADR-004) |
| No message body in logs or crash output | CI step "no logging in key code"; no crash SDK |
| Raw message never leaves the phone | privacy contract test (security-model section 2 item 4) |
| SMS permissions exist only in `prodSms` / `*Sms` flavors | `src/sms/AndroidManifest.xml`; app-ci and release job aapt2 assertions |
| Backup excluded | T-165 |
| Not a default-SMS-handler app, no SEND_SMS, no MMS/WAP | manifest assertion |

## Demo video script (about 2 minutes, English voiceover, Arabic UI visible)

1. Open on a fresh install (prodSms build). Show the Welcome screen and the in-app explanation screen ("What Zaghlol reads and why", FR-ING-A) before any system prompt.
2. Tap continue; show the system SMS permission prompt; grant it.
3. Send a synthetic bank SMS from an allowlisted test sender (emulator console or second phone): show the transaction appearing in the app with parsed amount and merchant.
4. Send a personal SMS from a normal number: show that nothing appears anywhere in the app.
5. Open Settings > Privacy > "What Zaghlol's server knows about you": show the list with no messages or transactions.
6. Show airplane mode: capture still works offline (nothing is uploaded).
7. Revoke the SMS permission in system settings; show the app degrading to notifications / share / manual (FR-ING-A-05) without crashing.
Use synthetic messages only (CLAUDE.md constraint 6).

## If Google refuses or revokes

Ship `prodNoSms` (built by the same workflow, `flavor: prodNoSms`). Capability flags hide the SMS UI. File the outcome in `docs/01-requirements/open-questions.md` (R-01).
