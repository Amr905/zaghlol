# Batch 90 review: T-322 (C3), T-323 (C4), T-324 (C1), T-326 (C4), T-328 (C4)

Batch `batch/2026-11-26-90` at `41ca9f6a`, compared with `main` at `ed5a73e0`. Commit messages and branch names use the old ids T-272…T-278. One reviewer covered code, security and privacy (Opus), because the batch holds C4 tasks.

Verdict: **CHANGES_REQUESTED**.
- T-328 has 2 majors (M1, M2). Both are privacy issues: a user reference reaches `sentText`.
- T-322, T-323 and T-326 are APPROVED, with minors.
- T-324 (C1) passed a skim. The Lead spot-checks it.

## Checks run

| Check | Result |
|-------|--------|
| `packages/zaghlol_domain`: `dart analyze`, `dart test` | No issues; 546 pass |
| `packages/zaghlol_parsing`: `dart analyze`, `dart test` | No issues; 1818 pass, 2 fail. Both failures are the same timing test, `generic_parser_test.dart` "safety benchmark" (305/191 µs against a 140 µs budget). It also fails when run alone, and the batch doesn't touch the generic parser, so it's the container's speed, not this batch. All 82 `test/chat/llm` tests pass. |
| `backend`: `dotnet build -warnaserror`, `dotnet format --verify-no-changes` | 0 errors; clean |
| `Zaghlol.Contract.Tests` | 111 pass, 94 fail. All 94 failures are `DockerUnavailableException` (Testcontainers). The LLM subset (`~Llm`/`~AskPlan`, 24 tests) passes. |
| `Zaghlol.Infrastructure.Tests` (T-323) | Not run: needs Docker. The batch GitHub run (db-platform/backend-ci) is the gate. |
| `app`: `flutter test test/core/backend/api_models_test.dart test/core/l10n` | 30 + 37 pass |
| Adversarial masker probe (about 150 cases, throwaway, not committed) | Results below |

---

## T-328: client scrub and reference masker (C4, privacy-critical)

Verdict: **CHANGES_REQUESTED** (M1, M2)

**What holds up.**
- **Folding.** Tatweel, harakat, zero-width and bidi marks (ZWSP/ZWNJ/ZWJ, RLE/PDF, soft hyphen), Arabic-Indic and Persian digits, alef/hamza variants, ى/ي and ة/ه all fold, and spans map back to the original text exactly.
- **Clitic prefixes.** و/ف + ب/ل/ك + ال and لل work (`وبكارفور`, `فبالكارفور`, `وللكارفور`).
- **Last-4 spellings.** `x4321`, `****4321`, `••••4321`, `4321/12` and `...4321` are masked.
- **Forged tokens.** The scrub strips every typed ⟦ or ⟧ before anything else runs, so a forged `⟦CARD_1⟧` or `⟦PHONE⟧` reaches the output as plain text.
- **Ordinary-word aliases** are masked only next to a bank/account/card word, as AC4 requires.
- **Unresolvable cases** (`bank X` with unknown X, a bank where the user has no account, a missing card, an ambiguous last-4) return `MaskUnresolved`.
- **Fails closed.** Any error returns `MaskUnresolved(failed)`.
- **No names in output.** Every `toString` is redacted, and candidates hold only `MaskAccount` objects, whose `toString` is also redacted.
- **Over-masking.** A nickname that is a common word («البيت») is masked everywhere. That is the safe direction.

The AC→test map is complete. Both negative proofs exist, and the builder showed each one failing with its guard broken.

### Findings

**M1 (major, privacy): some letter variants are not folded, so user merchant, bank and nickname names reach `sentText`.**
`packages/zaghlol_parsing/lib/chat/llm/loose_text.dart:10` (`looseFold`, through `foldKeyIndexed` / `_foldLetter` in `normalize/text_normalizer.dart`).

Probe results (Ahmed fixture, plus a merchant «كوستا»):

| Input | Sent |
|-------|------|
| `کارفور` (Persian kaf U+06A9) | `کارفور` |
| `سبینس` (Persian yeh U+06CC) | `سبینس` |
| `کوستا` | `کوستا` |
| `حسابي في الأهلي`, typed with alef + combining hamza U+0654 | unchanged, so the NBE alias goes out |
| `Ｃarrefour`, `Ｃｉｂ` (fullwidth Latin) | unchanged |

