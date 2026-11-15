# Batch 25b review: T-158 import flow, T-169/T-170 Smart ROI

Reviewer: code-reviewer (code + security). Tree: `batch/2026-11-15-25`. Ran `flutter test --exclude-tags benchmark,golden test/features/roi test/features/export_import test/tool` (all pass) and `dart test test/roi` in `zaghlol_domain` (21 pass).

## T-158 Import flow (S-67): CHANGES_REQUESTED

AC map: mockups 32-34 are built (source list, summary sheet, done screen) with the design-shot tests. Free users get the paywall (`import_source_screen.dart` `_start`, checked before the picker opens). Statement sources are `available: false`, so they show disabled with "coming soon" and their tap is null. The dry run (`ImportCsvUseCase.run(dryRun: true)`) inserts nothing. Under `dryRun` the duplicate multiset logic still runs, so the preview counts match the real run.

Security/privacy: `file_picker` uses the system document picker with no permission added. `SystemImportFilePicker.pick` reads the bytes and calls `FilePicker.clearTemporaryFiles()` in `finally`, so the temp copy is removed even on a read failure. `PickedImportFile.toString` and `ImportFlowException` carry no content or path. No logging.

### Findings

1. **BLOCKER (money): no transfer-pairing or refund-matching hook after a CSV import.** `import_ports.dart` (`importRunnerProvider`, last provider) builds `ImportCsvUseCase(DriftCsvImportStore(...))` without `onImported`. T-155 added that hook for exactly this (`import_csv.dart:159-164, 259-264`, from the batch-16 fix "re-pair after CSV import"). T-158 is the first production caller, so no path runs it. Imported rows are inserted as plain transactions. A transfer between the user's own accounts, such as a debit leg and a credit leg in the file, stays unpaired and counts as spending and income. Imported refunds are not matched either. The other ingest paths pair after persist: `transferPairingUseCaseProvider` and `refundMatchingProvider` in `txn_list_providers.dart`, and `afterPersist` in `ingest_raw_messages.dart`.
   - Required change: in `importRunnerProvider`, pass `onImported: (id) async { await pairing.onPersisted(id); await refunds.onPersisted(id); }`, using `transferPairingUseCaseProvider` and `refundMatchingProvider`. Check the refund method name at that point. A failure in the hook must not fail the already-committed import. Catch it and still return the summary.
   - Test: a provider-level test, using a real in-memory DB, that commits a CSV through `importRunnerProvider` and holds both legs of a same-amount transfer between two own accounts. Assert both rows end up linked as a transfer pair and are excluded from spending totals. Also assert that a duplicate-only re-import triggers no pairing.
2. Minor: `import_ports.dart` `commit` returns no `autoCategorised`, `needReview` or `topCategories`. The done screen hides the tiles, as the builder documented. This is acceptable, but the mockup 34 stat tiles never show for the only working source.
3. Minor: the S-67 export half, the target-card "Change" action and the PDF password step are not built (builder notes). They are follow-ups.
4. Nit: `app_screens.dart` imports `export_import/...` before `budget/...`, so the imports are out of alphabetical order. Format passes, so ignore it.

## T-169 Smart ROI rules + T-170 screen: APPROVED (with minors)

AC checks:
- **No names in any tip (ar/en):** `roi_no_names_test.dart` folds Arabic letter variants and strips one-letter prefixes and "ال". It checks the copy-deck `roi_*` rows against the institution registry and the merchant catalog. Suggestions carry only `RoiProductKind` enums and keys, never names. OK.
- **Per-currency figures:** `RoiSignals` throws on a currency mismatch. `evaluate` returns nothing when the assumptions are for another currency. `roiSignalsFrom` filters the charts, accounts and credit limits by currency. The assumptions are built in for EGP only, so other currencies get no tips and nothing is converted. All figures are integer `Money` with half-even rounding. No `double` money. `staplesRuns` uses a `double` division of a count, which is not money. The screen shows one currency at a time and never sums.
- **Flag off hides everything:** `roiSuggestionsProvider` returns empty before any query. `RoiTipsScreen` and `RoiTipsView` build `SizedBox.shrink`. `roiTipCountProvider` returns 0. Tested.
- **Disclaimer on every tip:** the full text is on top, and a summary line sits on each card. Tested with 2 tips, 1.3x text scale, ar and en.
- **Gold gate:** Free users see a locked preview and the paywall trigger. It reuses `deepCoaching`, because no ROI capability exists.
- **Rule 2 erratum:** the code keeps 22,200 (the spec's own inputs) instead of the printed 19,500. It is noted in the T-169 task file as a "Lead decision". It is not recorded in the SRS errata or the spec notes (minor, see 5).

### Category guesses (asked: acceptable?)
Dining -> delivery (rule 2) is acceptable behind the off-by-default flag. The tip is general ("cook at home, a home appliance, an installment plan") and carries a disclaimer. It will overstate for restaurant diners. Transport -> ride-hailing (rule 5) is weaker. Transport includes fuel, tolls and public transport. A car owner's fuel spend above 4,500 EGP/month would be told a vehicle installment plan beats ride-hailing, which is wrong advice. Suggest feeding rule 5 only from ride-hailing merchant groups (as the builder did for rules 1 and 3) and leaving it silent until then, or at least switching it off before the flag goes on. Neither is blocking now, because the flag is off at launch and the advice is not financial data. Rule 1 and rule 3 stay silent, which is correct. The idle-days proxy (`as_of` of the newest cash balance) resets on every balance refresh, so rule 4 can fail to fire. The error is on the quiet side, so it is harmless.

### Findings (all minor)
5. `roi_providers.dart` (transport -> rule 5 signal): see the guess note above. Leave rule 5 silent until a ride-hailing group exists. Also record the rule-2 erratum in `docs/01-requirements/` (open-questions or errata) so the spec and the code agree.
6. `roi_tips_providers.dart` `RoiDismissed`: "Not for me" lasts the session only (a documented deviation). Follow-up: persist it in settings.
7. `roi_tips_providers.dart` `roiShareOpenerProvider`: Share opens the studio with no ROI template. A follow-up for S-73. The tip's figures are not passed, so nothing leaks.
8. Legal sign-off on the disclaimer text (Q-23) is still open. It must be settled before the flag turns on. It is not a code blocker.
9. Not wired: the Tips segment on Ask and the badge (`roiTipCountProvider`). Fine while the flag is off.

## Fix list (blocking only)

| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| T-158 | `app/lib/features/export_import/presentation/import_ports.dart` (`importRunnerProvider`) | Pass `onImported` to `ImportCsvUseCase`. It must run transfer-pairing `onPersisted` and refund matching for each inserted id, after the commit. A hook failure must not fail the import. | Provider-level test with a real DB. Import a CSV holding a transfer's two legs between two own accounts, and assert the pair is linked and excluded from spending. A duplicate-only re-import triggers no pairing. |
