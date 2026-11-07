## Test section for docs/05-reviews/T-026.md

**Scope:** `docs/02-design/copy-deck.md` at `f43b6e1`. `git fetch origin` was run, and the local and remote branch tips are identical. I read the file from git objects and wrote no repo files. The throwaway scripts are in `/tmp/claude-0/-home-claude/8b5b5bb4-5f12-52fd-8ad3-771dc5c20afe/scratchpad/` (`t.py`, `t2.py`, `t3.py`, `t4.py`), run with `python3 -I`. `flutter analyze` and the Dart test suite don't apply, because this task changes only a docs file.

### Results by check

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Every row parses (key, AR, EN, notes) | PASS | `t.py` found 676 key rows. Each has exactly 4 cells, a backtick-wrapped key, and no empty AR, EN or notes cell. 0 malformed. The count per section matches the §1.K table for all 22 sections (sum 676). |
| 2 | Keys unique and match the §0.1 naming convention | PASS | 0 duplicate keys. All 676 match `^[a-z]\w*_[a-z]\w*_[a-z]\w*$`, which is three camelCase segments. Features seen are `common`, `accounts`, `transactions`, `onboarding`, `capture`, `home`, `ingestion`, `transfers`, `backup`, `mascot` and `security`. No backtick-quoted key reference in a note, AR or EN cell points to a missing key. |
| 3 | Same placeholder set in AR and EN | PASS | A real ICU parser (`t.py`) compared the placeholder names and types (plain, plural, select) per key. 0 mismatches. Select branch names are identical in AR and EN. `{count}` is never printed as a plain value. Every plural prints `{n}`. |
| 4 | Plural and select syntax | PASS with 1 defect | The parser found 35 plural keys and 8 select keys, which matches the deck's claim. There were 0 brace imbalances and 0 parse errors. Every AR plural has `=1`, `=2`, `few`, `many` and `other`, and every EN plural has `=1` (or `one`) and `other`. Every select has `other`. One exception, D-1 below: line 378 has only `=1` and `other` in AR. |
| 5 | No digits in AR strings except placeholders | PASS | After stripping placeholders and `=N{` selectors, 0 AR strings contain ASCII or Arabic-Indic digits. No arrows `←` or `→` appear in AR. |
| 6 | No emoji in error, permission, money or destructive keys | PASS | 31 rows contain emoji or symbols. Most are `✓`, which §0.8 counts as a symbol. A key-name filter for error, denied, permission, offline, delete, discard, stop, merge, lock, passphrase, undo, amount, safe, budget and similar words found none of them among the emoji rows. No single string branch holds more than one emoji. Emoji sit only in greetings, mascot lines, success and empty states, and review banners. Borderline: `home_mascot_payday` (line 510, 🎉 with `{amount}`) and `home_mascot_proudSavedMore` (line 508, 👏). Both are mascot praise lines, which §0.8 allows, but the Lead should accept them knowingly. |
| 7 | Required screens have sections with keys | PASS | S-01 has 10 keys, S-02 29, S-03 41, S-04 29, S-05 7, S-06 14, S-10 57, S-11 28, S-12 41, S-13 20, S-14 45, S-15 26, S-16 16, S-40 47, S-41 21, S-42 7, S-43 33, S-61 45 and S-62 14. S-10, S-11 and S-41 are also tagged on the shared sections (the transaction row, C-05), so the S-10 total in the script's heading-based count is higher. |
| 8 | Mechanical conversion to ARB (T-029) | PASS with caveats | Each row maps 1:1 to an ARB key. The AR and EN cells are already ICU text. Placeholder types are `count` as int and everything else as String, per §0.3. Caveats are listed below. |

### Defects and findings

