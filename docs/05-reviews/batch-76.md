# Batch 76 review: T-262, T-263 (C4), T-264, T-265, T-267, T-271

Batch `batch/2026-11-26-76` @ `aa79ab5d` against `main` @ `44ac3364`. One reviewer, code and security (Opus; T-263 is C4).

Verdict: **CHANGES_REQUESTED**. There is 1 blocker (T-262) and 2 majors (T-267). T-263, T-264, T-265 and T-271 are APPROVED.

## Checks run

| Check | Result |
|-------|--------|
| `flutter pub get --enforce-lockfile` | ok |
| `flutter analyze` (app) | clean |
| `dart analyze --fatal-infos` in `packages/zaghlol_parsing` and `packages/zaghlol_domain` | clean, both |
| `dart test` in `packages/zaghlol_parsing` | 1731 pass |
| `dart test` in `packages/zaghlol_domain` | 523 pass |
| `flutter test -x golden test/features/capture test/features/transactions test/features/salary test/features/home test/core/l10n` | 752 pass, **1 fail** (B1) |
| `flutter test -x golden test/features/insights test/features/budget test/features/hide_amounts test/features/settings test/features/share_cards test/features/ask test/features/gold test/a11y` | 1606 pass. Extra run, because T-262 copy changes reach these screens |
| Kotlin (T-263) | not compiled locally. I read it for compile errors and found none (see T-263) |

---

## T-262: Arabic says شهر instead of دورة (copy)

Verdict: **CHANGES_REQUESTED** (B1)

**Blocker**
- **B1.** `app/test/features/home/presentation/home_screen_test.dart:251`. The test `filter empty names the card (EC-61) and clears` still expects `"… this cycle"`. T-262 changed `homeEmptyFilter` (en) to `"No transactions for {cards} this month"` (`app_en.arb:390`), so the test fails and the batch CI run will be red. Required change: expect `this month`. A one-line fix (Lead delta check).

**Arabic review.** All 23 changed values agree in gender: الشهر ده, اللي فات, الجاي, هيخلص, الشهر اللي قبله/بعده. No sentence repeats شهر. Wherever a pay-month preset sits next to a calendar preset (`commonPeriodThisCycle/LastCycle/LastCycles`, `chatPeriodThisCycle/LastCycle`), it says "شهر المرتب" / "pay month", so period pickers and chat never confuse a pay month with a calendar month. The Home hero, budgets, mascot lines and share cards say "الشهر ده" for the pay cycle. That is what the task asked for, and on those screens no calendar-month figure stands next to it. `no_dawra_test.dart` guards against دورة coming back.

**Minor (follow-up)**
- **FU-350.** `app_ar.arb` `commonPeriodLastCycles` "آخر {n} شهور مرتب" is not plural-aware: for n ≥ 11 Arabic takes the singular (آخر 12 شهر). Use an ICU plural if n can exceed 10.

---

## T-263: image shares reach the scan (C4 native)

Verdict: **APPROVED**

**Root cause and fix.** The task file explains the cause convincingly. `MainActivity.onResume` announced `store.list()` without `ocrPath`, and Dart then de-duplicated the id, so a later correct poll was ignored. The fix routes both announcement paths through `ShareDescriptor.withOcrPath()`.

**Kotlin compile read.** I found nothing that would break the compile:
- `withOcrPath` is a top-level extension in `app.zaghlol.platform.share`, and `MainActivity` imports it.
- The `getParcelableArrayListExtra` overloads use the correct API levels; on SDK 33+ the call returns `ArrayList<Uri>?`.
- `MultiShare` is generic.
- `app.zaghlol.R` matches `namespace = "app.zaghlol"`.
- The test uses the existing `FakeShareSource.stream`, `FakeBoundsProbe` and `PNG_HEAD`, and `newId` gives 28 hex characters, which matches `ShareStore.ID`.

