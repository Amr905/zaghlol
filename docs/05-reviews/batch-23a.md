# Batch 23a review: FU-backend, FU-core, FU-native, SMS-TEMPLATES-2

Reviewer: `code-reviewer` (Opus, code + security). Branch: `batch/2026-11-15-23`. Date: 2026-11-14.

How this was checked: I read the production diff for each task and the riskiest tests. I ran:
- `flutter test` on `test/core/backend`, the FU-core test files, `test/features/home`, `test/features/transactions/application` and `test/ingestion/bundled_registry_e2e_test.dart`. All 438 tests passed.
- `dotnet test --filter Zaghlol.Api.Tests.Dev`. All 11 tests passed. The two failures in the wider filter are Testcontainers tests that need Docker; they run on GitHub.
- No native code was built; I read it only.

---

## FU-backend: phone-test stack, fake Play, grant-gold, dev keys (security-critical)

**Verdict: APPROVED**

### Security checks
- **Staging and production cannot enable it.**
  - Both `AddZaghlolDevFakeStores` and `MapDevFakeStores` throw unless `IsDevelopment()`. `DevKeyEnvFile.AddIfConfigured` does the same. The host therefore refuses to start in Production, Staging and Testing (theory test).
  - The `Dockerfile` defaults to `ASPNETCORE_ENVIRONMENT=Production`. Only the two compose files set Development.
  - Without the flag, nothing is registered and no `/dev/*` route is mapped (early return).
- **No keys are committed.** `dev-keys.sh` writes into the `devkeys` Docker volume (`DEV_KEYS_DIR`), and `.dev-keys/` is git-ignored. `/dev/v1/app-keys` returns only `Kid`/`PublicJwk:X`/`PublicJwk:Y`, and its test checks that nothing else leaks.
- **grant-gold scope.**
  - It targets the newest non-deleted install by `FirstSeenAt`, or a named install that must exist (404 otherwise).
  - The token is bound with `StoreBindingRef.Compute(install)` and verified with `BindingCheck.RequireCaller`.
  - The real verify, seat and entitlement code runs.
  - Any token that was not registered through grant-gold gets a 404 from the fake API, so real Play tokens are rejected.
  - The endpoint has no auth. Anyone on the developer's Wi-Fi can reach it, but it only works in Development on a local stack. I accept that.
- **App side.**
  - `allowPrivateLan` and the dev-key merge both depend on `!kReleaseMode`.
  - `parseDevBackendKeys` accepts only `[se]0000[a-z]` kids, and `ResponseSignatureVerifier` refuses dev kids when `allowDevKeys` is false. That is two independent locks, so a release build cannot pin or trust a dev key.
  - The LAN check accepts IPv4 literals only, never names.
- **`docs/workflow/run-backend-locally.md`** matches the compose file, the endpoints, the dart-defines and the flavor.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| B1 | minor | `app/lib/core/backend/backend_client.dart:105` | `isPrivateLanIpv4` accepts leading-zero octets. `Uri.parse` keeps `010.0.0.1` unchanged, and a libc resolver may read it as octal, giving `8.0.0.1`, a public address over plain http. This only applies to a developer's own compile-time define in a non-release build. | Reject octets with a leading zero (`0\d`). Add a test. Follow-up. |
| B2 | minor | `backend/tools/dev-keys.sh:24` | `rm -rf "$dir"/*` now runs on any `DEV_KEYS_DIR` that has no `kms.env`, including on a first run. A wrong export (for example `$HOME`) would empty that folder. Line 17 and the final echo still say `backend/.dev-keys`. | Refuse a `DEV_KEYS_DIR` that is neither empty nor already holding `kms.env`, or delete only `*.pem *.key kms.env`. Print `$dir`. Follow-up. |
| B3 | minor | `backend/src/Zaghlol.Api/Dev/DevFakeStores.cs:47` | The tests cover service registration only. No test checks that `MapDevFakeStores` throws outside Development, or that `/dev/v1/*` returns 404 without the flag (a `WebApplicationFactory` check). | Add both route-level tests. Follow-up. |
| B4 | nit | `app/lib/features/catalog_sync/application/sync_providers.dart:54` | A malformed `ZAGHLOL_DEV_KEYS` throws while the top-level `devBackendKeys` is being initialised, so every backend provider fails with a generic error. | Catch the error and fail with a clear message naming the define. Dev only. |

