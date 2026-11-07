## Test verification (test-engineer, T-012, branch `task/T-012-money` @ `e36b9d55`)

**Method.** There is no local Dart SDK, so I did a static read of the diff (`origin/main...origin/t012`) and checked the CI log. The log is `app-ci` run 42315952269, job "format, analyze, unit tests" (id 128228536199).
- The job concluded success. Both the `dart format --set-exit-if-changed` step and the `flutter analyze` step ran and passed.
- `dart test` in `zaghlol_domain` ended with "121 tests passed".
- All 10 property tests print "(testing 1000 inputs)".
- I did not re-run anything locally.

### Acceptance criteria and design-note requirements

| # | Criterion | Test (file: name) | CI evidence | Verdict |
|---|-----------|-------------------|-------------|---------|
| AC1 | KWD 1.250, BHD 0.375, JPY 1500 round-trip exactly | `money_test`: "AC: exact round trips KWD 1.250 <-> 1250", "BHD 0.375 <-> 375", "JPY 1500 <-> 1500". Also CLF 1.2345 and EGP -0.05. Each checks parse, `toCanonicalString`, storage and JSON. Backed by property 8 (canonical string, storage, json), 1000 runs each. | All ✅ | PASS |
| AC2 | EGP + USD throws `CurrencyMismatch` | `money_test`: "AC: currency mismatch EGP + USD throws CurrencyMismatch" and "EGP - USD and ordering throw; == is false" (includes a mixed-list `sort`). Property 3 "mismatch throws, == is false" covers random currency pairs. | All ✅ | PASS |
| AC3 | `allocate` never loses or creates a minor unit | Property 4-7 "weights 0..10^6" and "weights up to maxMinor" (sum equals amount, exact in BigInt). "7. allocateEven spread <= 1". Examples: "EGP 1.00 split three ways is 0.34, 0.33, 0.33", "largest remainder wins, ties go to the lower index", "negative amounts and zero weights", "invalid weights throw ArgumentError", "accepts exactly the maximum number of parts". | All ✅ | PASS |
| AC4 | DoD: analyze clean, formatted, no `double`, no amounts in logs | `no_floating_point_test` (2 tests: scans `lib/money/**`, and checks the scanner catches the forbidden forms, so it is not vacuous). `money_test` "no amounts in messages (NFR-SEC-03)" (3 tests). CI format and analyze steps passed. | ✅ | PASS. Hard-coded strings and RTL are not applicable (domain package). |
| P1 | Addition laws | commutative, associative, zero identity, `a+(-a)==0`, `a-b==a+(-b)` | 5 × ✅ (1000 runs) | PASS |
| P2 | Overflow is exact | `+`, `-`, `times` and `mulDiv` "throws iff out of range", compared with a BigInt oracle. Branches exist on both sides because 50% of minors are wide. | 4 × ✅ | PASS |
| P3 | Mismatch | see AC2 | ✅ | PASS |
| P4-P6 | Exact sum, within one unit of quota, sign symmetry, monotonic, zero weights get zero | `checkAllocation`, run for small and for BigInt-range weights. The quota check `abs(s*W - a*w) < W` is done in BigInt. | 2 × ✅ | PASS, but see G1 |
| P7 | `allocateEven` spread ≤ 1 | as above | ✅ | PASS |
| P8 | Round trips | canonical string, storage, json | 3 × ✅ | PASS |
| P9 | `MultiCurrencyTotal` order-independent, per-currency sum, `+` associative | 3 property tests | 3 × ✅ | PASS, but see G4 |
| P10 | `roundDiv` matches a rational oracle for each mode, including .5 ties | "10. roundDiv matches the oracle". One third of inputs are constructed exact ties, with both signs of n and d. Also "roundDiv ties per mode". | ✅ | PASS |
| Ex | Example tests from the design note | KWD `1.2345` rejected, JPY `1.5` rejected, `١٫٢٥٠` rejected, `[0.34, 0.33, 0.33]`, no-double scan | all ✅ | PASS |
| ISO | ISO table (exponent oracle, shape and uniqueness, append-only, codegen sync) | `iso4217_table_test`, 38 tests. The oracle covers KWD/BHD/OMR/JOD/TND/LYD/IQD = 3, JPY/KRW/VND/CLP/ISK/XOF/XAF/UGX/PYG = 0, EGP/USD/EUR/SAR/AED/QAR/GBP = 2, CLF/UYW = 4. | All ✅ | PASS against the stand-in snapshot (known issue: it must be re-verified after the real SIX snapshot lands) |

