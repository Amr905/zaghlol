I reviewed T-012 at `e36b9d55`. The verdict is **CHANGES_REQUESTED** because of two major findings.

- **Featured list is out of date:** `featuredCodes` misses GBP and INR, which A-59 / FR-CUR-01 / FR-CUR-07 now require.
- **Snapshot swap would lock in bad data:** replacing the reconstructed XML with the real SIX file goes through the append-only merge. Any wrong codes from the reconstruction would stay in the table permanently as `historic`.

The arithmetic, `roundDiv`, allocation, equality, the parsing boundary and the no-amounts-in-errors rule are all correct. I accept all eight declared deviations. Full markdown for `/home/claude/zaghlol/docs/05-reviews/T-012.md` follows; I did not write any files.

---

# Review — T-012 Money and Currency value types with ISO 4217 table

| Field | Value |
|-------|-------|
| Reviewer(s) | code-reviewer |
| Date | 2026-11-07 |
| Commit / diff | `task/T-012-money` @ `e36b9d55`, reviewed as `git diff origin/main...origin/t012` (18 files, +3874). CI `app-ci` run 42315952269 at the same SHA: 13/13 jobs green; `zaghlol_domain` `dart test` passes 121 tests; `dart format --set-exit-if-changed` and `flutter analyze` pass. |
| Verdict | **CHANGES_REQUESTED** |

## Acceptance criteria
| Criterion | Result | Evidence |
|-----------|--------|----------|
| KWD 1.250, BHD 0.375, JPY 1500 round-trip exactly | PASS | `money_test.dart:24-44` covers parse ↔ canonical ↔ storage ↔ JSON, plus CLF 1.2345 and EGP -0.05. Property 8 (`money_property_test.dart:327-341`) runs 1000 inputs per path. |
| Adding EGP to USD throws CurrencyMismatch | PASS | `money_test.dart:51-63`. Property 3 (`money_property_test.dart:260-269`) covers `+`, `−`, `compareTo` and `<`, and `==` returns false. |
| allocate never loses or creates a minor unit | PASS | Property 4 (`money_property_test.dart:271-315`) checks the sum in BigInt, for small weights and for weights up to maxMinor. `allocateEven` is also checked. |
| DoD: analyze clean, formatted, tests added, no `double` money, no raw SMS in logs | PASS | CI job "format, analyze, unit tests" passes. `no_floating_point_test.dart` passes. No SMS handling in this task. No UI, so RTL and goldens do not apply. |
| Design note: API shapes, error classes, `toString` without amounts | PASS | It matches the note, apart from the declared deviations below and finding 10. |
| Design note: canonical ASCII parse, too many decimals rejected, `-0` → 0, Arabic-Indic digits rejected | PASS | `money.dart:40-89`. The regex is anchored and ASCII-only, `e=0` rejects any `.`, and lengths over 16 digits are rejected before `int.parse`. Tests are at `money_test.dart:65-119`. |
| Design note: overflow at ±(2^53−1), never wrap or clamp | PASS | `money.dart:109-153`. `times` handles a factor of int64 min safely (`factor < -maxMinor` short-circuits). Property 2 is exact against a BigInt oracle, and the factor generator includes the int64 extremes. |
| Design note: largest-remainder allocation (ties go to the lower index, zero weights get zero, sign-symmetric, ≤10,000 parts) | PASS | `allocation.dart:18-70`. Leftover < number of positive weights, so zero weights never receive a unit. The tie-break is in the comparator at `:60-63`. |
| Design note: `roundDiv`, five modes | PASS | `rounding.dart:26-61`. BigInt `~/` truncates and the remainder takes the sign of n. Property 10 checks it against an independent floor-based oracle, with about a third of inputs being exact .5 ties and negative n and d. |
| Design note: `==` and `hashCode` | PASS | `money.dart:218-224` uses code + minor. `Currency` equality uses the code only. `MultiCurrencyTotal` uses `hashAllUnordered`, which is consistent with its `==`. |
| Design note: ISO table pipeline (codegen byte-identical, XML verification, independent oracle, uniqueness, append-only) | PASS with findings 2 and 3 | See `iso4217_table_test.dart`. |
| Design note: featured codes | **FAIL** | Finding 1. |
| Pure-Dart package; only new dependency is dev `glados` | PASS | `lib/money` has no package imports. `dart:io` is used only in `tool/`. `pubspec.yaml` adds `glados: ^1.1.7` under dev_dependencies, and the `pubspec.lock` diff is only the `glados 1.1.7` entry (8 lines). |

