# Batch 40 review (code + security, one reviewer)

Branch `batch/2026-11-18-40`. Reviewer: code-reviewer (Opus). Date 2026-11-18.

Checks run: backend `Zaghlol.Application.Tests` 1057/1057, `Zaghlol.Workers.Tests` 30/30, `Zaghlol.Infrastructure.Tests` price adapter + provider tests 25/25 (Docker-backed store tests run on GitHub only); app `flutter test test/core/l10n test/features/onboarding test/features/notifications`, 166 passed.

## T-127 Gold price adapters (GoldAPI, MetalpriceAPI). Verdict: APPROVED

The T-127 commit (7179016a) reached the batch through `task/T-140-prep`; `task/T-127` itself equals `main`. All math is `decimal` (`JsonElement.TryGetDecimal`, no double path). oz to gram is 31.1034768. 21K and 18K are derived as k/24 by `PriceNormalizer`. Sanity bounds throw `PriceProviderException`, so the last good value stays. A failure is not cached. The key comes only from config/secrets and startup fails without it. Transport errors carry fixed text with no inner exception, and the HttpClient loggers are removed, so the MetalpriceAPI query-string key cannot reach a log. Tests use stub handlers, with no live calls. The doc says plainly that the field names are unverified.

| # | Sev | File:line | Finding | Change |
|---|---|---|---|---|
| 1 | minor | backend/src/Zaghlol.Infrastructure/Prices/GoldApiProvider.cs:42-47 | Vendor `price_gram_21k/18k/24k` values are taken without any bound or consistency check against `price`/31.1034768. Only the ounce price is bounded. | Bound each gram price, for example within ±5% of the ounce-derived value times k/24. |
| 2 | nit | docs/03-technical/gold-price-providers.md:13 | GoldAPI link is `https://github.com//goldapi-io` (empty segment). | Fix the URL. |

## T-140-prep Hosting / OpenTofu / deploy workflow (no deploy). Verdict: APPROVED

- **Deploy workflow:** `workflow_dispatch` only, gated by `vars.BACKEND_DEPLOY_ENABLED`, runs in GitHub environments. It authenticates with OIDC WIF, and no secrets or keys are stored. The digest input passes through env and is regex-checked. Prod only promotes the staging digest.
- **KMS:** keys are bound per key with `signerVerifier` / `encrypterDecrypter` and no export/import role. The protection level defaults to HSM, and `prevent_destroy` is set.
- **Database:** Cloud SQL has no public IPv4 (`ipv4_enabled=false`, private network) and uses `ENCRYPTED_ONLY`. Backups and PITR (14 d) are on, along with deletion protection and terse error logging. No DB user passwords are in state.
- **Docs and checks:** the PDPL section is clearly marked "Not legal advice". The secret grep found nothing.

| # | Sev | File:line | Finding | Change |
|---|---|---|---|---|
| 3 | minor | backend/deploy/terraform/README.md:41-43 | The deploy SA is told to hold `roles/resourcemanager.projectIamAdmin`. That is effectively project-owner escalation for whoever can run the workflow. | Before the first deploy, scope it with an IAM condition (allowed roles list) or bind per resource. Document this. |
| 4 | minor | .github/workflows/backend-deploy.yml:15-46 | `prod` can be dispatched from any ref. Only the GitHub environment's branch policy stops that, and the README checklist does not state it. | Add `github.ref == 'refs/heads/main'` (or `v*` tag) to the job `if` for prod, or list the branch policy in the README steps. |

## T-176-177-prep + IOS-store-fixes Release workflows, store docs, entitlements. Verdict: APPROVED

- **Triggers and secrets:** both workflows are manual only and run in protected environments (`android-release`, `ios-release`). Signing and upload are gated on secrets, and upload also needs `upload=true` and main or `v*`. Secrets are passed via env, and the key files are removed under `always()`. The Gradle signing config reads env or a git-ignored `key.properties`, and `ZAGHLOL_REQUIRE_UPLOAD_KEY` prevents a silent fallback to debug signing.
- **Symbols and SDKs:** Dart symbols, the R8 mapping and dSYMs are uploaded only AES-encrypted. There is no crash SDK.
- **Store docs:** the Data safety, App privacy and SMS declaration drafts match BR-SYNC-03 (install ID, attestation, purchase tokens, optional account, opt-in contributions, request-my-bank). None of them claims "no server".
- **iOS fixes:** the `applesignin` entitlement was added. The widget `PrivacyInfo.xcprivacy` is in Resources, and the widget code uses no required-reason API, so the empty list is correct.

| # | Sev | File:line | Finding | Change |
|---|---|---|---|---|
| 5 | minor | .github/workflows/release-android.yml:250-258 | The dry-run unsigned AAB is a public artifact. An AAB carries `BUNDLE-METADATA/.../proguard.map` and native symbols, which contradicts the "mappings never in the clear" comment. The source is public, so this is low risk. | Strip BUNDLE-METADATA before upload, upload only the universal APK, or drop the artifact. |
| 6 | minor | docs/06-release/app-store-privacy.md:9,49-52 | Stale after IOS-store-fixes: it still says the widget manifest is "none" and the `applesignin` entitlement is missing. | Update the table and the open points. |
| 7 | minor | docs/06-release/app-store-privacy.md:13 | The app manifest's `NSPrivacyCollectedDataTypes` is empty, while the label lists collected data. This is already flagged as a follow-up. | Fill the manifest before submission (FU). |

## T-058-pass1 Arabic copy fixes. Verdict: APPROVED

I spot-checked 15 keys: commonActionMore, commonErrorSaveFailed, onboardingAndroidSetupSmsPointOnPhone, onboardingAndroidSetupSmsAllow, onboardingIosSetupShortcutTitle (ar+en), onboardingIosSetupFirstStatementSub, homeHeroDaysToPayday, exportsImportUntracked, insightsExplainCashFlowTip, insightsExplainNetWorthDeep, chatAnswerBalanceCredit, roiRuleWaterTitle/Body, categoriesEditBucketSavings, backupPassphraseMismatch.

- **Voice and wording:** the Arabic is Egyptian colloquial and correct. The privacy line now uses the allowed claim ("بيانات فلوسك بتفضل على الموبايل ده"). The plural agreement in `exportsImportUntracked` many/other is fixed.
- **Placeholders and plurals:** all are intact.
- **English key change:** the en `onboardingIosSetupShortcutTitle` change removes text that duplicated `ShortcutWhy`, and ar/en stay in parity.
- **Generated files:** they were regenerated.

| # | Sev | File:line | Finding | Change |
|---|---|---|---|---|
| 8 | nit | app/lib/core/l10n/app_ar.arb (categoriesEditBucketWants) | "رفاهيات" (luxuries) reads more judgmental than "wants". Check it against the voice guide's no-shaming rule. | Leave it to the UX pass 2 reviewer list. |

## Fix list (blocking only)

None. All findings are minor or nit and go to follow-ups.