**Security**
- **New `SEND_MULTIPLE` filter.** It is on the same exported `ShareActivity` and admits only `image/*`, so it adds no new data kind. Only the first URI is used, and `streamScheme/Host/UserInfo/ProviderPackage` are all derived from that URI, so `ShareUriPolicy` checks it as before: content scheme only, no own authority, no system providers (sms/mms/contacts), no user-info. The rest of the list is never opened. The platform moves `EXTRA_STREAM` into ClipData for `SEND_MULTIPLE` as well, so the read grant still comes from ClipData. Size caps and byte sniffing in `ShareIntake` are unchanged. A wildcard `image/*` type is decided by the bytes, which the test covers.
- **`ocrPath ?? d.id` in `shared_items_lifecycle.dart:121`.** Dart cannot be made to read an arbitrary path:
  - The `id` comes from the native store, not from the sender.
  - On Android, `OcrHost.recognizeBlocking` resolves it only through the share store, which requires `[0-9a-f]{28}`, decrypts the sealed copy and deletes it in `finally`.
  - On iOS, `ocrPath` is always set for images (`ShareIntakeHost.swift:28`). If the store is missing, the id fallback fails `OcrPaths.isInside(home)` and ends in an IO error, never a read.
- **Logging.** No content or URI is logged, and the Toast carries no content.

**Tests:** Kotlin `ShareImageSharesTest` (4 tests) runs in CI. In Dart, `shared_items_lifecycle_test.dart` covers the missing-`ocrPath` read and the OCR-not-available screen; both pass.

**Minor (follow-up)**
- **FU-344.** `ShareActivity.kt:64-67`. The "first one only" Toast appears before the intake has validated the first item, so a rejected first item shows both messages. Show it only after `ShareOutcome.Accepted`.
- **FU-345.** iOS: `NSExtensionActivationSupportsImageWithMaxCount = 1`, so a multi-photo share does not offer Zaghlol on iOS. The builder recorded this; it needs an Xcode-verified change.

---

## T-264: camera source, dev-only "what I read" (C3)

Verdict: **APPROVED**

**Production diff.**
- `scanImagePickerProvider` takes a `ScanImageSource`.
- `camera_access_denied` maps to `ScanCameraDeniedException`, which shows a banner and makes the Gallery button primary.
- The `finally` block deletes the plain file after `sealImage` in every outcome. On cancel no file exists.
- The Android manifest declares no CAMERA permission, so the system camera intent is used.
- iOS `NSCameraUsageDescription` exists in en and ar (`InfoPlist.xcstrings`), and the Arabic is Egyptian colloquial.

**Security / privacy**
- **Not reachable in release.** `scanReadTextEnabledProvider` returns `kIsDevBuild`, a `const` built from `appFlavor` (`ingestion_config.dart:39`), so AOT drops the button in staging and prod. When the flag is false, `ScanService` sets `lastReadText` to null on both the image path and the text path. The test "release: no button in found, no-text or no-total" covers this.
- **Memory only, never logged.** In dev builds the OCR text lives only in the `lastReadText` field and the dialog's `SelectableText`. It is never logged, written, or put into an outcome or diagnostics counter.

**Tests:** 4 camera/gallery tests (both sources, camera → confirm, cancel, denied in ar and en) and 4 "what I read" tests. All pass.

**Minor (follow-up)**
- **FU-346.** On Android, if the system kills the app while the camera is open, `image_picker` keeps the photo for `retrieveLostData()`, which the app never calls. A plain photo then stays in the app-private cache until the OS clears it. Call `retrieveLostData()` at start-up, then delete or seal the file.
- **FU-347.** No test covers the provider's delete-after-seal, including when sealing fails. The AC "cancel leaves no file" is shown only through an overridden picker.

---

## T-265: InstaPay title and To/From name (C2)

Verdict: **APPROVED**

