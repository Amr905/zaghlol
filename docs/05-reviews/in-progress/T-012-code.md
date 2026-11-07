# Review — T-012 Money and Currency value types with ISO 4217 table

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer |
| Date | 2026-11-07 |
| Commit / diff | Round 1: `e36b9d55` (`git diff origin/main...origin/t012`). Round 2: `1e44bb9` (`git diff e36b9d5 origin/t012`, 9 commits, 20 files, +945/−145). |
| CI | Round 1: run 42315952269, 13/13 green, 121 domain tests. Round 2: run 42352828411, 12/13 green. In the job "format, analyze, unit tests", format and analyze pass, 155 domain tests pass and 1 fails. The failure is the intended merge gate `iso4217_snapshot_gate_test.dart:17`, with the message "placeholder snapshot still in place". Because of it, the `zaghlol_parsing` test step is skipped; that package is unchanged since main. |
| Verdict | **APPROVED pending genuine SIX snapshot.** The only blocking item is the snapshot gate (see "Merge conditions"). |

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| KWD 1.250, BHD 0.375, JPY 1500 round-trip exactly | PASS | `money_test.dart` "AC: exact round trips". Property 8 covers canonical string, storage, `fromJson` and `tryFromJson`. |
| Adding EGP to USD throws CurrencyMismatch | PASS | `money_test.dart` "AC: currency mismatch". Property 3. |
| allocate never loses or creates a minor unit | PASS | Properties 4–7. Round 2 adds an exact comparison with a Hamilton oracle, edge weights including Σw > 2^63, and an equal-weights tie property. |
| DoD: analyze clean, formatted, tests, no `double`, no raw SMS in logs | PASS | CI format and analyze steps pass. The scanner is hardened (CR6). There is no UI, so RTL and goldens do not apply. |
| Design note: overflow, `roundDiv`, allocation, equality, parsing boundary, serialization | PASS | Traced by hand in round 1. Round 2 changes re-traced (see the Round 2 section). |
| Design note: ISO table pipeline | PASS, gated | Codegen is byte-identical, XML verification and the independent oracle pass, and the append-only, exponent-guard and `--fresh` tests pass. The gate test fails on purpose until the genuine snapshot is committed. |
| Featured codes per SRS (A-59, FR-CUR-01/07) | PASS (round 2) | `currency.dart:41-52` lists the 10 codes in A-59 order; test `iso4217_table_test.dart` "featured codes are active, in A-59 order". |

## Findings (round 1, at `e36b9d55`)
| # | Severity | File:line (round 1) | Issue | Required change | Owner | Round 2 status |
|---|----------|---------------------|-------|-----------------|-------|----------------|
| CR1 | major | `lib/money/currency.dart:39-49` | `featuredCodes` used the D-22 eight; A-59 adds GBP and INR. | Use A-59 order; update the tests. | T-012 + architect | **Resolved** |
| CR2 | major | `tool/gen_currencies.dart:126-135, 209-218` | Replacing the reconstructed snapshot through an append-only merge would keep invented codes as permanent historic rows, and no mechanical gate existed. | Add `--fresh`, a published-date gate test, and a procedure for `_baselineCodes` and the code diff. | T-012 | **Resolved** (procedure items at swap time) |
| CR3 | minor | `tool/gen_currencies.dart:126-135` | A changed exponent or numeric was overwritten silently. | Throw unless the code is explicitly allowed; add a test. | T-012 | **Resolved** |
| CR4 | minor | `lib/money/money.dart:165-170` | `allocateEven` allocated the list before checking the part cap. | Check the cap first; add a test. | T-012 | **Resolved** |
| CR5 | minor | `lib/money/multi_currency_total.dart:14-38` | Overflow behaviour depended on input order at the range bound. | Sum exactly and check the range once; add a full-range property. | T-012 | **Resolved** |
| CR6 | minor | `test/money/no_floating_point_test.dart:7` | The scanner missed `/`, float literals, `toStringAsFixed` and `pow`. | Strip comments and strings, then extend the patterns. | T-012 | **Resolved** (one gap left: R2-1) |
| CR7 | minor | `test/money/generators.dart:8` | One shared `ExploreConfig` meant shared random state between properties. | Create a fresh config per property. | T-012 | **Resolved** |
| CR8 | minor | `test/money/generators.dart:147-179` | No edge pool for weights and no tie-break property. | Add an edge pool, a tie property and a Hamilton oracle. | T-012 | **Resolved** |
| CR9 | minor | `lib/money/money_errors.dart:20-55` | `reason` and `op` were free strings. | Make them enums. | T-012 | **Resolved** |
| CR10 | nit | `lib/zaghlol_domain.dart:4` | `largestRemainderSplit` was exported publicly. | Move it to `src/`, or declare it in the note. | T-012 | **Resolved** |
| CR11 | nit | `lib/money/money.dart:163-164` | The "larger shares first" wording was wrong for negative amounts. | Reword. | T-012 | **Resolved** |
| CR12 | nit | `test/money/money_test.dart:167` | No test for a negative denominator. | Add one. | T-012 | **Resolved** |
| CR13 | nit | `docs/04-tasks/tasks/T-012.md` | Accepted deviations are not recorded in the design note. | Amend the note. | solution-architect | **Open** (doc-only; the branch changes no docs) |