### Do the properties prove the invariants?

- **Generators.**
  - Currency: 28% each from exponents 0, 2 and 3 (above the 25% requirement), plus 16% from the full table including historic codes.
  - Minor values: about 25% from the edge pool (±maxMinor, ±(maxMinor−1), 0, ±1, …), about 25% small, and about 50% uniform over 0..2^53−1 with a random sign.
  - Weights: lengths 1-50, 20% zeros, a separate big-weight generator up to 2^53−1, and a forced non-zero entry.
  - `times` factors include ±maxMinor, −maxMinor−1 and the int64 extremes.
  - The numeric ranges are adequate.
- **Oracle independence.** The oracles are independent of the implementation.
  - `_oracle` is a floor/modulo formulation. `roundDiv` uses truncate-and-step, so it is a different algorithm.
  - Overflow and allocation checks use plain BigInt arithmetic.
  - It is the same author, but no copy-paste of the logic.
- **Run count.** 1000 runs is enough for the wide-range properties. The boundary cases are the weaker spot, listed below.
- **Vacuity.** I found no vacuous test. The only conditional assertion is associativity, which is skipped when either side overflows. Overflow-heavy inputs are common, but about 50% of cases remain non-skipped. The commutativity and overflow properties are asserted unconditionally.
- **Mutation sensitivity.** I checked by reading that each of these would fail if the behaviour broke: off-by-one in the range check, wrapping instead of throwing, the `times` guard, `halfEven` versus `halfAwayFromZero`, sign handling, and leftover units being lost.

### Gaps

| ID | Gap | Severity |
|----|-----|----------|
| G1 | Hamilton selection is not property-tested. Property 5 (within one unit) and property 6 (monotonic) pass whichever indices receive the leftover units, so a wrong tie-break or a wrong choice of remainders would still pass. Only the examples `[3,3,1]`, `[1,1]`, `[1,1,1]` and `[1,2]` pin it down. Suggest a property that compares against a naive reference (sort by remainder descending, then index ascending). | Non-blocking |
| G2 | Parsing rejection cases are missing: a trailing or leading `\n` or tab (Dart `$` without multiLine should reject these, but nothing asserts it), NBSP, fullwidth digits `１٢`, Persian digits `۱۲`, a mixed ASCII/Arabic-Indic string, a JPY `1.0`, a very long run of leading zeros (more than 16 digits), and `-` plus maxMinor+1. The Arabic-Indic rejection itself is covered (`١٫٢٥٠`, `١٢`). | Non-blocking |
| G3 | `fromJson` with extra keys is untested. The code ignores them, which is a lenient choice that should be pinned. Also missing: `null` or non-String currency, `minor` null/bool/`num`, and an out-of-range minor via JSON. | Non-blocking |
| G4 | Overflow in `MultiCurrencyTotal` is untested. The `moneyList` generator uses `smallMinor` (one 64th of the range) on purpose, so `of`, `add` and `+` are never driven to `MoneyOverflow`. Related behaviour worth a test or a decision: the running-total overflow is order-dependent (`[max, 1, -1]` throws, `[max, -1, 1]` does not). That is acceptable but should be documented for the code-reviewer. | Non-blocking |
| G5 | Empty-total edges are only half covered. `empty.currencies` and `isMultiCurrency` are tested. Not tested: `empty[c]` is zero, `empty + empty`, `empty.nonZero()`, `empty.orderedFor(c)`, `orderedFor` with a primary not present, and `hashCode` consistency for equal totals. | Non-blocking |
| G6 | `Money.hashCode` is checked on a single pair only. There is no property that `a == b` implies equal hashCodes. | Non-blocking |
| G7 | Exponent 4 is nearly absent from the random generators (reached only through the 16% full-table bucket, roughly 0.2% of draws). It is covered by examples (CLF) and by `moneyList`. | Non-blocking |
| G8 | Exact-boundary hits are by chance only. Pairs summing to exactly maxMinor or maxMinor+1, and `times` products landing on exactly maxMinor, are covered by the examples (`top + 1`, `-top - 1`, `top.times(2)`). The properties reach them only rarely. | Non-blocking |
| G9 | Allocation weights above 2^53 (up to int64 max) are untested, although the code claims "any int weights are safe". The single-weight case `[w]` appears in about 2% of runs and has no explicit example. The all-zero case is covered by the example `[0, 0]`. | Non-blocking |
| G10 | The design note says "default fixed seed", but the config is `ExploreConfig(numRuns: 1000)` with no explicit `Random(seed)`. I could not confirm that glados 1.1.7 defaults to a fixed seed. If it is random, CI could flake, and a failing seed would have to be recovered from the output. Suggest passing a fixed seed explicitly. | Non-blocking (needs confirmation) |
| G11 | Re-verification after the real ISO snapshot lands. The table tests currently pass against the stand-in file. The "no baseline code was deleted" and "equal to List One" tests must be re-run against the real snapshot, and `currencies.json` plus the generated file must be regenerated. This is already a known pre-merge item. | Blocking for merge, not for test sufficiency |