- **D-1 (medium), line 378, `onboarding_iosSetup_checkCount`:** the AR plural has only `=1` and `other`. This breaks the §0.4 rule that Arabic must supply all six forms. The two branches are identical, so the text is correct, but a T-029 six-form parity test will fail on it. Either add the four missing forms or exempt this key in the test.
- **D-2 (low, convention conflict), lines 168, 233, 241, 242, 260, 262, 378, 454, 459, 527, 532, 538, 594, 595, 597, 644, 711, 747, 764, 765, 766, 767, 793, 864, 970 and 972:** 26 of 35 AR plurals have no `=0` branch. §0.4 says "all six forms: =0, =1, =2, few, many, other". Also, the CLDR Arabic categories are zero/one/two/few/many/other, not `=0`. With no `=0` or `zero` branch, a count of 0 falls to `other` and renders as "0 حركة". Please settle the rule: require `=0`, or define "six forms" as one/two/few/many/other plus `=1`/`=2`, and write the T-029 parity test to match.
- **D-3 (low), lines 765, 766, 767, 943, 944 and 972:** the notes don't say `count:int` for these plural keys, which every other plural does. T-029 needs the type to declare the placeholder in the template ARB.
- **D-4 (low, documentation), about 100 keys:** the notes don't list some placeholders. Examples are lines 171, 173, 178, 234 and 235, and most `amount`, `merchant`, `card` and `date` keys from line 492 onward. The ICU text is complete and §0.3 makes every non-count placeholder a String, so conversion isn't blocked. The ARB `@key.placeholders` metadata can only be generated from the ICU text, not from the notes.
- **D-5 (low, line 678, `ingestion_review_title`):** AR has 👀 and EN has none. Every other emoji key has matching emoji in both languages.
- **D-6 (low, advisory), length classes (§0.7):** `t4.py` counted a string as over the limit when its longest ICU branch, with placeholders removed, exceeded the limit for its stated class. That gave 28 keys over a limit in AR or EN, for example:
  - line 311 (L, EN 35/30)
  - line 312 (L, EN 38/30)
  - line 315 (B, AR 24/20)
  - line 367 (B, AR 23/20)
  - line 371 (L, AR 37/28)
  - line 392 (C, AR 24/16)
  - line 394 (C, EN 19/16)
  - line 395 (L, AR 36/28)
  - line 420 (S, EN 155/130)
  - line 441 (B, EN 23/22)
  - line 523 (L, EN 35/30)
  - line 564 (C, 18/16)
  - line 699 (B, EN 27/22)
  - line 800 (T, EN 54/44)
  - line 838 (C, 18/16)
  - line 878 (C, EN 22/16)
  - line 888 (L, EN 39/30)
  - line 917 (C, AR 18/16)
  - line 964 (C, 24/16)

  A few notes list "T · M" and the script took the larger limit; line 359 passes on that basis. The 6 notes that begin "N + …" (635, 645, 689, 708, 770, 939, 975) parsed as having no class, which is a script artefact, not a defect. Length is a layout risk to check at 130% scale, not a blocker.

### T-029 conversion caveats

- Apostrophes appear in 78 EN rows. Line 734 (`{name}'s share`) puts an apostrophe right after a closing brace. Flutter gen-l10n treats `'` specially next to braces. T-029 should run `flutter gen-l10n` early on this key, and escape it as `''` if needed.
- Placeholder names `part`, `type`, `method` and `platform` are fine as Dart identifiers. No reserved words are used as placeholder names.
- One row (line 307, `onboarding_welcome_languageToggle`) has Arabic in the EN column. That is intentional.
- 62 AR rows contain Latin brand names or acronyms, which §0.6 allows.
- §1.Q lists Q-15 (the `count` int plus `n` String plural scheme) and Q-16 (bidi isolates added in the presentation layer). Both need the architect's confirmation before T-029. They are open design decisions, not test failures.
- The file ends with the Part 2 and Part 3 marker comments, so appends are safe.

### Not covered

- Native Egyptian-speaker review of the Arabic text. That is T-058.
- The §0.8 tone-gate rules on humour and on the "no server" claim are only partly checked. Only the emoji rule was automated.
- `flutter gen-l10n` was not run, because T-029 doesn't exist yet. Parse validity was checked with my own ICU parser, not Flutter's.

### Verdict: **TESTS_SUFFICIENT**

The deck's mechanical properties all hold: 676 unique rows, matching placeholders, balanced ICU, no digits in AR, no emoji where the tone gates forbid them, and all required screens present. D-1 and D-2 should be fixed or resolved before T-029's parity test is written, but they are deck wording and convention issues, not test gaps. No repo files were written, so no test files were added. The scripts can be rerun from the scratchpad path above if you want to keep them as T-029 test seeds.