## Declared deviations (judged against the design note)
| Deviation | Ruling |
|-----------|--------|
| `Currency.isFund` + JSON `fund` key | **Accept.** D-51 / FR-CUR-07 need it so pickers can list funds codes last. It is parsed from List One `IsFund="true"` and checked against a hard-coded set of 9. The architect should add it to the note's JSON format. |
| `Currency.all` | **Accept.** Historic codes must stay reachable, and `active` is defined in terms of it. |
| `CorruptMoney(code, reason)` | **Accept in principle.** `reason` should become an enum (finding 9). |
| `fromJson` throws `CorruptMoney` | **Accept.** This matches `fromStorage`, and a malformed backup is a data-integrity error. |
| Generated table as records | **Accept.** The list is still const, instances are canonical (built once into `_byCode`), and the test confirms the runtime table equals the JSON row by row. |
| `allocate` always uses BigInt | **Accept.** Exactness is unconditional, and the cost is negligible at ≤10,000 parts. |
| `orderedFor` includes primary only if present | **Accept.** Callers can still get `total[primary]`, which returns zero, and the doc comment states the behaviour. FR-HOME-01 / EC-55 leave the decision about showing an empty primary card to the UI layer. |
| No-double scan uses `\bnum\b` | **Accept.** It is stricter than `num ` because it also catches `num?`, `<num>` and `num.parse`. Finding 6 covers the scan's remaining gaps. |
| (undeclared) numeric uniqueness checked only for active rows | **Accept.** ISO does reuse numerics of withdrawn codes. Record it in the note. |
| (undeclared) public `largestRemainderSplit`, `maxAllocationParts`, `MultiCurrencyTotal.isEmpty` | See finding 10. |