## Round 2 (at `1e44bb9`)

### Verification of round 1 findings
- **CR1:** `currency.dart:41-52` has the D-22 eight plus `'GBP', 'INR'`, with doc comments citing A-59. The `orderedFor` expectation is now `AED EGP USD SAR GBP CHF`, and the doc comment in `multi_currency_total.dart` is updated.
- **CR2:** Covered by five changes:
  - `main` accepts `--fresh` (`gen_currencies.dart:319, 331`), which skips the committed JSON.
  - The header comment documents the swap: use `--fresh` exactly once, regenerate `_baselineCodes`, and list changed codes in the PR.
  - `iso4217_merge_test.dart` checks that a merge with no previous table returns exactly the snapshot.
  - `iso4217_snapshot_gate_test.dart` requires `YYYY-MM-DD` and a date ≥ 2025-09-01. The sentinel `2000-01-01` makes it fail.
  - Comment stripping happens before matching, so the sentinel text inside the XML header comment cannot be picked up as the `Pblshd` attribute.
- **CR3:** `mergeAppendOnly` throws `FormatException` when an existing code's exponent or numeric changes, unless the code is in `allowChanged` (`--allow-change=`). The test covers exponent, numeric, the allowed case, a wrong allow-list and the no-change case.
- **CR4 / F1:** `allocateEven` rejects `parts <= 0 || parts > maxAllocationParts` before calling `List.filled`. Tests cover `maxAllocationParts + 1`, `1 << 40`, `1 << 62` and −1.
- **CR5:** `_sum` adds per currency in `BigInt` and range-checks once, throwing `MoneyOverflow(…, MoneyOp.sum)`. `of`, `add` and `+` all use it. Coverage:
  - The example test `[max, +1, −1]` / `[max, −1, +1]` covers order, and also `add` and `+` overflow.
  - A full-range property asserts that the outcome (value or overflow) is the same under reversal and shuffling, and that the result is non-null exactly when the BigInt per-currency sums fit.
- **CR6 / F4:** The scanner now removes comments and string literals (`//`, `/* */`, single, double, triple-quoted and raw strings). It then forbids:
  - `double` and `num`;
  - `toDouble`, `parseDouble` and `toStringAsFixed`;
  - `pow(`;
  - a lone `/`, including `/=`;
  - `\d+.\d+`, `.\d` and exponent literals.

  Self-tests cover both catching forbidden forms and ignoring comments, strings and safe forms. One gap is left: R2-1.
- **CR7:** `explore()` returns `ExploreConfig(numRuns: 1000, random: Random(42))` for each property.
- **CR8:** The weights generators now draw from `edgeWeights` 25% of the time: a single weight, all-equal weights, `maxMinor` weights, `[int64Max, int64Max, 1]` (Σw > 2^63) and `[2^62, 2^62, 0, 2^62, 3]`. `checkAllocation` adds two checks:
  - an equal-weights, non-increasing-by-index check;
  - an exact match against `_hamilton`, an independently written BigInt reference.

  A separate `equalWeights` property covers ties.
- **CR9:** `MoneyOp {create, add, subtract, times, mulDiv, sum}` and `CorruptMoneyReason {unknownCurrency, outOfRange, missingCurrency, nonIntegerMinor}`; `toString` prints `.name`. A test runs over every reason.
- **CR10:** `allocation.dart` moved to `lib/money/src/`. The barrel exports `src/allocation.dart show maxAllocationParts` only.
- **CR11:** The doc now says "lower indices receive the extra unit", and `allocate` lists its guarantees in its own doc comment.
- **CR12:** Tests cover `mulDiv(1, -3, …)` throwing `ArgumentError` and `mulDiv(-1, 3, floor)` returning −2.
- **CR13:** Still open. The design note is unchanged on the branch. This is non-blocking doc work for the architect; record the rulings below.

### Verification of security findings in my areas
- **F1 (allocateEven cap):** Resolved, as CR4.
- **F2 (`Pblshd` reaching generated source):** Resolved.
  - `checkPublished` requires `^\d{4}-\d{2}(-\d{2})?$` in `parseListOne`, `parseJson` and `mergeAppendOnly`.
  - Both renderers call `_validate`, which re-checks the date and every row, so a hand-built `CurrencyTable` cannot inject into source either.
  - Tests reject a newline, `*/`, a trailing space, `2026-1-1` and an empty value through both parsers and both renderers.
