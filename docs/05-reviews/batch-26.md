# Batch 26 review (batch/2026-11-15-26) — urgent device fixes

Reviewer: code-reviewer (Opus; code + security). Scope: FIX-device-flows, FIX-sms-real.
Tests run: `flutter test` on add_sheet_selection, drift_transaction_repository, txn_edit_providers (41 pass); `dart test` on zaghlol_parsing test/real, test/generic, test/pipeline (246 pass). An ad-hoc probe (not committed) ran non-transaction HSBC messages through Guard + pipeline (results below).

## FIX-device-flows — APPROVED

Checked:
- **Add sheet:** `app_router.dart:69-75` now passes the sheet's own `Builder` context. `closeAddSheetThen` (`add_sheet.dart:25-43`) pops the sheet route, then opens the destination from the root navigator's context after `route.completed`, and checks `nav.mounted` first. Scan, asset/paywall, type and say all go through it. Correct.
- **Default Cash:** `ensureDefaultCash` (`drift_accounts_repository.dart:77-104`) does a read, then an insert. The partial unique index `ux_accounts_default_cash` (`financial.drift:52`) blocks a second Cash, and a race that loses falls back to the winner. Currency comes from `Settings.primaryCurrency`. No duplicate Cash is possible. The provider catches errors and returns null, so the editor degrades as before.
- **TransactionsChanged:** the wrapper (`alerting_transaction_repository.dart`) publishes after the write commits and is best effort. The only subscribers are the cycle cache invalidator and budget providers (`budget_providers.dart:114`), and neither writes transactions, so there is no loop. Bulk edit, pairing and refunds use their own paths, so the same change is never sent twice through this wrapper. If an extra event did occur, it would only trigger one more recompute.
- **Catalog seed:** `main.dart:198` listens to `catalogSeedProvider`. `loadIfNeeded` does nothing once a version exists, so the cost falls on first launch only. A failure leaves the provider in an error state with no retry and does not crash the app.
- **Workflow:** runs only on `ci/**` pushes and `workflow_dispatch`, never on PRs from forks. Actions are pinned by SHA. Checkout uses `persist-credentials: false`, and only the final step references the token, which is masked. Screenshots come from synthetic test data. `contents: write` is acceptable here: the workflow has one job, and the force-push goes to the dedicated `device-shots` branch only.

Findings (none blocking):
- **major (non-blocking, not money/security), `app/lib/core/catalog/catalog_providers.dart:35` + `packages/zaghlol_catalog/lib/src/trusted_keys.dart:15`:** `allowDevKeys: !kReleaseMode`, and the only bundled key is the dev key `s0000a`. So **any release-mode APK (`prodSms`/`prodNoSms`) fails closed: no categories, and S-13 still cannot save.** This is the documented design (FU-090), but it means the PO must test a **debug devSms/stagingSms APK**, not a prod release build. The Lead should tell the PO this explicitly. Before a store build, either FU-090 lands or the editor must be able to save without a category.
- minor, `add_sheet.dart:36-38`: the `removeRoute` branch (sheet not on top) relies on `route.completed` resolving after `removeRoute`. Only the `isCurrent` path is exercised. Add a test, or open the destination at once in that branch.
- minor, `alerting_transaction_repository.dart:36-45`: `_read` makes one `byId` call per id. A large bulk delete therefore does N reads. Batch them later.
- minor, `txn_edit_providers.dart:31`: `defaultCash()` does not filter deleted or hidden accounts, so a soft-deleted Cash account would still be returned. This predates the batch; noting it for a follow-up.
- nit, `device-flows.yml:17`: move `permissions` to job level and add a `concurrency` group for `device-shots`, so two runs cannot race on the force-push.

## FIX-sms-real (C4 ingestion) — APPROVED

Checked:
- **HSBC template** (`hsbc.json`, `hsbc.card_used_limit.en`): the USD amount stays USD. The available limit reads its own currency through `acur` (`template_extractor.dart:217-228`) and is never converted. An `acur` that cannot be resolved counts as a fatal `balanceInvalid`, and the message then falls back to the generic parser. The date format is `d/M/yyyy`. `* 4417`, `*5075` and `xx…` are all handled. Fixtures cover Arabic digits, thousands separators and the no-space star.
- **Sender tolerance:** `^hsbc(?:[ ._-]?(?:eg|egy|egypt|bank))?$` is anchored. Tests reject `HSBCX`, `MYHSBC`, `XHSBC` and `HSBC EG PROMO`. The Dart Guard, the devSms spike Guard and the registry use the same pattern. Kotlin (`GuardConfig.kt:326`) and Swift (`GuardConfig.swift:412`) already support `regex` sender rules from the same JSON, so the native code did not need to change.
- **Generic fallback for known senders** (`parsing_pipeline.dart:181-202`): it runs **after** the institution drop rules and the global OTP/promo drop rules (lines 125-133), and after every template has been tried. A fatal template result still wins. `parseGeneric` caps confidence below the auto-accept threshold (test asserts `< kAutoAcceptThresholdPermille`). In ingest (`ingest_raw_messages.dart:1343-1370`), these results go to **review**. Auto-save happens only for a sender the user marked `alwaysCapture` **and** confirmed N times, and only for background messages. That is the existing A-66 policy. Probe results with sender `HSBC`:

  | message | result |
  |---|---|
  | "Use code 482913 to confirm your payment of EGP …" | dropped (global OTP) |
  | declined / limit increase | `noTemplateMatched` |
  | "Your OTP for transaction of USD 38.50 … is 482913" | Generic → review, direction null, 560‰ |
  | cashback promo | Generic → review, **income** EGP 500, 630‰ |
  | statement ready | Generic → review, direction null, 352‰ |
  | "payment … is due on 25/11/2026" | Generic → review, **expense**, 700‰ |
  | installments promo / payment received | Generic → review, null / conflict |

  None of these is auto-accepted. They add review noise but cannot write a transaction on their own, so this is not blocking.
- **Privacy:** no logging was added. The result carries no body text. All fixtures are synthetic.

Findings (none blocking):
- minor, `app/assets/guard/guard_base.json` (global drop) + `hsbc.json` drop: an OTP worded "Your OTP … is NNNNNN" passes the Guard and now becomes a review item with an amount. A payment-due reminder becomes an "expense" review item. Add drop patterns for `otp … is \d{4,8}` / `do not share`, `due on|minimum due|statement`, and `cashback|offer|T&C`. Add negative-proof tests for each.
- minor, `ingest_raw_messages.dart:1357`: a generic result from a **known** institution is filed as `ReviewKind.newSender`, so the review copy for HSBC may say "new sender". Also, the generic auto-save path resolves its account with `_genericInstitution(p.senderKey)` instead of `g.institutionCode` (`:1374`). For a known bank with `alwaysCapture`, that could create a second account for the same card. Use the institution code when it is present.
- minor: no native golden vector covers `HSBC EG` / `HSBC-EG` / `HSBCX`. The Kotlin and Swift Guards agree with Dart only by construction. Add these senders to the Guard golden corpus.
- nit, `generic_parser.dart:116`: `_messageDate` takes the first `d/M` in the body. In an "offer valid till dd/MM" message that date is in the future, so it is rejected and the code falls back to the receipt date. The behaviour is correct, but a comment saying so would help.

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|---|---|---|---|
| — | — | None. No blocker or money/security/privacy/data-loss major. | — |

Lead note for the PO: hand over a **debug `devSms` (or `stagingSms`) APK**. A `prod*` release APK will still start with no categories (see the FIX-device-flows major above).
