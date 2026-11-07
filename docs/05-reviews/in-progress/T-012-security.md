## Security & privacy review (security-privacy-reviewer, Opus)

**Scope:** `git diff origin/main...origin/t012` (`task/T-012-money` @ `e36b9d55`), 18 files. I read CLAUDE.md §2/§6 and the T-012 design note. CI run 42315952269 is green. The placeholder ISO snapshot is out of scope, as instructed.
**Limits:** there is no Dart SDK in the review sandbox, so I did not run any of the conclusions below. They come from reading the code against Dart VM semantics and from the committed tests. pub.dev was blocked by the egress proxy (403), so I could not check the glados archive hash against pub.dev.

### Verdict: **CHANGES_REQUESTED**

Two Medium findings (F1, F2) block approval. Each fix is a few lines. F3–F6 are Low and should be fixed now or tracked in the named task. F7–F10 are informational.

### What passes
- **No amounts in diagnostics.**
  - `Money.toString()` returns `Money(EGP)` (`money.dart:229`).
  - `MultiCurrencyTotal.toString()` lists codes only (`multi_currency_total.dart:104`).
  - `CurrencyMismatch`, `MoneyOverflow`, `UnknownCurrency` and `CorruptMoney` print codes and fixed reasons only. `_safeCode` hides input that does not look like an ISO code (`money_errors.dart:58-64`).
  - `parse` throws `FormatException('not a canonical XXX amount')` with no `source` or `offset` (`money.dart:54`).
  - All `ArgumentError` messages are constants.
  - Tests assert all of this (`money_test.dart:110-117, 267-293, 335-337`).
- **Overflow.**
  - `+` and `−` work on inputs bounded to ±(2^53−1), so the int64 operation cannot wrap, and the result is range-checked.
  - `times` rejects |factor| > maxMinor before calling `abs()`, so the int64 minimum is handled. The division pre-check is exact.
  - `mulDiv` and allocation use `BigInt`, and their cost is bounded (at most about 2^53 × 2^63 per product, at most 10,000 parts).
  - Unary minus is safe because the range is symmetric.
  - I found no way to build an out-of-range `Money`: `Money._` is private, and every public path checks the range.
- **Precision.** Parsing never rounds. Extra fraction digits are rejected, and fewer are padded. After leading zeros are stripped, the 16-digit cap keeps `int.parse` well inside int64 (`money.dart:77-87`). `fromJson` requires `minor is int`, so JSON doubles (`1e3`, `1.0`) and integers too large for int64 are rejected.
- **`try*` APIs.**
  - `tryOf` is a plain map lookup.
  - `tryMinor` is a range check.
  - `tryParse` has no throwing path on any string: the regex limits input to ASCII `[0-9]`, `int.parse` gets at most 16 digits, and `padRight` gets an exponent from the table (0..4, tested at `iso4217_table_test.dart:102-108`).
  - The only remaining failure mode is the resource cost in F3.
- **No `double`.** Nothing under `lib/money/` uses `double`, `num`, `/` or float literals. All division is `~/` or `BigInt`.
- **XXE / entity expansion.** `gen_currencies.dart` uses no XML parser. It extracts values with regexes and never resolves DTDs or entities, so XXE and billion-laughs attacks cannot happen. Codes are validated `^[A-Z]{3}$` and numerics `^[0-9]+$` before they are emitted.
- **Supply chain.** The `pubspec.lock` diff adds only `glados` 1.1.7 (hosted on pub.dev, sha256 `c39446c0…acb33`). It appears in `packages/zaghlol_domain/pubspec.yaml` under `dev_dependencies` only. It is labelled `transitive`, the same as every other member dependency in this workspace root lock (`test`, `lints`, `meta`). There are no runtime dependencies, no new transitive packages, and no analytics or telemetry.

### Findings

**F1 — Medium — `allocateEven` builds an unbounded list before the 10,000-part cap**
- **Owner:** T-012
- **Location:** `packages/zaghlol_domain/lib/money/money.dart:165-170`, with the cap at `allocation.dart:22`
- **Problem:** `allocateEven(parts)` checks only `parts <= 0`, then runs `List<int>.filled(parts, 1)` (line 169). The `maxAllocationParts` check in `largestRemainderSplit` comes too late.
- **Leak/exploit path:**
  - A split or participant count that reaches `allocateEven` from a restored backup, CSV import or a crafted deep link triggers the allocation. Likely callers are T-091 splits and T-051 cycle math.
  - `allocateEven(1 << 31)` tries to allocate about 16 GB. That raises `OutOfMemoryError`, or the OS kills the app, instead of the documented `ArgumentError`.
  - A count in the hundreds of millions causes heavy memory pressure before it fails.
  - This breaks the design-note contract ("a list longer than 10,000 entries → `ArgumentError`") and turns a bad input into a crash.