**Production diff.**
- `instapay_title.dart` marks a transaction as InstaPay when its category is `kInstapayCategoryId` or its counterparty kind is `ipa`, and never for internal transfers.
- The name is wrapped in FSI…PDI isolates.
- A non-empty merchant that differs from the counterparty counts as a user rename and keeps its own title. InstaPay bill templates set the biller as merchant and keep the biller title, which is correct.
- The list row, the Home feed row and the detail header use it.
- `counterpartyKind/Value` are mapped in the repository.

**Search:** the FTS index already holds `counterparty_value` (`fts_options.dart`, `transactions_search_test.dart`).

**Minor (follow-up)**
- **FU-348.** Two gaps:
  - Review cards and widget rows (scope 2) were not changed.
  - The new search test runs on `FakeRepo`, whose filter the builder extended, so it proves nothing about real search; real search is already covered by `transactions_search_test`.
  - Note: when an IPA address was parsed, the second line shows the address (`To omar.k@instapay`), not a person's name. That matches "as stored".

---

## T-267: receipt total cross-checks (C3)

Verdict: **CHANGES_REQUESTED** (M1, M2)

I ran adversarial synthetic texts through `ParsingPipeline.parseOcr` (scratch only, not committed). Many came out correct at 600:
- net + VAT + service with a Visa tender, service without VAT, integer-only totals, quantity-heavy rows, one large item, a tax registration number, `Visa ****4321 150.00`, a discount with a matching Visa, and `12:15 PM` / "Pomegranate" after a time.
- A wrong `Total 1500.00` confirmed only by an equal cash line was correctly offered as a guess (3× the item sum).

Two regressions remain.

**Major (money)**
- **M1.** `receipt_parser.dart` `_tenders` (the `_cardLabel` path), together with the 3× rejection in `_pickTotal` and the lone-card guess.
  - **Issue.** Masked card digits are read as the card amount, because tender values accept weak integer tokens. When the 3× rule drops the labelled total, that number becomes the result. The 3× rule can drop it whenever the item sum counts only a few rows: rows without letters (column blocks) and rows whose decimals OCR lost are not counted. Results:
    - `Sample Cafe\nLatte\nCroissant\n90.00\n60.00\nDelivery 10.00\nBag 1.00\nTotal 161.00\nVisa ****4321` gives **4321.00** (main gave 161.00).
    - The same text with `Card No 5123 45XX XXXX 4321` gives **45.00**.
    - When the total survives, the same misread card value contradicts it, so `Total 150.00\nVisa ****1234\nApproved 150.00` (a common POS slip) is downgraded to 400.
  - **Required change.**
    - A tender value must be a strong amount (decimal or currency marker) and must not directly follow a mask (`*`, `x`, `•`).
    - The lone-card guess must never replace a labelled total with a weak number.
    - The 3× rejection should not discard the only labelled total because of a sum over a few rows.
    - Add fixtures for the three texts above.
- **M2.** `receipt_parser.dart` `_pickTotal` (the contradiction count).
  - **Issue.** A correct total on a discounted receipt is now downgraded to a guess (fallback template, 400), because it sits below the item sum and nothing confirms it. Discount lines are ignored in the check.
    - `Latte 2 45.00 90.00\nCroissant 2 30.00 60.00\nSubtotal 150.00\nDiscount 15.00\nTotal 135.00\nCash 200.00\nChange 65.00` gives 135.00 at 400 (main: 600).
    - It also happens with no tender at all, and with Arabic `خصم … الاجمالي`.
    - It does not happen when a card tender matches.
  - **Required change.** Read discount values like the other cross-check values. Count `item sum − discount` (and `net − discount + VAT`) as a confirmation, or at least treat items as neutral when a discount line exists. Add an en fixture and an ar fixture.

**Minor (follow-up)**
- **FU-352.** A card tender that includes a tip (`Total 150.00`, `Tip 15.00`, `Card 165.00`) contradicts the total and downgrades it to 400. The amount is still right; consider letting a tip line explain the difference.
- Tests: all 20 new fixtures and every T-260/T-261 fixture pass. The 500-repeat adversarial timing test passes.