---

## FU-core: 10 fixes + Home mascot message source (money/data)

**Verdict: APPROVED**

### Checks
- **Home mascot (FU-224).** `pickHomeMascot` compares only when `previous.currency == figures.currency`, and works on each currency's own figures. `Money` subtraction and comparison throw on a mismatch anyway. The provider returns the first currency that has a message and never sums across currencies. The previous cycle is read with the same card filter as Home. The slot keeps the T-104 contextual cards below the bubble.
- **FU-075.** A currency-only update is refused inside a transaction with `CurrencyMismatch`.
- **FU-096.** `recordPaidMoney` refuses gold lots (`ArgumentError`) and other currencies (`CurrencyMismatch`).
- **FU-095.** `markApplied` runs only when rows changed.
- **FU-122.** A review item that backs a transaction no longer marks its raw message dismissed.
- **FU-127.** The healed leg now emits a cycle event.
- **FU-106.** A future `asOf` is capped at now plus the skew, so it cannot cause later replays to be rejected.
- **FU-119.** Group separators are dropped only in proper runs. I traced `1٬234٫50` → `1234.50`, and `1٬2`, `12،5` and `1234٬567` stay unchanged so the strict parser rejects them.
- **FU-079.** 29 Feb maps to 28 Feb.
- **FU-131.** Export dedupes by id.
- **FU-132.** The Undo batch is stored before the hooks run, every id runs its hooks, and the first failure is rethrown.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| C1 | minor | `app/lib/features/export_import/application/export.dart:326` | The dedupe fixes rows inserted during paging. A row deleted during paging still shifts later offsets back, and the export silently skips one row. | Use keyset paging (`occurred_at, id`). Follow-up. |
| C2 | minor | `app/lib/features/home/application/home_mascot.dart:39` | When the last cycle's net was negative, "saved X more" reports `net - lastNet`. For example, net 100 after −500 gives "saved 600 more". The arithmetic is correct, but the copy is misleading. | PO/UX decision: possibly require `lastNet > 0`. Follow-up. |
| C3 | minor | `app/lib/features/transactions/application/bulk_actions.dart:76` | The rethrow after a hook failure means the caller never receives `result.batchId`. The Undo ids are stored, but the UI cannot offer Undo for that batch. | Return the result and report the hook failure separately, or have the UI read the batch id from the exception. Follow-up. |
| C4 | nit | `app/lib/app/app_navigation.dart:120` | `_homeActions` copies every field of `HomeActions` by hand. A field added later will be dropped silently. | Add `HomeActions.copyWith(mascotSlot:)`. |

---

## FU-native: ShareStore key re-read, OCR key read, wipe widget refresh, no-log grep

**Verdict: APPROVED**

### Checks
- **ShareStore (065-2).** Both `list()` and `read()` now call `readMetaConfirmed`. A "not authentic" result is final only when the reloaded key is `.unchanged`. `.unavailable` keeps the share, and `.changed` decrypts once more. The body decrypt follows the same rule. Deletion happens only when the result is still not authentic under the current key.
- **`SpoolCipher.reloadKey`.** It returns `.unchanged` when nothing is cached, which is correct: no attempt has used a key yet.
- **OCR key provider.** It reads through `keychain.existing()` and never calls `loadOrCreate`.
- **Wipe.**
  - Android: `SafeToSpendWidgetReceiver.refreshAll` runs after the files are cleared, as a best-effort `attempt`, so it never masks `WipeIncomplete`.
  - iOS: `reloadAllTimelines()` runs before the incomplete check.
- **No-log grep.** It now covers the remaining production native folders. I confirmed that every listed directory exists, so `find` cannot fail the step.

### Findings
None.