None of G1-G10 weakens a stated acceptance criterion. The three criteria and the 10 design-note property requirements each have a test that passed in CI.

### Verdict: **TESTS_SUFFICIENT**

Conditions:
- Add G1 (a Hamilton reference property) and G2/G3 (the extra parsing and `fromJson` cases) before or soon after merge. They are cheap and strengthen the C4 coverage.
- Re-run the ISO table tests on the real SIX snapshot before merge (G11).

---

## Test verification, round 3 (delta 1e44bb9..cb1859c)

**Verdict: TESTS_SUFFICIENT.** The earlier verdict stands, and G11 (real ISO snapshot) is now closed, with one caveat on provenance.

**Evidence.** app-ci run 42407200685 is green on all 13 jobs. In job "format, analyze, unit tests" (id 128507348387) the format and analyze steps pass and the log ends "162 tests passed". That is 121 plus 41 new tests, including 7 from the delta groups. I read the code and the log. I did not re-run anything locally, because there is no Dart SDK.

### Delta items

| Delta item | Test (CI-green) | Does it pin the behaviour? |
|---|---|---|
| Real snapshot, snapshot gate | `iso4217_snapshot_gate_test`: published is a real SIX date on or after 2025-09-01. `iso4217_table_test`: "every List One code with numeric minor units is active" (asserts `table.published == listOne.published`). | Yes. The gate no longer fails on purpose and now blocks a sentinel `2000-01-01` or pre-Amendment-180 date. The published-equality assertion ties the JSON to the XML header. |
| Oracle against real data | 25 "has exponent N" tests (KWD/BHD/OMR/JOD/TND/LYD/IQD = 3; JPY/KRW/VND/CLP/ISK/XOF/XAF/UGX/PYG = 0; EGP/USD/EUR/SAR/AED/QAR/GBP = 2; CLF/UYW = 4). They call `Currency.of(...)`, so they exercise the generated table. The expected values are hard-coded and independent of the XML. | Yes. I re-derived the data independently with a separate Python parse of `list-one.xml`. It gives 165 numeric-unit codes, which is 164 after XAD. The numeric and exponent values for those 164 codes match `currencies.json` exactly. The set also equals the 164 codes in `_baselineCodes`. |
| Funds set | "funds codes are active, flagged and not featured". It asserts `flagged.toSet() == {BOV, CHE, CHW, CLF, COU, MXV, USN, UYI, UYW}`, which is exactly 9. | Yes. This is a strict set equality. Raw List One flags 10 codes IsFund, the 9 plus XAD, so the test would fail if XAD leaked back in. |
| Exclusions (D-67) | "non-currency X-codes are excluded" now includes XAD, checked through `Currency.tryOf`, which is null. "the genuine snapshot lists XAD; the table does not" asserts the raw XML contains `<Ccy>XAD</Ccy>` and that neither the parsed snapshot nor the committed table contains it. "XAD is skipped even though List One flags it IsFund" uses a synthetic entry. "a committed XAD row is dropped, not kept as historic" checks the row count equals `committed.rows.length`. "render refuses a table containing XAD" checks `renderJson` and `renderDart` both throw `FormatException`. | Yes, at four layers (parse, merge, render, runtime). Each would fail if the corresponding guard were removed. |
| `_baselineCodes` (164) | "no baseline code was deleted". | Yes. Its 164 entries have no duplicates and equal the JSON code set. It only catches deletions, not additions. That is acceptable, since the rule is append-only. |
| Byte-identical regeneration | "iso4217_table.g.dart is byte-identical to a fresh render" (`renderDart(table) == committed .g.dart`). "currencies.json == merge(List One snapshot, committed table)" (`renderJson(merged) == committed JSON`). "the runtime table equals currencies.json" (row by row, including `isFund` and status). | Yes. These run the Dart generator inside CI against the committed Python-produced files. They pass, so this is the proof that the Python port matches the Dart renderer. Together with the "every active entry equals List One" and "every List One code is active" tests, the committed data is also tied to the XML. The one weakness is G-R3-1 below. |
| `--fresh` guard | `freshAllowed` is tested for four cases: genuine committed table without `--i-know` is refused, with `--i-know` is allowed, placeholder is allowed, null (no table) is allowed, and a different date such as `2000-01-02` is refused. | Yes for the predicate. The `main()` wiring and exit code 64 are not tested, which is acceptable for tool glue. |
| Interpolation-aware no-double scanner | New must-catch samples: `'${a / b}'`, `'EGP ${minor / 100}'`, and a nested `'${x ? 'a' : '${0.5}'}'`. New must-ignore samples: `'${a ~/ b} is 1.5 / 2 text'`, `'${x ? 'a/b' : '0.5'}'`, `'$name / ${map['k']}'`. The main scan over `lib/money` passes. | Yes. The must-catch cases prove interpolated code is scanned, including nested strings. The must-ignore cases prove string text is not scanned (false-positive control). |