---

## T-271: salary currency drives the payday (C3)

Verdict: **APPROVED**

**Production diff.** `salaryCurrencyOf` counts salary months per currency in the newest 3 salary months.
- On a tie it picks the primary currency; if the primary is not among the tied, it picks the currency with the newest credit, then the smaller code, so the result does not depend on input order.
- `detectPaydayForSalary` passes the chosen currency to the unchanged `detectPayday`, and `PaydayAutoService` now calls it.
- It reads only dates and currency codes; no amounts and no conversion are involved. No schema change.
- The builder's reading of "first salary of the month" (within the chosen salary currency) is recorded in the task file and is reasonable.

**Tests:** the domain group (7 cases), `payday_auto_test` and `salary_usd_ingest_test` (Arab Bank USD SMS gives income, USD, `sys:income`, payday auto-set and the banner) all pass.

**Minor (follow-up)**
- **FU-351.** `payday_detection.dart:64-68`. The doc comment of `_latestFirstDays` ("The first salary date of each month…") now sits above `_monthKey`. Move it back.

---

## Cross-task minor (follow-up)

- **FU-349.** `docs/02-design/copy-deck.md` lacks these new keys:
  - `captureScanCamera`, `captureScanGallery`, `captureScanCameraDenied`, `captureScanWhatIRead*` (T-264)
  - `transactionsInstapayTitle/To/From` (T-265)
  - `native_android_shareMultipleFirstOnly` (T-263)
  - `NSCameraUsageDescription` (T-264)

  Also, `transactionsInstapayTo` (ar) "إلى {name}" is standard Arabic; Egyptian colloquial would say "لـ {name}". The task text named إلى, so this is for the PO/copy owner to confirm.

## Fix round

| Lane | Findings | Expected size |
|------|----------|---------------|
| app UI/l10n (T-262) | B1 | 1 line: Lead delta check |
| parsing (T-267) | M1, M2 + fixtures | over 30 lines: delta-only Sonnet re-review |

---

## Delta re-review (Sonnet)

Scope: `git diff 7d81e534 b088cdd7 -- packages/zaghlol_parsing` (T-267 fix, `receipt_parser.dart` +81/−18, 8 new fixtures) and commit `7d81e534` (B1).

Checks (worktree at `b088cdd7`): `dart analyze --fatal-infos` clean; `dart test` in `packages/zaghlol_parsing` 1740 pass (all new fixtures included); `flutter test test/features/home/presentation/home_screen_test.dart` 31 pass.

### Verdicts

| Finding | Verdict | Note |
|---------|---------|------|
| B1 (home empty-filter test) | **RESOLVED** | One-line test change to `this month`; the test file passes. |
| M1 (masked card digits, card guess) | **RESOLVED** | Tender values now need a strong amount (`strongOnly`), digits next to a mask or after `Card No` / `رقم البطاقة` are not amounts, and the 3x rule keeps a lone labelled total when price-only rows make the item sum doubtful. |
| M2 (discount contradicts total) | **RESOLVED** | Discount is read as a strong tender-style value and counted in `net − discount + VAT` and `itemSum − discount` (and the all-priced-rows sum). |

New blocker/major: **none.** One new minor (FU-353) and two small ones below.

### Probe table (`ParsingPipeline.parseOcr`, scratch test, not committed)

Format: new result; where old (`b088cdd7^1`) differed it is shown.