---

## SMS-TEMPLATES-2: NBE + synthetic ATM/salary/declined/FX templates

**Verdict: CHANGES_REQUESTED**

### Checks
- All synthetic templates are tagged `"source": "synthetic-unverified"`. The schema accepts only `po-sample` and `synthetic-unverified`.
- `declined` maps to `TxnStatus.declined` through `ingest_rules.dart:75`, so it is excluded from totals.
- The `card_purchase_fx_charged` templates put the EGP charged figure in `amount`/`cur` and the foreign figure in `oamount`/`ocur`. Balance and available come out in EGP. That is correct.
- The foreign-only template cannot match a charged message, because the ` (` after last4 fails the tail.
- The manifest, guard base and spike guard were updated.

### Findings
| # | Sev | File:line | Issue | Required change |
|---|-----|-----------|-------|-----------------|
| S1 | **major (money)** | `app/assets/registry/institutions/nbe.json:164,207`; `cib.json:169,212`; `banque_misr.json:169,212`; `qnb.json:173,216` | The foreign-only `card_purchase_fx` templates capture the trailing account balance (`Avl Bal EGP 5000.00` / `الرصيد 5000.00 جم`) in `(?<balance>)`/`(?<available>)`. `template_extractor.dart:217-218` denominates balance and available in the `cur` currency, which here is USD. So the balance is stored as **USD 5,000**. Ingest then resolves the account by `amount.currency` (USD) and `_recordBalance` writes that fabricated USD balance onto it (`ingest_raw_messages.dart:1041,1106`), often on a new phantom USD account for the card. This mis-denominates money silently and breaks CLAUDE.md §2.4. The 16 fixtures assert `"balance": "5000.00"`, so they encode the bug. The fixture runner compares the number only, not the currency. | In all 8 foreign-only FX templates, make the balance/available tail non-capturing, or drop it, so that no balance is recorded when the template has no account-currency amount. Set `balance`/`available` to `null` in the 16 `card_purchase_fx_*` (non-charged) fixtures. |
| S2 | minor | `app/assets/registry/institutions/nbe.json` (`nbe.card_purchase.ar/.en`, no `source` tag); `docs/04-tasks/tasks/T-036.md:44` | The task note says the NBE purchase templates come from a "PO sample". The PO file `sms_samples_2026-11-14.tsv` has no NBE row (it starts at row 2), so the source cannot be verified. | Tag both as `synthetic-unverified`, or cite where the NBE sample came from. Follow-up. |
| S3 | minor | foreign-only FX templates | A foreign-only purchase resolves the account by USD. An EGP card therefore gets a second (USD) account with the same last4. This is existing engine behaviour, but these templates are its first real trigger. | File a follow-up: resolve card accounts by (institution, last4) and keep the foreign amount as `originalAmount`, once the PO decides how a foreign-only message is stored. |

---

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| SMS-TEMPLATES-2 | `app/assets/registry/institutions/{nbe.json:164,207; cib.json:169,212; banque_misr.json:169,212; qnb.json:173,216}` | The foreign-only `card_purchase_fx` templates must not capture `balance`/`available`, because the balance is in the account currency and not `cur`. Make the tail non-capturing and update the 16 fixtures to `balance: null`. | An ingest test (in `bundled_registry_e2e_test.dart`): an NBE foreign-only FX SMS with `Avl Bal EGP 5000.00` stores a USD expense and records **no** balance, with no USD 5,000 balance row. The fixture runner should also compare the balance currency, or that test fails without the fix. |

## Lead delta check (SMS-TEMPLATES-2 fix, commit ff96db40)

The eight foreign-only `card_purchase_fx` templates no longer capture `balance` or `available` (non-capturing tail); their fixtures expect null. The `_charged` templates keep the EGP balance, now asserted with `balanceCurrency`/`availableCurrency` EGP. `fixture_runner` compares the balance and available currency, so a balance read in the wrong currency fails. A new e2e test stores a foreign-only NBE message as a USD expense with no balance. Verdict: APPROVED.
