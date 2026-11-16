# Batch 30 review (code + security)

Diff: `git diff origin/main...origin/batch/2026-11-16-30`. Reviewer: Opus (batch has a C4 task).
Tests run on the merged tree: `flutter test --exclude-tags benchmark,golden test/ingestion test/features/ingestion test/features/transactions test/features/budget test/features/home test/core test/app/budget_route_test.dart`: 1903 passed. `packages/zaghlol_parsing` `dart test`: 1477 passed.

## task/SMS-auto (C4, ingestion / money): CHANGES_REQUESTED

I ran adversarial synthetic bodies through the real pipeline (bundled registry, Guard base, `IngestWorld`, sender `NBE`, background origin). Template paths, duplicate detection, OTP, decline, D-28 bracketed FX, limit-before/after-amount, refunds, statement/minimum-due and the AR/EN settlement legs all behaved correctly. Two paths auto-save a wrong transaction with no review item:

| Body (synthetic) | Result |
|---|---|
| `Your card ending 1234 was used for a payment of EGP 500.00 at VODAFONE. Thank you for banking with NBE` | auto-saved `transfer_in` 500 EGP, no review |
| `Purchase of EGP 750.00 at AMAZON on your card ending 1234. Thank you for your payment` | auto-saved `transfer_in` 750 EGP, no review |
| `Payment of EGP 900.00 at CARREFOUR with your card ending 1234 was reversed and credited` | auto-saved `transfer_in` 900 EGP, no review |
| `Get 10% cashback! Pay EGP 500 with your card ending 1234 at NOON before 30/11` | auto-saved `income` 500 EGP, no review |

### Findings
- **MAJOR (money), S1** `packages/zaghlol_parsing/lib/generic/generic_parser.dart:230-241` (`_settlement`) and `:122-123`. The received-side settlement fires on any card word plus (`payment` and `thanks`/`thank you`/`credited`/`posted`) when no debit word appears. It then **overrides** the keyword direction (`was used`, `purchase`, `at MERCHANT`). Card purchases come out as `transfer_in` into the card: the wrong sign, and the spend drops out of the totals. Because `ccPayment` has a direction and no reason, `genericAutoSaveEligible` saves it with no review. A reversal reads the same way. Required change: the settlement result must not override a contradicting keyword direction. When an expense, purchase or "was used" cue sits near the amount, or a reversal cue is present, add `directionConflict` (goes to review). Drop the loose `_paymentWords` + received-verb fallback, or require it to sit inside a settlement phrase next to the amount.
- **MAJOR (money), S2** `packages/zaghlol_parsing/lib/generic/generic_policy.dart:68-84` (`genericAutoSaveEligible`). The rule has no positive "money already moved" requirement. A promo that misses the short `promoKeywords` list but carries an income word (`cashback`) auto-saves phantom income. The PO row says a promo cue goes to review. Required change: auto-save only when a `completedTransactionCues` hit (or a settlement phrase) is present. Otherwise the message goes to review.
- minor `app/lib/features/ingestion/presentation/review/review_screen.dart:797-801`: the "show original" tile reuses `ingestionReviewUnreadShow` ("Show message" / "شوف الرسالة"). The wording is acceptable in both languages, but there is no hide label. Add `ingestionReviewOriginalShow/Hide` (follow-up).
- minor `app/lib/features/ingestion/application/ingest_raw_messages.dart:368-378` with the `!autoSave` branch at `:1389`: on re-parse, a review row whose generic result is not confident (or is a likely duplicate) goes through `_persist`, and that can add a second open review item next to the old one. It happens once per registry bump. Follow-up: resolve or reuse the existing item.
- Verified OK: a raw row maps to at most one txn (the `promoteRaw` status guard). Dismissed and manually resolved rows leave `review`, so they are not re-promoted. A second job run examines 0 rows. The cross-channel duplicate goes to review. `dedupeKey` is set. The raw body is read only into the card model (`review_providers.dart:310`), with no logging or export. Settlement legs are `transfer_in`/`transfer_out`, never expense or income. No `double`.

## task/UI-fix30: APPROVED
- The budget route is wrapped in `BudgetRouteScaffold` (Scaffold/Material). The route test covers en, ar and dark.
- `ZHaptics` is centralized. Add fires once (the shell `_openAdd` tick was removed), and nothing fires from build or loops.
- nit `app/lib/core/ui/z_haptics.dart:10`: the mutable static `enabled` is a global. Move it to a provider when a setting exists.

## task/BRAND-logos: APPROVED
- No logo files are bundled (`assets/brand/logos/` holds only `.gitkeep`). `LOGOS.md` requires written permission before any logo is added. `readableOn` picks the higher-contrast ink. Malformed JSON rows are skipped.
- minor `app/lib/core/ui/institution_avatar.dart:17`: for mid-tone brand colours the better of white and ink can still fall below 4.5:1. Initials are bold caption text, so this is acceptable. Follow-up: assert at least 3:1 in a test over `institutions_brand.json`.

## Fix list (blocking)
| Task | File:line | Required change | Test to add |
|---|---|---|---|
| SMS-auto | `packages/zaghlol_parsing/lib/generic/generic_parser.dart:122,230-243` | The settlement result must not override a contradicting expense, purchase, "was used" or reversal cue; add `directionConflict` instead; tighten the `payment` + verb fallback | e2e: the first 3 bodies above (sender NBE) go to review with no txn |
| SMS-auto | `packages/zaghlol_parsing/lib/generic/generic_policy.dart:68` | Require a completed-transaction cue (or settlement phrase) for auto-save | e2e: the cashback promo body goes to review with no txn |