### Gaps (all non-blocking)

| ID | Gap | Severity |
|---|---|---|
| G-R3-1 | No test renders `merge(listOne, null)` and compares it with the committed JSON. The existing JSON-sync test merges against the committed table, so it is idempotent by construction. Today there are no historic rows, so a from-scratch render should be identical. This is a one-line test to add. | Non-blocking |
| G-R3-2 | Provenance of `list-one.xml` cannot be verified by any test, and I could not reach `six-group.com` (the proxy refused). The content is internally consistent. It has Pblshd 2026-09-17, and BGN, CUC and HRK are absent, which fits the euro adoption and CUC retirement. XCG and ZWG are present. A SHA-256 pin of the file is the only mechanical check available, so record it in the PR. Its value for the record is `33139b438657d1cee116ba737807ea71d19d6de4b90f799a09c56f0cc6a1b0ff`, with 45520 chars and no CR bytes. Someone with network access should also diff it against SIX. | Non-blocking, but a human must confirm before merge |
| G-R3-3 | `.gitattributes` `-text` keeps the XML byte-stable. No test asserts that the XML has no CR. Low risk, since CI runs on Linux. | Non-blocking |
| G-R3-4 | The scanner's raw-string detection looks at the previous character (`s[start-1]=='r'`). An identifier ending in `r` directly followed by a quote could be misread as a raw string. This is a latent weakness in the test tool, not a regression, and no such code exists in `lib/money` today. | Non-blocking |
| G-R3-5 | The round-1 gaps G1 to G10 were not re-reviewed. The delta renamed two allocation property tests ("weights 0..10^6 and edges", "weights to maxMinor and edges") and added a `_hamilton` reference. That addresses G1 in principle, but I did not audit the new oracle in this round. | Non-blocking |

Files read: `/home/claude/zaghlol/packages/zaghlol_domain/test/money/` (`iso4217_table_test.dart`, `iso4217_merge_test.dart`, `iso4217_snapshot_gate_test.dart`, `iso4217_test_support.dart`, `no_floating_point_test.dart`) and `/home/claude/zaghlol/packages/zaghlol_domain/tool/gen_currencies.dart`, all at `origin/t012` (cb1859c).

> **Lead note on G-R3-2 (provenance):** the product owner downloaded `list-one.xml` from SIX themselves and placed it in the project folder on 2026-11-07. The file's sha256 is `33139b438657d1cee116ba737807ea71d19d6de4b90f799a09c56f0cc6a1b0ff`, and this hash is recorded in the merge commit.