- **Required change:**
  - Reject `parts > maxAllocationParts` with `ArgumentError` before allocating the list.
  - Add a test for `allocateEven(maxAllocationParts + 1)` and `allocateEven(1 << 40)` expecting `throwsArgumentError`.

**F2 — Medium — the generator copies the unvalidated `Pblshd` attribute into generated Dart source**
- **Owner:** T-012 (fix before the real SIX snapshot is imported)
- **Location:** `packages/zaghlol_domain/tool/gen_currencies.dart:71, 87, 168, 195`
- **Problem:**
  - `_published` captures `[^"]*`, which also matches newlines.
  - `renderJson` escapes the value safely with `jsonEncode`.
  - `renderDart` then writes the value (decoded back from the JSON by `parseJson`) into a `//` line comment: `out.writeln('// ($sourceName, published ${table.published}).');`.
- **Exploit path:**
  - The design expects the next List One file to be downloaded from the internet. A tampered or MITM'd file could use `Pblshd="2026-01-01⏎import 'dart:io';⏎…⏎//"`.
  - The newline ends the comment, so arbitrary top-level Dart lands in `lib/money/src/iso4217_table.g.dart`, which is compiled into the app.
  - Examples: extra imports and declarations, or a block comment that hides the real table so a different one is used, silently changing exponents and scaling every amount by 10^k.
  - The byte-identical regeneration test does not catch this, because it regenerates the same injected output from the committed JSON. Only review of a generated diff would.
- **Required change:**
  - In both `parseListOne` and `parseJson`, accept `published` only if it matches `^\d{4}-\d{2}(-\d{2})?$` (SIX uses `YYYY-MM-DD`), and throw `FormatException` otherwise.
  - Treat every value that goes into Dart source as validated data: codes and integers are already handled, and `published` is the only free-text field.
  - Add a test that a `Pblshd` containing `\n` or `*/` is rejected.

**F3 — Low — `_parse` has no length limit before the regex and string copies**
- **Owner:** T-012 (or T-013 if the Lead prefers the limit at the normalizer)
- **Location:** `packages/zaghlol_domain/lib/money/money.dart:64-84`
- **Problem:**
  - A hostile string, such as a huge SMS or CSV cell or a backup field, is fully matched by the regex and then copied twice: `whole + fraction.padRight(...)` and then `replaceFirst(_leadingZeros, '')`.
  - Leading zeros are unlimited, so a 50 MB `"000…01"` passes the 16-digit check only after both copies are made.
  - The cost is linear (the anchored pattern does not backtrack badly), so this is about 3× memory and CPU per call, not a pathological blow-up. It is still an avoidable amplifier on an API meant for untrusted input.
- **Required change:**
  - Return `null` up front when `text.length` exceeds a small bound, for example 1 (sign) + 16 + 1 + 4 + a generous margin for leading zeros, such as 64.
  - Add a test with a 1 MB all-zeros and an all-digits string, asserting `tryParse == null`.

**F4 — Low — the no-double scanner misses the main ways floating point gets in**
- **Owner:** T-012 (test-engineer)
- **Location:** `packages/zaghlol_domain/test/money/no_floating_point_test.dart:7`
- **Problem:**
  - The forbidden pattern is `\bdouble\b|\bnum\b|toDouble|parseDouble`.
  - It does not catch `int / int`, which returns a `double` without the word ever appearing (for example `final q = a / b; q.round()`).
  - It does not catch float literals (`0.5`, `1e3`) or `var`-inferred doubles.
  - Today's code is clean (I checked by hand), but the guard would not stop a regression in the exact place CLAUDE.md §2.4 cares about.
- **Required change:**
  - Strip comments, then also forbid a lone `/` operator (not `~/`, `//` or `/*`) and numeric literals containing `.` or `e`/`E`.
  - Better: add the `avoid_double_and_int_checks` lint, plus a custom lint or analyzer check that fails on any expression whose static type is `double` under `lib/money/`.
  - Extend the self-test samples with `a / b` and `0.5`.

**F5 — Low — the parser accepts non-canonical forms, so text-based dedup keys can disagree**
- **Owner:** T-046 (ingest dedupe) and T-155 (CSV import duplicate detection). T-012 should only document it.
- **Location:** `packages/zaghlol_domain/lib/money/money.dart:40, 77-88`
- **Problem:**
  - `parse` accepts leading zeros (`007.10`, which a test at `money_test.dart:95` intends), short fractions (`1.5` and `1.50`), and `-0` / `-0.00`.
  - All of these map to one `(minor, currency)`, and `toCanonicalString` is a normalizing function, not an identity. That is correct for amounts.
  - It is a risk if a downstream dedup or fingerprint key hashes the raw amount text (from SMS, OCR or a CSV cell) instead of the parsed value.
  - Example: an attacker-controlled or OCR-noisy CSV row `"01.50"` would not be treated as a duplicate of `"1.50"`, so a duplicate transaction gets imported. The reverse also happens: a sign lost in `-0` is invisible.
