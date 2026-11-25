# Batch 74 review (T-260, C3) — reviewer: Opus

Branch `batch/2026-11-25-74` @ e7a46e95 vs main 1d69f761. Production diff read; AC→test map checked; tests run.

Runs: `dart analyze --fatal-infos` clean; `dart test` zaghlol_parsing 1700 passed; `flutter analyze` clean; `flutter test -x golden test/features/capture` 305 passed. No `zaghlol_lints` package dir found in this tree (skipped).

## T-260 — Verdict: CHANGES_REQUESTED (1 major)

### Findings

**M-1 (major) — `receipt_parser.dart` `_totalLabel` (new bare `amount` / `net`) + `_skipLine`: tender lines read as the total.**
The new bare label `amount` matches `Amount received 200.00` and `Amount returned 50.00`; neither word is in `_skipLine`, and the last label that yields an amount wins. Adversarial probes through `ParsingPipeline.parseOcr`:
- `Pharmacy\nTotal 150.00\nAmount received 200.00` gives **200.00** (cash paid), template `ocr.receipt.generic`, confidence 600.
- `Pharmacy\nTotal 150.00\nAmount returned 50.00` gives **50.00** (change).
- `Pharmacy\nTotal 150.00\nTotal Savings 15.00` gives **15.00** (`total` is not subtotal).
Before T-260, `amount` was not a label, so the first two are regressions. This is exactly the "cash paid / change picked instead of total" risk. Nothing auto-saves, but the screen shows it as a normal read, not a guess.
Required change: add `received|returned|refund(ed)?|savings?|saved|balance|tender|المستلم|المرتجع|توفير|الرصيد` (folded) to `_skipLine`, or drop the bare `amount` label unless the line has no tender word. Add 3 fixtures (the above) to `test/ocr/pharmacy/`.

### Checked, no issue
- Phone, date, time, quantity (`x2`, `qty`), `%`, 6+ digit codes and zero-padded tokens are removed from candidates. Probes OK: `Hotline 19123` between label and amount gives no read; `Total 14:35 150.00` gives 150.00; `Tax ID 123-456-789` gives 99.00; `Total 3 items` gives no read. Subtotal/VAT/cash/change lines are skipped (`cash`, `change`, `نقدا`, `الباقي` probes OK). Money is `Money` minor units via `parseAmount`; no `double`.
- Bank/wallet templates still win: `parseOcr` tries registry institutions first; the generic reader is the last resort. Existing OCR/template tests unchanged and green.
- Nothing auto-saves: the fallback has confidence 400 and template `ocr.receipt.fallback`. `_enterAmount` only pushes `TransactionEditScreen` with a prefill (merchant/date, source ocr). A lone bare line item stays unread.
- ReDoS/time: regexes have no nested quantifiers; label scan capped at 40; probes with 2000 lines of repeated labels, label/number columns and Arabic column blocks ran in about 0 ms each.
- l10n: new ar/en strings in ARB, ar is Egyptian colloquial; no hard-coded strings in the screen. `ScanDiagnostics` holds counters only; `ScanNoTotal.toString` is redacted.
- `ScanEmpty` removed: the only `ScanOutcome` switch is in `scan_confirm_screen.dart` (updated; analyze exhaustive). The share-text path in `scan_service.dart` returns `ScanNoText` / `ScanNoTotal`. No other references.

### Minors (follow-ups)
- **FU-338 (minor):** the last-resort fallback takes the largest strong amount, so on a receipt with no total label it can pick a card/cash line (`Card 200.00` over items 25.00 and 90.00 gives 200.00). Confidence 400 and the confirm screen contain it; consider skipping `card|visa|mastercard|بطاقه|فيزا` lines.
- **FU-339 (minor):** `Net 110.00` after `Total 120.00` + `Discount 10.00` wins over Total (last label wins). Probably right for net-after-discount; confirm with the PO on a real-layout sample.
- **FU-340 (nit):** the `scan_confirm_screen.dart` header comment line is over 80 chars (format passes, but wrap it).

## Lead delta check
(pending fix of M-1)