- **F3 (parse length):** Resolved. `maxParseLength = 64` (`money.dart:46`) is checked before the regex or any copy. Tests cover exactly 64 characters (accepted), 65 (rejected), and 1 MB inputs of zeros, sevens and nines.
- **F6 (non-throwing entry points):** Resolved. `tryFromStorage` and `tryFromJson` return null on:
  - unknown codes, lowercase codes, codes with spaces, and empty codes;
  - out-of-range values, including `1 << 63`;
  - wrong types and missing keys.

  `fromStorage` now calls `tryFromStorage` and maps null to the right reason. Both pairs are tested against the same bad-input table, and property 8 covers `tryFromJson`.
- **F9 (generator stripping and range checks):** Resolved. `_ignored` strips comments, CDATA and the DOCTYPE including any internal subset. `parseListOne` rejects minor units longer than one digit and numerics longer than three, then calls `checkRow` (numeric 1..999, exponent 0..4, code `^[A-Z]{3}$`). `parseJson` checks every field's type and the optional `fund` key's type. Tests cover hidden entries in comments and CDATA, a DOCTYPE, and bad rows (`978:5`, `978:10`, `000:2`, `1000:2`, lowercase codes, codes with a newline, exponent 9 or −1, numeric `'978'` or 0, bad status, `fund: 'yes'`). The quadratic rescan on a missing `</CcyNtry>` remains; it is a dev-time tool only, so I accept it.
- **Also checked:**
  - F5 (doc wording): `parse` doc now says it normalizes and that dedup must key on `toStorage`.
  - F7: "never log" warnings added to `toStorage` and `toJson`.

### Deviations from the design note (rulings)
| # | Deviation | Ruling |
|---|-----------|--------|
| 1 | `Currency.isFund` | Accept. D-51 / FR-CUR-07 need it to list funds last. |
| 2 | JSON `fund` key, written only when true; `parseJson` defaults it to false and type-checks it | Accept. |
| 3 | `Currency.all` (active and historic, sorted) | Accept. |
| 4 | `CorruptMoney(code, CorruptMoneyReason)` | Accept. The enum makes "no amounts in errors" hold by type. |
| 5 | `MoneyOverflow(currency, MoneyOp)`, including `sum` | Accept. |
| 6 | `fromJson` throws `CorruptMoney` and ignores extra keys (pinned by a test) | Accept. Being lenient about extra keys suits backup forward-compatibility. |
| 7 | `Money.tryFromJson` | Accept. This is the boundary API that F6 asked for. |
| 8 | `Money.tryFromStorage` | Accept. Same reason as 7. |
| 9 | Generated table is a const list of records | Accept. |
| 10 | `allocate` always uses BigInt | Accept. |
| 11 | `orderedFor` includes the primary currency only when it is present (pinned by a test) | Accept. Callers can still read `total[primary]`, which returns zero. |
| 12 | No-double scan: `\bnum\b` plus the extended pattern set | Accept. |
| 13 | Numeric uniqueness asserted for active rows only | Accept. ISO reuses withdrawn numerics. |
| 14 | `allocation.dart` under `src/`; only `maxAllocationParts` exported | Accept. |
| 15 | `MultiCurrencyTotal.isEmpty`, plus value `==`, `hashCode` and `toString` (codes only) | Accept. |
| 16 | `Money.maxParseLength = 64` | Accept. |
| 17 | `featuredCodes` = A-59's 10 codes | Accept. This is required by the SRS; the note is out of date. |
| 18 | `checkPublished` accepts `YYYY-MM` as well as `YYYY-MM-DD` | Accept. The gate test separately requires `YYYY-MM-DD` for the committed snapshot. |
| 19 | Generator CLI `--fresh` and `--allow-change=` | Accept; see R2-2 for a hardening suggestion. |
| 20 | `Money.toString()` returns `Money(<code>)` | Accept. |

**Leading zeros (more than 16 within the 64-character cap):** Accept. The note's grammar `-?[0-9]+` allows leading zeros, and the range check runs on the digits after the zeros are stripped. A test covers zero-padded `maxMinor + 1` being rejected. The input-length cap from F3 bounds the cost, and the behaviour is pinned by "leading zeros do not count toward the 16-digit cap". The non-canonical-input risk (F5) is documented on `parse`, and dedup must key on `toStorage` (T-046, T-155).