Persian/Urdu layouts and pasted text produce ک/ی. Some input methods and copy sources produce decomposed hamza. The builder listed ک/ی as a known gap, but under D-92 it is a leak, not a gap.

Required change:
- In `looseFold` (masker and scrub only, so the parser's `foldKey` stays as it is), fold the following, for both the text and the keys:
  - U+06A9 → ك and U+06CC → ي (also U+06C1/U+06D5 → ه).
  - Alef/waw/yeh + U+0653/U+0654/U+0655 → the base letter. Drop the combining mark and keep the origin index.
  - Fullwidth ASCII U+FF01–FF5E → ASCII.
- Add these variants to the property group in `reference_masker_test.dart`.

**M2 (major, privacy): a real last-4 next to a common card word, or written in two groups, reaches `sentText`.**
`packages/zaghlol_parsing/lib/chat/llm/reference_masker.dart:31` (`_cardWords`) and `:386` (the `_fourDigits` loop).

Probe results (4321 is Ahmed's card):

| Input | Sent |
|-------|------|
| `كريديت 4321` | unchanged |
| `credit 4321` | unchanged |
| `كارت 43 21` | unchanged |
| `كارت 43-21` | unchanged |
| `كارت ٤٣ ٢١` | unchanged |
| `كارت 4 3 2 1` | unchanged |

«الكريديت» is the everyday Egyptian word for a credit card. FR-LLM-18 (3) gives its card-word list as examples ("e.g."), and the builder already went beyond it (ميزة, ماستر, debit…).

Required change:
- Add `كريديت`, `كردت`, `ديبت`, `بريبيد`, `ائتمان`, `ائتماني`, `credit`, `prepaid` and `ending in` forms to the card words, in folded form.
- Within the ±3-token card window, join adjacent digit groups separated by a single space, `-` or `.` when together they make exactly 4 digits, and resolve the result as a last-4 candidate. The amount exception (currency word after it) still applies.
- Add tests: `كريديت 4321`, `كارت 43 21` and `كارت ٤٣-٢١` must each be masked or unresolved.

**Minors (follow-ups, not blocking).**

- **m1. Last-4 more than 3 words from the card word.** `reference_masker.dart:395`. «الكارت بتاعي اللي رقمه في الآخر 4321» sends 4321. This matches the SRS rule (3 words), and «صرفت 4321 جنيه» must keep 4321, so the window can't simply grow. Raise an OQ: widen the window for a token that exactly equals one of the user's last-4s?
- **m2. "bank of X" and "X bank" skip the FR-LLM-20 unknown-bank check.** `reference_masker.dart:463`. `of`, `al`/`el` and similar words are on the stop list, so `bank of zz` and `zz bank` are sent. Arabic `بنك X` works. Fix: skip one connector word before testing X, and also test the token before `bank`.
- **m3. Some phone and InstaPay forms survive the scrub.** `client_scrub.dart:17`. `0100.000.0000`, `010 00 00 00 00`, `ahmed＠instapay` (fullwidth @) and `ahmed @ instapay` all go out. These forms are rare. Fix: accept `.` and 2-digit groups when the total is at least 10 digits and the run starts with `01`/`+20`; fold U+FF20 and ignore spaces around `@` before `instapay`.
- **m4. Possessive suffixes on names.** `كارفوري`, `Talabatey` and `بنكالأهلي` (missing space) are not masked. Low risk; decide with m1.
- **m5. Placeholder numbers above 9.** The schema accepts only `_[1-9]` (`ask-plan-v1.schema.json:225`), but the masker numbers without limit. The 10th distinct merchant can't be referenced. Cap at 9 per kind, or return `MaskUnresolved`.
- **m6. No input cap, and the cost grows with the square of the input.** 340 KB took 10 s. The UI caps questions at 300 characters (FR-LLM-17), so this is defensive only. Add `if (text.length > 4 * maxAskChars) → MaskUnresolved(failed)`.
- **m7. Registry short forms.** `فودافون`, `Vodafone` and `voda cash` alone are not masked, because only «فودافون كاش» is an alias. T-343's registry adapter must supply short forms; add a test there.
- **nit. Scrub failure path.** On error the scrub returns the text `⟦NUMBER⟧`, which the pipeline would then send as a question. Signal the failure instead, so nothing is sent and no quota is used.

On the builder's other listed gaps:
- **Digits written as words:** acceptable (m1-class, OQ).
- **A 4-digit amount near a card word without a currency word is treated as a last-4:** the safe direction, accepted.
- **The `bank X` stop list:** the safe direction, apart from m2.

---

## T-322: LLM contracts (C3)

Verdict: **APPROVED**

**Checked.**
- **The schema is a closed set.**
  - Every object has `additionalProperties:false` and all fields required.
  - `plan` is an enum of 17 values, and `p` is an `anyOf` of one closed `$defs/P_<plan>` per plan.
  - Step 5's `PLAN_MISMATCH` closes the gap the `anyOf` leaves between `plan` and `p`, as the builder decided; the vectors cover it.
- **Placeholders and mentions.**
  - `ref` matches `^⟦(ACCOUNT|CARD|BANK|MERCHANT)_[1-9]⟧$`.
  - `mention` has no digits in any script and is 1–40 characters.
  - Amount strings are ASCII decimals (at most 9.3 digits).
- **Templates.** The step 6 reference rejects digits in any script (Unicode Nd), `@` (including fullwidth and small), links (`://`, `www.`, label.tld), markup characters, controls, more than one emoji, ⟦⟧, unknown or duplicated blanks, the wrong script for the language, and non-NFC text. Keeping `t` out of the schema, so that a bad template drops only `t`, is sound.
- **Versioning.** `v` is pinned to 1, and `planVersion: 1` is in the request; a breaking change becomes `ask-plan/2`.
- **Builder decisions.**
  - The 4 KB body cap, or 16 KB with `attestationObject`, is sound: `q` stays 1–300 by schema, so the larger cap only lets the attestation blob through.
  - `zaghlol-cat-attest-v1` follows the ask pattern.
  - Validating `p` per plan is right.
- **The NFC note is correct.** I checked it: with `InvariantGlobalization=true`, `"é".IsNormalized(FormC)` returns `true`, so T-330 needs its own NFC table or must keep the combining-mark check.
- **Fixtures** use synthetic tokens and data, and a test checks that.
- **Codegen.** The change (`_Raw`, `unknown` → `unknownValue` on the wire value `unknown`) is fine.

**Minors.**
- **m8. The categorise attest prefix is recorded only in `backend-api.md` §4.9.** `zaghlol-cat-attest-v1` is not in `llm-categorise.md` §3 or `ask-llm.md` §5. Add one line in either place, so T-336/T-340 don't miss it.
- **m9. T-330 must not use `string.IsNormalized`.** It is a no-op under invariant globalization. The AskPlanReference comment notes this; make it an explicit AC of T-330.

---

## T-323: backend migration, six LLM tables (C4: data migration)

Verdict: **APPROVED**

**Checked.**
- **Columns match the spec.** The columns match `ask-llm.md` §4.5 and `llm-categorise.md` §4 exactly. No column can hold question text.
- **Identifiers.** `subject_id` on `llm_quota_counters` is the only install or account id. The two review tables carry only `install_hash`, as the spec requires. `updated_by` and `operator_id` are operator ids.
- **No floating types.** `cost_usd` is `numeric(14,6)`.
- **merchant_norm backstop.** All three tables use the same `merchant_norm` CHECK as `merchant_contributions` (FU-018), plus length 2..64.
- **Expand-only.** The migration only creates new tables, with plain SQL (the T-135 pattern), named constraints and no change to the model snapshot.
- **Safe on every host.** The regex uses only syntax `merchant_contributions` already ships with on Aiven, MonsterASP and the self-hosted kit. `Down` drops only the new tables.
- **Least privilege.**
  - `app_rw` only reads `remote_config` and has only INSERT/SELECT on the review tables.
  - `ops_rw` may update only the review columns.
  - `ops_ro` has nothing.
  - `worker_rw` has DELETE for the retention purger. That goes beyond §4.5's "DELETE on counters" but matches the retention rules for spend (13 months), cache, confirmations and corrections.

**Minors.**
- **m10. Two deletions the spec needs have no grant.** `GrantMatrix.cs:292`, `:294`. `app_rw` has no DELETE on:
  - `llm_quota_counters`, which `DELETE /v1/installs/me` and `/v1/accounts/me` must use to delete the subject's rows (`ask-llm.md` §4.2, privacy erasure). Those endpoints run as `app_rw`.
  - `llm_cat_answer_cache`, which FR-LCAT-12 intake uses to delete a cached row after 3 corrections.

  The matrix is frozen once it ships, so fixing this later costs a migration. Recommended: change both to `SIUD` in this fix round (two tokens plus the grant test rows). Otherwise give T-334/T-339 an FU.

---

## T-326: what-if and saving-suggestion calculators (C4: financial math)

Verdict: **APPROVED**

**Checked.**
- **Integer money.** All money is integer minor units through `Money`. Threshold tests use BigInt cross-multiplication with no division (S1 `last*300 >= sum*(100+pct)`, S4 `u*100 >= w*share`). Each figure is rounded half-even once.
- **Per currency.** Results are per currency; mixed currencies throw `CurrencyMismatch`, and an amount-mode cut applies only to its own currency.
- **Basis.** The base B uses at most the last 3 full periods: one period gives a figure from that period, zero periods gives `NotEnoughData`.
- **SRS examples.** 3,200 × 50 % × 12 = 19,200.00, and min(500, 3,200) × 6 = 3,000.00 both match.
- **Essential categories.** The essential list (Q-25) also checks `parentId`.
- **Ranking.** Top 3, ties by name, then kind.

**Minors.**
- **m11. Does S1's 3-period average include the last period?** `savings_suggest.dart:162`. The builder includes it, so the SRS PL-SUGGEST fixture (delivery 2,300 against an average of 1,800) holds only if delivery is not strictly rising; otherwise S3 (latest − earliest) wins. The builder flagged this. Raise an OQ so the SRS says whether the average is "previous 3" or "last 3 including".
- **m12. Negative base.** `what_if.dart:93`. A net-negative base (refunds above spend) gives a negative saving in percent mode, and `capped = true` with a negative figure in amount mode. Return `NotEnoughData`, or a zero result, when `base <= 0`.
- **nit.** S1/S3 de-duplication is keyed by category name. Two categories with the same name (custom and system) would collapse; key by `id`.

---

## T-324: ARB strings (C1)

Skim only. 105 keys, `arb_parity_test` and the l10n tests are green. Lead spot-check.

---

## Security and privacy summary

| Area | Result |
|------|--------|
| Data leaving the phone (D-92, FR-LLM-03/18) | **M1, M2** must be fixed before merge. m2, m3 and m4 are Low. |
| Map and names never logged (FR-LLM-19) | Holds: redacted `toString` everywhere, no logging, fail closed |
| Forged placeholders and prompt injection through templates | Holds (strip before scrub; step 6 grammar) |
| Backend tables: no question text, no install id in the review tables, least privilege | Holds; m10 is a missing grant, not an excess one |
| Attestation binding vectors (JCS, prefixes, installId) | Reproduced byte-exactly by an independent test |

## Proposed follow-ups

Next free number from `LEAD_HANDOFF.md`: FU-364.

| FU | Item | Owner |
|----|------|-------|
| FU-364 | m1 + m4: last-4 beyond 3 words; possessive suffixes (OQ to the PO) | T-328 lane / requirements |
| FU-365 | m2: `bank of X` / `X bank` unknown-bank check | T-343 |
| FU-366 | m3: phone with dots or 2-digit groups; fullwidth or spaced `@instapay` | T-343 |
| FU-367 | m5: placeholder index above 9; m6: input cap; nit: scrub failure signal | T-343 |
| FU-368 | m7: registry short aliases (فودافون, Vodafone) for the masker adapter | T-343 |
| FU-369 | m8: categorise attest prefix in the spec docs; m9: NFC as an AC of T-330 | T-330 / T-336 |
| FU-370 | m10: `app_rw` DELETE on `llm_quota_counters` and `llm_cat_answer_cache` (or fix now) | T-334 / T-339 |
| FU-371 | m11: OQ on the S1 average basis; m12: negative base; nit: dedupe by id | T-342 |

---

## Fix round — T-328

Branch `task/b90-fix-masker`. Parsing package only, plus one backend schema pattern.

- **M1 fixed.** `looseFold` (loose_text.dart) is now its own pass, not `foldKeyIndexed` plus extras. It folds Persian/Urdu letters (ک ی ە ھ ہ ۃ گ پ چ ڤ ...), alef/waw/yeh with hamza or madda (precomposed or combining U+0653-0655; ؤ ئ read as و ي on both sides), Arabic presentation forms (FB50-FDFF, FE70-FEFE, lam-alef as two letters), fullwidth ASCII, Latin accents (U+00C0-017F, NFD marks, ligatures), Eastern Arabic and Persian digits, and drops zero-width, bidi, variation selectors, tatweel and marks. The parser's `foldKey` is unchanged (test). A second mapping, `scrubFold`, keeps dots and hyphens for the scrub regexes.
- **M2 fixed.** Card words extended (كريديت، الكريديت، كردت، ديبت، بريبيد، ائتمان، ميزة، ماستر، credit, debit, prepaid, meeza, ending, آخره ...). A last-4 can now be 1 to 4 adjacent digit groups that make exactly 4 digits (`43 21`, `43-21`, `43.21`, `4 3 2 1`, any digit script) within 3 words of a card word; the amount exception is unchanged.
- **Minors done:** `bank of X`, `bank al X` and `X bank` go through the unknown-bank check (an English prefix stop list keeps `my bank`, `which bank`); phones with dots, 2-digit groups and `+20`; `ahmed @ instapay` and fullwidth `@`; placeholder numbers above 9 render and map (schema pattern widened to `_[1-9][0-9]?` in `backend/contracts/ask-plan-v1.schema.json`; the .NET contract tests were not run here).
- **Safety net:** after masking, `sentText` is folded again and checked for any account label/nickname/extra name, non-ordinary bank alias, merchant name, or a known last-4 next to a card word; a hit returns `MaskUnresolved(failed)`. Proven through the seam `ReferenceMasker.leaksForTest` (no shipped rule leaves a leak for the net to catch in an end-to-end case).
- **Tests:** new `reference_masker_variants_test.dart` (variant probes, 20 card words x 14 spellings x 4 frames, property tests with Persian, decomposed hamza, fullwidth, zero-width, accent and split-digit generators, minors, safety net, known gaps). With the lib changes stashed the new tests fail (13 failing groups).
- **Still not caught** (T-328 task file, known gaps): digits as words, last-4 beyond 3 words (FU-364), possessive suffixes, comma-split digits, look-alike letters from other scripts, scrub failure path text. m6 (input cap) and m7 (registry short forms) not done.

---

## Delta re-review — T-328

Scope: `git diff a1a4e4e6..6afbfac7 -- packages/zaghlol_parsing backend/contracts` (one commit). Reviewer: `code-reviewer` (Opus), delta only.

Verdict: **CHANGES_REQUESTED** (M3). M1 and M2 as written are fixed; one new last-4 leak class remains.

**Checks run.** `dart test test/chat/llm`: 104 passed. About 130 throwaway adversarial probes through `ClientScrub` + `ReferenceMasker` (not committed). Performance: a 300-character question with 100 accounts (label, nickname, extra name, last-4) and 100 merchants (two names each) takes about 4.7 ms on average for scrub + mask, about 2.3 ms for a single run. That is well under 50 ms.

**M1 / M2 confirmed fixed.** These are now masked: Persian ک/ی/ڪ/ۆ, alef + combining U+0654, presentation forms (`ﻛﺎﺭﻓﻮﺭ`), fullwidth (`Ｃarrefour ｃｉｂ`), Latin accents, tatweel inside names, ى/ي and ة/ه swaps (`القاهره`, `حلوانى مصطفي`, `مومن`), every و/ب/ل/ف/ك/لل prefix, any letter case, `كريديت 4321`, `كارت ٤٣ ٢١`, `كارت 4 3 2 1`, `43/21`, `43_21`, a newline between groups, `كارتي ٤٣٢١`, `بكارتي 4321`, and `card ending in 4321`. A nickname that is a common word («الشنطة») is masked everywhere, which is the safe direction.

**Safety net.** There is one `MaskResult` return (`reference_masker.dart:648`), and it comes after `_leaks`. A hit returns `MaskUnresolved(failed)` inside the `try`, so the net can't be bypassed. It re-folds `sentText` with the same `looseFold`, `_nameHits` and `_digitHits` as the masker. As a result, it only catches span-resolution bugs, not matching gaps: every leak below gets past both the masker and the net. See m14.

**Schema.** `_[1-9][0-9]?` matches what the masker emits (`_$n`, no cap). More than 99 entities of one kind can't fit in a 300-character question. See m13 for the missing cap and vectors.

### Findings

**M3 (major, privacy): a known last-4 still reaches `sentText` when glued to the card word, after a possessive card word, or split by a dash or comma.**
`reference_masker.dart:11` (`_wordRun` makes `كارت4321` one token), `:30` / `:321` (`_cardWords` / `_hasWord` handle prefixes only, not suffixes), `:243` (`_digitGroups` joins on a space only; `loose_text.dart:44` turns only `-` `_` `/` U+2212 into a space).

| Input (4321 is Ahmed's card) | Sent |
|---|---|
| `كارت4321`, `كارت٤٣٢١`, `visa4321` | unchanged |
| `كارتك 4321`, `كارتها 4321` | unchanged |
| `كارت 43–21` (en dash), `43—21` (em dash; iOS smart punctuation) | unchanged |
| `كارت 43,21`, `4,3,2,1`, `٤٣،٢١` (Arabic comma) | unchanged |

Dropping the space between a word and a number is common in Arabic typing. «كارتها» (her card) is the usual way to ask about a spouse's card. These are the same leak class as M2.

Required change:
- Treat a letter↔digit boundary as a token boundary for card-word and digit-group detection.
- Accept the pronoun suffixes ك/ه/ها/نا/كم/هم/و on card/account words (stem match).
- In the digit-group join, treat U+2010–2015, `,`, `،` and `:` as separators, like space, `-`, `.` and `/`.
- Add these vectors to the M2 property generator.
- Optional, closing all digit cases at once: also make the net fail closed on any known last-4 that appears after digit groups are joined across non-letter separators. This changes the «صرفت 4321 جنيه» rule (test at `reference_masker_variants_test.dart:268`), so it goes with the FU-364 OQ.

**Accepted known gaps** (not majors; none comes from ordinary typing of the user's own reference):
- **Look-alike letters from other scripts.** Cyrillic/Greek/Cherokee (`Сarrefour`, `Τalabat`, `Ꮯarrefour`), math alphanumerics (`𝐂arrefour`), Roman numeral `Ⅽ`, and Arabic Extended-A `ࢪ`. No Egyptian keyboard produces these inside a Latin or Arabic name. The threat is accidental disclosure by the user, not an adversary hiding their own data. Already listed in the task file.
- **Possessive or plural suffixes on names.** `كارفوري`, `كارفورها`, `طلباتي`, `Talabatey`, `Carrefours`, and a nickname with a possessive (`شنطتي`). Already listed (m4); low frequency; tracked with FU-364.
- **Names split by a space, emoji, comma or hyphen.** `كار فور`, `Carre four`, `C a r r e f o u r`, `كار🛒فور`, `حلواني🍰مصطفى`, `حلواني، مصطفى`, `كار-فور`, `N B E`. These are not real spellings of the name.
- **Spelling variants that are different letters, not folds.** `سبينز`, `الكاهرة` (ق→ك), `كوستى` / `كوسته` (final ا→ى/ه). The registry should supply these aliases (T-343, with m7).
- **Last-4 more than 3 words from the card word.** `…بيخلص بـ 4321`, `…آخر أربع أرقام فيه 4321`. Tracked in FU-364 (OQ).
- **Bank name glued to the card word.** `CIBcard`, `CIB<ZWSP>card`. This is the `بنكالأهلي` class.

**Minors (follow-ups):**
- **m13.** `docs/03-technical/ask-llm.md:46` still says `_[1-9]`. The contract vectors (`backend/tests/Zaghlol.Contract.Tests/vectors/ask-plan-v1.json`) have no `_10` accept case or `_100` reject case. The masker has no cap at 99: add one, or rely on the m6 input cap. The .NET contract tests were not run in the fix round; the batch GitHub run must cover them.
- **m14.** The safety net shares its matching with the masker, so it adds no coverage for matching gaps. Make it strictly wider:
  - For names of 4 or more folded letters, match a substring in text with spaces, punctuation and symbols removed.
  - Match a known last-4 joined across any non-letter separators, as in M3's optional item.
- **m15.** ZWSP/ZWNJ are dropped, not read as a space, so `CIB<ZWSP>card` glues. A dot inside a name is dropped but a hyphen becomes a space, so `كار.فور` is masked and `كار-فور` is not. Pick one rule. Nit-level.
- **Batch 91 note.** `task/T-331` embeds the old pattern in `packages/zaghlol_parsing/lib/chat/llm/plan_schema.g.dart:41`. `task/T-330` and `task/T-331` both carry `backend/contracts/ask-plan-v1.schema.json` with `_[1-9]`. After batch 90 merges, rebase both and regenerate `plan_schema.g.dart` from the widened schema. Otherwise the app rejects `_10`+ plans that the masker can now produce.