## Findings
| # | Severity | File:line | Issue | Required change | Owner |
|---|----------|-----------|-------|-----------------|-------|
| 1 | **major** | `packages/zaghlol_domain/lib/money/currency.dart:39-49`; `test/money/iso4217_table_test.dart:163-169`; `test/money/money_test.dart:326-333` | `featuredCodes` has the 8 D-22 codes, as the design note says. The SRS is the source of truth and differs: FR-CUR-01, FR-CUR-07 and A-59 make the featured list `EGP, USD, SAR, EUR, AED, QAR, KWD, BHD, GBP, INR`, adding GBP and INR for Monzo/HDFC/Paytm. Pickers (FR-CUR-07) and `orderedFor` (FR-HOME-01) will use this constant, so GBP and INR users get the wrong order. | Append `'GBP', 'INR'` in A-59 order. Update the doc comment from "D-22 order" to "A-59 order". Update the test that asserts the exact list, and update the `orderedFor` expectation (it becomes `AED EGP USD SAR GBP CHF`). The architect should correct the design note. | T-012 (impl); solution-architect (note) |
| 2 | **major** | `packages/zaghlol_domain/tool/gen_currencies.dart:126-135, 209-218`; `test/money/iso4217_table_test.dart:12-22, 69` | **Pipeline robustness when the genuine SIX file arrives.** `main()` always merges the new List One into the committed JSON, append-only. When the reconstructed XML is replaced, any code that exists only in the reconstruction (an invented code, or one already withdrawn) becomes a permanent `historic` row. `_baselineCodes` then forces it to stay. `tryOf` would accept those codes, so a parser could treat a bogus code as valid. Nothing mechanical stops a merge while `published` still reads `UNVERIFIED-RECONSTRUCTION-…`. | (a) Add a `--fresh` mode (or an explicit documented step that deletes `currencies.json`) so the first genuine snapshot is generated with no previous table. Regenerate `_baselineCodes` from that output. (b) Add a test that `published` matches `^\d{4}-\d{2}-\d{2}$` and is ≥ 2025-09-01 (Amendment 180). It fails today on purpose and blocks merge until the real file is committed. (c) In the PR, list the codes that changed versus the reconstruction. | T-012 |
| 3 | minor | `packages/zaghlol_domain/tool/gen_currencies.dart:126-135` | In future refreshes, `mergeAppendOnly` silently overwrites an existing code's `exponent` (or `numeric`) when List One changes it. Stored `*_minor` values for that code would then be read at the wrong scale (×10^k), which breaks CLAUDE.md §2.4. | Throw from `mergeAppendOnly` when an existing code's exponent or numeric changes, unless an explicit override for that code is passed. Add a test. An exponent change needs a data migration task, not just a table refresh. | T-012 |
| 4 | minor | `packages/zaghlol_domain/lib/money/money.dart:165-170` | `allocateEven(parts)` runs `List<int>.filled(parts, 1)` before the 10,000-part limit is checked. A large `parts` value (e.g. `1 << 40`) tries to allocate terabytes and fails with an out-of-memory error instead of `ArgumentError`. | Check `parts > maxAllocationParts` in `allocateEven` before allocating. Add a test with a large `parts` value. | T-012 |
| 5 | minor | `packages/zaghlol_domain/lib/money/multi_currency_total.dart:14-38` | `of(xs)` depends on input order at the range edges. For example, `[max, +1, −1]` throws `MoneyOverflow` while `[max, −1, +1]` returns `max`, because each running total is range-checked. Property 9 claims order independence, but the generator `smallMinor` (`generators.dart:94-108`) never reaches the bound. | Accumulate each currency's total exactly (BigInt, or int64 with a bounded count) and range-check once at the end; do the same for `+`. Add a property test that uses full-range `any.minor`. Alternatively, document that the result depends on order at the bound and narrow the property. | T-012 |
| 6 | minor | `packages/zaghlol_domain/test/money/no_floating_point_test.dart:7` | The scan misses the usual ways a double appears in Dart without the word `double`. These include int `/` int, which returns a double, double literals such as `1.5`, `.round()`, `.toStringAsFixed`, and `pow(`. `minor / 100` would pass. | Strip `//` and `///` comments and string literals, then also forbid `[^~/]/[^/*=]`, `\b\d+\.\d+\b`, `toStringAsFixed`, `\bpow\(`. Add matching cases to the self-test. | T-012 |
| 7 | minor | `packages/zaghlol_domain/test/money/generators.dart:8` | One `ExploreConfig` instance is shared by every property in the file. In glados 1.1.7 the config owns its `Random` (default seed 42). Each test's inputs therefore depend on how many tests ran before it, so a failure may not reproduce under `--name`. Not verified locally; CI does not show it. | Build a fresh config for each test, e.g. `ExploreConfig explore() => ExploreConfig(numRuns: 1000);`, so each test gets its own fixed seed. | T-012 |
| 8 | minor | `packages/zaghlol_domain/test/money/generators.dart:147-179`; `test/money/money_property_test.dart:271-325` | Allocation generators lack edge cases. With random weights in 0..10^6, equal remainders almost never occur, so the lower-index tie-break is checked only by examples. There is no property that equal weights give non-increasing shares by index. There is no weight edge pool (single weight, all equal, a weight of `maxMinor`, int64-scale weights where Σw > 2^63), even though the implementation supports them. | Add a weight edge pool to `_weights`. Add properties: equal weights give shares non-increasing by index; the extra units go to the R largest remainders (checked with a BigInt oracle); Σw > int64 still splits exactly. | T-012 |
| 9 | minor | `packages/zaghlol_domain/lib/money/money_errors.dart:20-28, 45-55` | `CorruptMoney.reason` and `MoneyOverflow.op` are free-form public `String`s that `toString()` prints as-is. The "never an amount" rule (NFR-SEC-03) depends on every future caller writing safe text. | Make `reason` an enum (`unknownCurrency`, `outOfRange`, `missingCurrency`, `nonIntegerMinor`) and `op` an enum. The guarantee then holds by type. | T-012 |
| 10 | nit | `packages/zaghlol_domain/lib/zaghlol_domain.dart:4`; `lib/money/allocation.dart:1-18`; `lib/money/multi_currency_total.dart:76` | Undeclared public API. `largestRemainderSplit(int, List<int>)` and `maxAllocationParts` are exported, which gives a bare-int split with no currency. `MultiCurrencyTotal.isEmpty` was added. | Move `allocation.dart` to `lib/money/src/` and stop exporting it (keep `maxAllocationParts` only if callers need it), or declare these in the design note. | T-012 |
| 11 | nit | `packages/zaghlol_domain/lib/money/money.dart:163-164` | "the larger shares come first" is wrong for negative amounts: −34 comes before −33. | Reword to "lower indices receive the extra unit". | T-012 |
| 12 | nit | `packages/zaghlol_domain/test/money/money_test.dart:167` | `mulDiv` is tested only with denominator 0; a negative denominator is not tested. | Add a case with a negative denominator. | T-012 |
| 13 | nit | `docs/04-tasks/tasks/T-012.md` (design note) | The accepted deviations are not yet recorded in the note. | Amend the note: `isFund` / `fund` key, `Currency.all`, `CorruptMoney` reason, `fromJson` error type, the record table, active-only numeric uniqueness, `orderedFor` semantics, and the featured list fix from finding 1. | solution-architect |