### New findings (round 2)
| # | Severity | File:line | Issue | Required change | Owner |
|---|----------|-----------|-------|-----------------|-------|
| R2-1 | minor | `test/money/no_floating_point_test.dart:23-60` | `stripCommentsAndStrings` drops interpolated expressions together with the string. So `'${minor / 100}'`, the most likely way a display-formatting double would sneak in, passes the scan. The doc comment admits this, but nothing enforces "interpolations stay plain identifiers". | Scan the bodies of `${…}` (keep the expression and drop only the literal text), or fail on any `${` whose body contains `/` or a float literal. Add `"'\${a / b}'"` to the must-catch samples. | T-012 (can be done after merge) |
| R2-2 | minor | `tool/gen_currencies.dart:319, 331` | `--fresh` skips both the append-only rule and the exponent guard. It is documented as one-time use, but nothing stops a later run from silently dropping codes or changing exponents. The `_baselineCodes` test catches deletions; it does not catch exponent changes beyond the oracle's 25 codes. | Make `--fresh` refuse unless the committed JSON's `published` is the sentinel `2000-01-01`, or unless an explicit `--i-know` flag is also given. Alternatively, after the swap, delete `--fresh` in a follow-up commit. | T-012 |
| R2-3 | nit | `tool/iso4217/list-one.xml:11` | The header comment says the date gate lives in `test/money/iso4217_table_test.dart`. It now lives in `iso4217_snapshot_gate_test.dart`. | Fix the path, or let it go when the file is replaced. | T-012 |
| R2-4 | nit | `lib/money/money.dart:18, 132, 293-294` | The `_create` and `_subtract` aliases for `MoneyOp.create` and `MoneyOp.subtract` exist only to keep lines short, while `add`, `times` and `mulDiv` use `MoneyOp.x` directly. The inconsistency is a small indirection. | Optional: inline them and let `dart format` wrap the lines. | T-012 |
| R2-5 | nit | `test/money/money_property_test.dart:357, 361` | The property names "weights 0..10^6" and "weights up to maxMinor" are no longer accurate, because both generators now also draw int64-scale edge weights. | Rename, e.g. "weights 0..10^6 + edges". | T-012 |
| R2-6 | nit | (process) | While the gate test is red, the CI job stops before `zaghlol_parsing` tests and any later steps run. A regression elsewhere in that job would be hidden until the swap. | Acceptable for now, since `zaghlol_parsing` is untouched. Do not merge other work onto this branch while it is gated. | Lead |

### Merge conditions
1. Commit the genuine SIX `list-one.xml` (Pblshd ≥ 2025-09-01, Amendment 180 or later).
2. Run `dart run tool/gen_currencies.dart --fresh` and commit the regenerated `currencies.json` and `iso4217_table.g.dart`.
3. Regenerate `_baselineCodes` in `test/money/iso4217_table_test.dart` from the new JSON.
4. In the PR, list the codes added, removed or changed versus the placeholder. Any exponent difference on a featured or oracle code needs reviewer sign-off.
5. Confirm the oracle, funds-set, exclusion and featured-active tests still pass on the real data. These tests are independent of the XML, so a wrong real-world assumption fails loudly rather than being absorbed.
6. CI fully green, with the gate test passing and `zaghlol_parsing` running.
7. The architect amends the design note (CR13) using the deviation rulings above. This should be done but does not block the code.

No re-review of the code is needed for items 1–6 if only those files change. Because this is a C4 task, the security-privacy-reviewer and test-engineer sign-offs are still needed.

## Checklist
- [x] `flutter analyze` clean (run 42352828411)
- [x] Tests added and passing: 155 pass; 1 intended gate failure
- [x] RTL + LTR verified: N/A (no UI)
- [x] No hard-coded strings: N/A (developer-facing errors only)
- [x] No `double` money, explicit currency (hardened scanner; R2-1 gap)
- [x] No sensitive data in logs (typed enums; codes only; never-log warnings on `toStorage` / `toJson`)
- [x] Stays within the task's scope (only `lib/money/**`, the barrel, `tool/` and `test/money/**` changed)

## Notes for the Lead
- Answers to the two snapshot questions from round 1, as of round 2:
  - *Is the pipeline robust?* Yes. It strips comments, CDATA and the DOCTYPE, validates every row, validates the date before any value reaches Dart source, guards exponent and numeric changes, and offers a fresh-build path plus a red gate until the real file lands. R2-2 is the remaining hardening.
  - *Are the exponent checks independent?* Still yes: the hard-coded oracle reads the runtime table, never the XML.
- The 15-item deviation list was not in the repo or in your message. The 20 rulings above come from my own comparison of the diff and the design note; please map the implementer's list onto them.
- R2-1 and R2-2 are minors and can ride with the snapshot-swap commit or go in a small follow-up. They do not block approval.