| Text | New | Old |
|------|-----|-----|
| `… Total 161.00` + `**** **** **** 4321` | 161.00, 600 | 161.00, 400 |
| `… Total 161.00` + `xxxx-4321` | 161.00, 600 | 161.00, 400 |
| `… Total 161.00` + `Visa 4321` | 161.00, 600 | 4321.00, 400 |
| `… الاجمالي 161.00` + `رقم البطاقة 4321` | 161.00, 600 | 4321.00, 400 |
| `Latte 60.00 / Croissant 90.00 / Card 150.00` (no total label) | 90.00, 400 | same (pre-existing) |
| `Card 150.00` alone | unrecognized | same |
| `Total 150` with integer items | 150.00, 600 | same |
| `Total 150` / `Cash 200` / `Change 50`, integer items | 150.00, 600 | same |
| `Total 150` alone | 150.00, 600 | same |
| `Discount 10% 15.00`, total 135.00 | 135.00, 600 | 400 |
| integer discount `Discount 15` / `Total 135` (with and without cash) | 135.00, 600 | same |
| `Discount 10%` only, total 135.00 | 135.00, 400 | same (no amount to confirm; acceptable) |
| discount 50 larger than items 30, `Total 30` | 30.00, 600 | 30.00 |
| same, wrong `Total 1.00` | 1.00, 600 | 1.00, 400 (see FU-354) |
| Net 150, discount 15, VAT 18.90, `Total 153.90`, cash 200 | 153.90, 600 | 400 |
| Net 150, discount 15, VAT 21, `Total 171.00` (total ignores discount) | 171.00, 400 | 600 (see FU-354) |
| items 150, discount 100, `Total 50.00` | 50.00, 600 | 400 |
| items 150, discount 15, `Total 150.00` | 150.00, 600 | same |
| `Total 150.00` + `Approved 150.00` | 150.00, 600 | 400 |
| `Approved Total 150.00`, `Authorization Total 150.00`, `Authorisation 123456` after a total | 150.00, 600 | same |
| `Total Approved 150.00` with 2 items | **90.00, 400** | 150.00, 600 |
| `Amount Approved 150.00` with 2 items | **90.00, 400** | 150.00, 600 |
| `Total Approved 150.00` / `Total Amount Approved 150.00` alone | **unrecognized** | 150.00, 600 |
| `Card 45XX 1234`, `Visa XXXX4321 150.00`, `Total 150` + `Card 150`, `Tax ID **** 150.00`, `* Total 150.00`, `Max Total 150.00`, `Latte x 60.00` / `xx 60.00` | 150.00, 600 | same |
| Pharmacy PO layout (`الإجمالي: 573.00 الخصم .00`) | **573.00, 600** | same |
| Restaurant PO layout (Net Sales / VAT / Amount Due 436.00 / Paid 0 / Visa 436.00 / Change 0) | **436.00, 600** | same |

### Findings

- **FU-353 (minor, money, low confidence only).** `receipt_parser.dart:39` (`_skipLine`). The new skip words `approved|approval|authori[sz]ation` hide a real total when the word sits on the total's own line and no other total label exists: `Total Approved 150.00`, `Amount Approved 150.00` and `Total Amount Approved 150.00` now give a wrong item amount (90.00, fallback, 400) or no result, where the old code read 150.00 at 600. This is the "can the new words hide a real total" case. It is not silent: the amount is a 400 guess that always needs review, or the receipt falls to manual entry. It is a rare layout (most slips have a plain `Total`), so not a major. Suggested change: let a line that also holds a total label win over the `approved` skip word, or limit the skip to a line that has no total label.
- **FU-354 (minor).** `receipt_parser.dart` `_pickTotal`. With a discount at or above the item sum, `c < itemSum − discount − 1` can never contradict, so a wrong tiny total passes at 600 (`Latte 10 / Croissant 20 / Discount 50 / Total 1.00`). A receipt whose total ignores a printed discount (`Total 171.00` with net 150, discount 15, VAT 21) now drops from 600 to 400 (amount is still right). Both are contrived; consider clamping the item-sum floor at the largest single item.
- **FU-352** (tip on a card tender, from the first round) is unchanged and still open.

### Lead action

Verdict for the delta: **APPROVED** for B1, M1 and M2. No fix round needed; FU-353 and FU-354 go to the follow-up list.