## Checklist
- [x] `flutter analyze` clean (CI run 42315952269)
- [x] Tests added and passing (121 in `zaghlol_domain`; 10 glados properties at 1000 runs each)
- [x] RTL + LTR verified: N/A (no UI)
- [x] No hard-coded strings: N/A for user-facing text; error text is developer-facing only
- [x] No `double` money, explicit currency (subject to the scan gaps in finding 6)
- [x] No sensitive data in logs: `Money`, `MultiCurrencyTotal` and all four errors leave out amounts; `UnknownCurrency` and `CorruptMoney` hide input that does not look like an ISO code; `FormatException` does not echo its input (tested)
- [x] Stays within the task's scope: only `lib/money/**`, the export, `tool/`, tests, the dev dependency and the lock file changed

## Notes for the Lead
- **Two questions about the reconstructed XML.**
  - *Is the generator robust?* The regex parser fits SIX's real structure: the `Pblshd` attribute, repeated `CcyNtry` per country, code-less entries, `N.A.` minor units and `IsFund="true"`. Conflicting repeats fail loudly, as do a changed fund set (the hard-coded set of 9) or a missing exclusion. The weak point is the replacement step itself, finding 2: run it as a fresh build, not a merge, and add the date-format guard so the reconstruction cannot reach `main`.
  - *Are the exponent checks independent?* Yes. The oracle (`iso4217_table_test.dart:73-87`) checks the runtime `Currency` table against hard-coded values: KWD/BHD/OMR/JOD/TND/LYD/IQD = 3; JPY/KRW/VND/CLP/ISK/XOF/XAF/UGX/PYG = 0; EGP/USD/EUR/SAR/AED/QAR/GBP = 2; CLF/UYW = 4. It does not read the XML, so it stands even if the XML is wrong.
- Finding 1 comes from the design note, not the implementer: the note still uses the D-22 list, which A-59 has replaced. The architect should correct the note at the same time.
- Arithmetic I checked by hand and found correct:
  - `times` at the int64 minimum;
  - `mulDiv` products beyond int64 (tested with maxMinor × 1000000007);
  - the bound R < number of positive weights, which guarantees zero weights never get a unit;
  - allocation stays monotonic, because equal quotients with w_i > w_j imply r_i > r_j;
  - `roundDiv` in all five modes, including negative denominators.
- After fixes, this needs re-review by code-reviewer. As C4, the security-privacy-reviewer and test-engineer sections are also still required.