- **Required change:**
  - In T-012, rename the doc wording from "canonical" to "accepted" for the parser input, or add a sentence saying that `parse` normalizes and that `toCanonicalString(parse(s)) == s` does not hold in general.
  - T-046 and T-155 must build dedup keys from `toStorage()` (`minor` plus code), never from source text.
  - If byte-exact canonical input matters anywhere, offer a `parseStrict` that rejects leading zeros (other than a single `0`), short fractions and `-0`.

**F6 — Low — untrusted JSON has no non-throwing entry point**
- **Owner:** T-149 (backup restore) and T-155 (CSV import). Alternatively T-012 adds the API.
- **Location:** `packages/zaghlol_domain/lib/money/money.dart:190-216`
- **Problem:**
  - Backup and CSV data reach `fromJson` and `fromStorage`, which signal bad data only by throwing `CorruptMoney extends Error`.
  - Dart convention and `avoid_catching_errors` discourage catching `Error`. Restore code will either catch it broadly, which also swallows real bugs, or let one corrupt row crash the whole restore.
  - This goes against the design note's own rule that untrusted input enters through `try*` APIs.
- **Required change:** add `static Money? tryFromJson(Map<String, Object?>)` and `tryFromStorage(int, String)` that return `null`, with tests for wrong types, unknown or lowercase codes, out-of-range values and missing keys. Otherwise, record in T-149/T-155 that they must catch `CorruptMoney` specifically, per row.

**F7 — Info — `toStorage()` and `toJson()` print amounts through their default `toString`**
- **Owner:** T-021 (redacting diagnostic log)
- **Location:** `packages/zaghlol_domain/lib/money/money.dart:184-186, 202`
- **Problem:**
  - The record returned by `toStorage()` prints as `(currency: EGP, minor: 1250)`.
  - The map returned by `toJson()` prints `{minor: 1250, currency: EGP}`.
  - This is unavoidable for serialization types. However, `'$row'`, `debugPrint(m.toJson())` or an exception message that embeds a storage row would leak an amount that `Money.toString` was designed to hide.
- **Required change:** add a dartdoc warning ("contains the amount; never log") to both methods. T-021's redactor and lint rules should treat `*_minor` fields and these shapes as sensitive.

**F8 — Info — `UnknownCurrency.code` and `CorruptMoney.code` keep the raw untrusted text as a public field**
- **Owner:** T-021
- **Location:** `packages/zaghlol_domain/lib/money/money_errors.dart:37, 49`
- **Problem:** `toString` is safe, but any future diagnostic that serializes error fields, rather than calling `toString`, would echo arbitrary text. That text could be SMS content passed by mistake.
- **Required change:** none now. T-021 must log errors through `toString()` only.

**F9 — Info — the generator's regex parsing also matches inside XML comments, CDATA and the DTD**
- **Owner:** T-012 (when the real SIX file lands)
- **Location:** `packages/zaghlol_domain/tool/gen_currencies.dart:72-76`
- **Problem:**
  - A commented-out `<CcyNtry>` would be parsed as a live entry.
  - A missing `</CcyNtry>` makes the lazy `(.*?)` rescan to the end of the file for each opening tag. That is quadratic, but only in a dev-time tool.
  - Exponents are not range-checked at generation time. The committed-table test at `iso4217_table_test.dart:102-108` does catch values outside 0..4, so CI fails safely.
- **Required change (optional):** strip `<!--…-->`, `<![CDATA[…]]>` and `<!DOCTYPE…>` before matching, and range-check `exponent` (0..4) and `numeric` (1..999) in `parseListOne`.

**F10 — Info — the glados hash was not checked against pub.dev**
- **Owner:** Lead
- **Location:** `pubspec.lock:150-157`
- **Problem:** pub.dev was unreachable from the review sandbox, so I did not compare sha256 `c39446c0c4fe83a6ee6ee4fdee5a1afa27050619c7df390bf4c3b77b6f1acb33` with the published `archive_sha256` for glados 1.1.7. The CI `pub get`, which checks hashes, passed.
- **Required change:** none, unless the Lead wants an independent hash check. glados is dev-only, test-time code and is not shipped in the app.

### Required to move to APPROVED
1. Fix **F1**: add the `parts` cap before `List.filled`, plus a test.
2. Fix **F2**: validate `Pblshd` in `parseListOne` and `parseJson`, plus a test.
3. Fix **F3** and **F4** in this task, or file them explicitly on the task board. **F5** and **F6** are to be recorded as acceptance notes on T-046, T-149 and T-155.

### Files reviewed
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/money.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/allocation.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/money_errors.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/rounding.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/currency.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/lib/money/multi_currency_total.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/tool/gen_currencies.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/test/money/no_floating_point_test.dart`
- `/home/claude/zaghlol/packages/zaghlol_domain/test/money/money_test.dart`
- `/home/claude/zaghlol/pubspec.lock`

All files are as of `origin/t012`.