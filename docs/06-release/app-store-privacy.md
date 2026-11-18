# App Store privacy answers and App Review notes (draft, T-177)

## Privacy manifest status (verified in the tree and asserted by `release-ios.yml`)

| Bundle | `PrivacyInfo.xcprivacy` | Declared |
|---|---|---|
| Runner (app) | present | `NSPrivacyTracking=false`, no tracking domains, no collected data types; required-reason APIs: SystemBootTime **35F9.1** (T-180 trusted clock), FileTimestamp **C617.1** |
| ShareExtension | present | see file |
| ZaghlolWidget | **none** | Open item: confirm the widget code uses no required-reason API (it reads the App Group snapshot); if it does, add a manifest. Flagged for the batch reviewer. |

`NSPrivacyCollectedDataTypes` is empty in the app manifest. App Store Connect's App Privacy answers are what Apple shows users; the manifest's collected-data list should be completed to match the table below before submission (a follow-up for the iOS engineer: a manifest that is empty while the nutrition label lists data is inconsistent). No third-party SDK ships its own manifest requirement today (no analytics, ads, crash SDK).

## App Privacy ("nutrition label") draft

Tracking: **No**. Zaghlol does not track users (no ad or analytics SDKs, no data sharing for tracking).

Data **not collected** (stays on the phone): SMS/message content, transactions, amounts, balances, budgets, assets, contacts, location, photos (Share/OCR and PDF stay local), audio and speech (on-device recognition).

Data collected by Zaghlol's backend:

| Apple type | Data | Linked to identity? | Tracking | Purpose |
|---|---|---|---|---|
| Identifiers > Device ID | Anonymous install ID; App Attest assertion (D-45) | Not linked to the user's identity (random ID, no account needed). For signed-in users the account token links to the account: declare as linked for those users (confirm) | No | App functionality |
| Purchases > Purchase history | Purchase transaction identifiers for Gold verification and restore | Linked for signed-in users, otherwise not (matches `deployment.md` section 2) | No | App functionality |
| Contact info > Email address | Optional Sign in with Apple / Google ID-token claim | Linked, optional | No | App functionality (account) |
| Other data | Opt-in merchant contributions; "Request my bank" (institution, country, channel) | Not linked | No | App functionality |
| Usage / diagnostics | none collected | | | |

## Disclosures that the privacy notice and the privacy details must state (security-model section 2a, T-137)

1. **Same-iPhone seat keys (D-62):** restore and sign-in send a key proof from this install and from up to 4 earlier Zaghlol installs on the same iPhone, so the server can tell those installs were on the same iPhone; it keeps only a keyed hash, per purchase and per install, and never logs the keys. (In transit linkability is accepted.)
2. **"Delete everything" (R4-8):** keeps the seat keys on the phone so Gold can return without using the monthly move; the server keeps a keyed hash with the purchase until the purchase is deleted. Erasing the iPhone removes the keys.
3. **Time nonce (R4-2):** a random one-time number used to check the time; nothing about the phone or user; not stored.
4. **Support links (R4-7(2)):** if support links Gold to an account, the phone that bought it is told when it next connects; the notice repeats until that phone's next sync proves it stored it.
5. App Attest (D-45): an assertion proving the app is genuine is sent for restore.

## App Review notes (draft, English; attach in App Store Connect)

- Zaghlol keeps financial data on the phone. The server handles purchase verification, merchant catalog sync, gold/FX prices and feature flags only.
- **No SMS access on iOS.** Transactions arrive from (a) Shortcuts personal automations (Message and Wallet triggers) that the user sets up with the in-app guide and that call the app's App Intents, (b) the Share Extension, (c) camera/photo OCR on the phone (Vision), (d) PDF import, (e) voice and manual entry. Reviewers can test with the share sheet and manual entry without any automation.
- **Sign in with Apple** is offered wherever Google sign-in is offered; sign-in is optional and exists only to carry Gold across devices.
- **Account deletion** is in-app: Settings > Account > Delete account (FR-ACCT-04); "Delete everything" erases on-device data.
- **Gold** is sold through StoreKit 2 (monthly, yearly, lifetime); entitlement is verified by our server. A sandbox demo path: demo Apple ID credentials to be supplied by the PO.
- Face ID is used only for the optional app lock (`NSFaceIDUsageDescription`); microphone and speech recognition only for voice entry, on device.
- Encryption: standard TLS and on-device AES via system and bundled libraries; export compliance answers to be completed by the PO (`ITSAppUsesNonExemptEncryption`).
- No tracking, no third-party analytics or advertising SDKs.

## Open points for the iOS engineer or PO

1. `Runner.entitlements` has no `com.apple.developer.applesignin`, yet the app uses `sign_in_with_apple`: confirm the capability and add it before the signed build, and in the app's provisioning profile.
2. The three provisioning profiles must include App Groups, Keychain sharing and iCloud (CloudDocuments) per the entitlements files.
3. Widget privacy manifest (above).
4. Demo account for review.
