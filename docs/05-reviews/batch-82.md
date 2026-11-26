# Batch 82 review (T-292, C2)

Reviewer: code-reviewer (Sonnet). Branch `batch/2026-11-26-82` at c19359689.
Checks: `flutter analyze` clean; `flutter test -x golden test/features/mascot test/features/widgets_bridge test/core/db test/app`: 1074 passed, 1 skipped. Kotlin hand-traced (compiles in CI only).

## T-292 — Verdict: APPROVED

| Item | AC / test | Result |
|------|-----------|--------|
| FU-391 | `rive_preload_test.dart` (first frame, in-app reduce, platform flag) | OK |
| FU-392 | `OcrMergerTest.anUnrelatedShortDigitLineOnTheSameBoxDoesNotBlockTheArabicAmount` | OK (traced) |
| FU-393 | `widget_snapshot_builder_test.dart` FU-393 | OK; device check still owed (recorded in task and docs) |
| FU-394 | `financial_c_daos_test.dart` counting interceptor, 551 ids -> 2 selects | OK |

### Traces
- FU-391: `RivePreloadOnFirstFrame` sits inside `ProviderScope` (main.dart), `initState` only registers one post-frame callback, `build` returns the child: no rebuild loop, no provider read before the scope. `mounted` guarded. Reads `ref.read(reduceMotionProvider)` and `MediaQuery.maybeDisableAnimationsOf(context)` (the implicit View's MediaQuery, available above MaterialApp; null falls back to the dispatcher flag).
- FU-392 new test: "Total Amount" and "Ref 12" both strong and both match the Arabic box. For "Total Amount", `strongAmountOverlaps` sees "12": AMOUNT matches, no decimal, 2 digits -> not amount-like -> false, so `٨٥٫٥٠` is appended as `85.50`. "Ref 12" is already `appended` -> kept. Result `["Total Amount الإجمالي 85.50", "Ref 12"]` as asserted.
- Existing `382.46` case (line 171): "382.46" is amount-like (decimal, last char digit), overlap 1 -> guard holds, noise `321146 535` not appended; `arabicWords` yields nothing; result unchanged. `latinReceiptKeepsTheMlKitLines` lines carry their own digits, unaffected. `Ref 1436` test unaffected (replacing path).
- FU-393: arabic "٧ أيام على القبض · + USD" (one code) stays under 32; two codes or `+N` drop the hint in Arabic and English. Accepted trade-off, see FU-395.

### Findings

- **minor** `OcrMerger.kt:~203` (`amountLike`). Integer amounts of 1-2 digits with no decimal are no longer "amount-like", so the guard no longer protects them. Input: latin boxes `Total Amount` and `85` (same row), credible Arabic line `الإجمالي ٣٢١٤٦` at conf >= 0.60 over both: the Arabic digit token is now appended, giving `Total Amount 32146` next to `85`. Before the change it was blocked. Needs noise >= 0.60 (PO photo noise was <= 0.56), so rare; small EGP prices are common. Suggested: treat a bare digit token as amount-like when it is the whole token of a strong line with no other letters (or any digit token on a line that also holds an amount word). -> FU-395.
- **nit** `widget_snapshot_builder.dart:~154`. The 32 budget counts the LRI/PDI wrappers and applies to every widget size, so the 4x1 widget also loses the hint with two codes. Intended per the task; revisit after the owed device check. -> FU-396 (device check, already owed).

### Follow-ups
- FU-395 (minor): amount-like guard for 1-2 digit integer amounts (above). Owner: next OCR task.
- FU-396 (nit): after the 2x1 device check (ar/en), tune `widgetSmallLineBudget` and consider per-size budgets.

No blockers or majors.
