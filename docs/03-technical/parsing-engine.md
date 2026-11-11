# Message Parsing Engine (`packages/zaghlol_parsing`)

The engine is pure Dart and deterministic, with templates held as **data** (FR-PAR-08, D-17). Adding or fixing a bank means adding a JSON template and fixtures, which is a C1/C2 task. The engine runs in the main isolate, a worker isolate or the headless background engine.

## 1. Pipeline

```
RawMessage
  → 0 Guard re-check        (same rules as native; defense in depth)
  → 1 Normalize             digits, separators, whitespace, tatweel, bidi marks, Unicode NFKC
  → 2 Resolve institution   sender/package → institution (registry) | generic
  → 3 Match template        ordered templates of that institution (+ user custom templates, Gold)
  → 4 Extract fields        named groups → typed fields (Money, last4, merchant, balance, ref, datetime)
  → 5 Classify direction    template-declared, or keyword rules for generic
  → 6 Clean merchant        strip POS/terminal codes, city/country suffixes; normalize key
  → 7 Score confidence      template base score × field completeness × sanity checks
  → 8 Generic fallback      if no template matched and source is generic or registry-but-unmatched
  → ParseResult { fields, direction, status, templateId, confidence, reasons[] }
```
Stages 9 onwards are categorize, dedupe, pair and persist. They live in the application layer (`IngestRawMessages`) because they need the DB (§6).

Every stage is a pure function with its own tests. Total time is under 10 ms per message on the reference device (NFR-PERF-01): regexes are precompiled at registry load and cached per isolate.

## 2. Normalization (stage 1, FR-PAR-04, EC-03)

| Step | Rule | Example |
|---|---|---|
| Digits | Arabic-Indic `٠-٩` and Extended `۰-۹` → ASCII `0-9` | `١٥٠` → `150` |
| Decimal / thousands | `٫` → `.`, `٬` → `,`, narrow NBSP and NBSP → space | `١٬٢٥٠٫٠٠` → `1,250.00` |
| Invisible marks | Remove RLM, LRM, ZWJ, ZWNJ and BOM | — |
| Tatweel & diacritics | Remove `ـ` and harakat (for matching only; the stored body is untouched) | `جـنيه` → `جنيه` |
| Arabic letter variants (matching keys only) | `أإآ`→`ا`, `ى`→`ي`, `ة`→`ه` | — |
| Whitespace | Collapse runs, trim | — |

The amount parser handles the three grouping styles of FR-PAR-11:
- `1,234.56`;
- `1.234,56` (EU, allowed only if the template declares `locale: eu`);
- `1,23,456.78` (Indian).

Precision follows the currency exponent: `KWD 12.345` → 12345 minor (EC-36), and `JPY 1500` → 1500. If the decimal count exceeds the exponent, the template is wrong and parsing fails, which sends the message to review. Values are never rounded silently.

## 3. Registry format (bundled `assets/registry/`)

```json
// assets/registry/institutions/nbe.json
{
  "code": "nbe", "names": { "ar": "البنك الأهلي المصري", "en": "National Bank of Egypt" },
  "country": "EG", "defaultCurrency": "EGP",
  "senders": [ { "match": "exact", "value": "NBE" }, { "match": "exact", "value": "AlAhly" } ],
  "packages": [ "com.ofss.alahly" ],
  "walletCardNames": [ "NBE", "الأهلي" ],
  "last4": [ "\\*\\*(\\d{4})", "رقم (\\d{4})" ],
  "drop": [ "(?i)\\bOTP\\b", "رمز التحقق" ],
  "templates": [
    {
      "id": "nbe.card_purchase.ar", "version": 2, "lang": "ar", "channel": ["sms"],
      "event": "card_purchase", "direction": "expense", "baseConfidence": 0.98,
      "pattern": "تم خصم (?<amount>[\\d,.]+) (?<cur>جم|EGP|USD) .*?بطاقة .*?\\*\\*(?<last4>\\d{4}) لدى (?<merchant>.+?) (?:يوم|في) (?<date>\\d{1,2}/\\d{1,2})(?:.*?الرصيد المتاح (?<balance>[\\d,.]+))?",
      "currencyMap": { "جم": "EGP" },
      "date": { "format": "d/M", "yearPolicy": "nearest_past" },
      "flags": { "isAvailableLimit": false }
    },
    { "id": "nbe.card_foreign.en", "version": 1, "lang": "en", "event": "card_purchase_fx", "direction": "expense",
      "pattern": "(?<ocur>[A-Z]{3}) (?<oamount>[\\d,.]+) .* charged (?<cur>EGP) (?<amount>[\\d,.]+) .*\\*(?<last4>\\d{4})",
      "baseConfidence": 0.97 }
  ],
  "fixtures": "fixtures/nbe/"            // ≥ 4 per template: AR, EN, and edge variants (FR-PAR-01)
}
```

**Template semantics:**
- **Named groups:** `amount`, `cur`, `oamount`/`ocur` (original currency, FR-TXN-04), `last4`, `merchant`, `counterparty`, `ipa`, `phone`, `balance`, `available`, `ref`, `date`, `time`.
- **Event:** `event` drives later stages. Values: `card_purchase`, `card_purchase_fx`, `atm_withdrawal`, `transfer_out`, `transfer_in`, `instapay_out`, `instapay_in`, `salary`, `refund`, `reversal`, `declined`, `fee`, `cc_payment`, `fx_conversion`, `pending_auth`, `settled`, `wallet_topup`, `bnpl_installment`, `balance_only`.
- **Version:** `version` is bumped on any change. `registry_manifest.json` holds `registryVersion`, the max over all templates, used for re-parse.
- **Lint:** the `tools/registry_lint` CLI validates schema, compiles regexes, rejects catastrophic-backtracking patterns, runs all fixtures and fails CI on any regression. It also generates the native Guard config subset.

**As built (T-032).** The logic is pure Dart in `packages/zaghlol_parsing/lib/registry/` (functions take file contents; no I/O); `tools/registry_lint` only reads the directories.
- **Bundle:** `registry_manifest.json` (`{schema, registryVersion, institutions[]}`; `registryVersion` must equal the max template `version` and the list must equal the institution files), `shared.json` (global `drop.global`, `last4`, `shortcutKeywords`, `generic{senderHints, bodyHints, alwaysCapture}`, `merchantCleaning{countryTokens, cityPhrases, legalSuffixes, noiseTokens}` merged with the built-in seed lists) and `institutions/<code>.json`. `code` must equal the file name.
- **Strict schema:** unknown keys, wrong types, unknown `event`/`direction`/`lang`/`channel`, an unknown group name, a missing `amount` group (except `balance_only`), a `date` block without a `date` group, duplicate template ids and duplicate exact sender ids across institutions are errors. A registry with any error is never returned by the loader (fail closed). `direction` is `expense`, `income` or `neutral` (declines, balance notices). `baseConfidence` is written as a decimal with at most 3 digits (`0.98`) and stored as thousandths (980); the engine uses no floating point.
- **Guard-bound patterns** (sender regexes, `drop`, `last4`, `generic` hints) compile like the Guard compiles them since T-035: leading `(?i)` removed, Arabic variants folded, `RegExp(p, unicode: true)`, case-sensitive (they must be lowercase; platform-channels §1.1 *Portable regex subset*). Sender regexes run on `foldKey(source)`. The adversarial bodies of the runtime probe also include runs of `*` and `x` (mask characters), which caught `\*{2,}(\d{4})` as quadratic.
- **Template patterns** compile with Dart `RegExp`, case-insensitive, with a single leading `(?i)` accepted and dropped (Dart has no inline flags; any other inline flag is a compile error). Body and pattern are folded the same way (`foldKey` on the body, `foldArabicVariants` on the pattern), so templates may be written with either spelling of alef, ya, ta marbuta. The regex runs on the folded text. T-032 returned captures from that text too, so display text came out lower-cased and with folded letters; T-033 fixes this for the display groups (see "As built (T-033)").
- **Backtracking heuristic** (`backtrackingProblems`) is a check on the pattern text, not a proof, because Dart has no regex timeout. It rejects an unbounded quantifier on a group that contains an unbounded quantifier, a bounded repeat above 3 of such a group (`(a+){1,50}`), a repeating group with an empty, duplicate, optional-twin (`a|a?`) or prefix-overlapping (`a|aa`) alternative, lookarounds, backreferences, more than 6 unbounded `.` wildcards and patterns over 600 characters. Overlap that is not a literal prefix (`(\w|\d)+`) is not detected.
- **Number and currency policy:** a number capture may be followed by one `.` or `,` (it is dropped); `0,123` style grouping is rejected. A `cur` capture is looked up in the template `currencyMap`, then as an ISO code or symbol; `$` on an account in another currency is USD (an explicit marker beats the account currency, like `£` and `€`), and `﷼` has no default. A `cur` capture that cannot be resolved is a problem, never a silent fall back to the institution currency. Without a `cur` group the institution `defaultCurrency` applies.
- **Fixtures** live outside the bundle: `app/test/fixtures/sms/<institution>/<case>.json` with `sender` (or `package` for notifications), optional `channel`, `body`, `receivedAt` (wall clock in the device zone; the offset is ignored) and `expect`. `expect.outcome` is `matched` (default, needs `template`), `dropped` (an institution or global drop pattern fired) or `unmatched`. Other `expect` keys: `direction`, `event`, `amount`, `currency`, `originalAmount`, `originalCurrency`, `last4`, `merchantClean`, `merchantKey`, `counterparty`, `ipa`, `phone`, `balance`, `available`, `ref`, `date`, `time`, `problems`, and the pipeline keys `confidence` (permille, as text), `needsReview` (`true`/`false`), `occurredAt` (`YYYY-MM-DDTHH:mm:ss`), `language`, `reasons` (list of reason codes) and `counterpartyKind` (a fixture that sets any of them also needs the pipeline to pick the same template). A key set to `null` means "must be absent". Extraction problems must be declared in `expect.problems` or the fixture fails.
- **Lint checks:** loader errors, every fixture, **cross-match** (a fixture body matched by more than one template of its institution and channel is an error, so templates must be disjoint on the fixtures), at least 4 passing fixtures per template (`--min-fixtures`), and the Guard config export (sorted and deterministic, under 200 KB; since T-035 the base part of platform-channels §1.1, with every Guard-bound pattern in the portable regex subset and a **last-4 parity** check: on every passing fixture whose `expect.last4` is set, the Guard's last-4 must equal it, issue `guardLast4Mismatch`). Output lists file paths and field names only, never message text or values. T-033 adds a **runtime guard** (`slowMatch`): the fixture runner times each template match (limit 100 ms, injectable) and the lint runs adversarial bodies (digits only, Arabic words only, the template's own fixture body repeated) of 64, 128, 256 and 512 characters per template, stopping at the first size over the limit. Dart cannot interrupt a running regex, so this measures after the fact: it catches polynomial blow-up at a small size, but a truly exponential pattern would still hang the lint run (the heuristic above is the first line for those, and CI has a job timeout).
- **CLI:** `dart run registry_lint [--registry dir] [--fixtures dir] [--min-fixtures n] [--guard-config file] [--check-guard-config file] [--write-manifest]` from `tools/registry_lint`; exit 0 clean, 1 findings, 2 usage or I/O error.
- The fixture runner uses a minimal extractor (`extractFields`: amount, currency, original amount, balance, available, last4, merchant, counterparty, ids, date). T-033 builds stages 0, 5, 7 around it (below); the generic fallback is T-073.

**As built (T-033).** `ParsingPipeline(registry).parse(ParseRequest)` in `packages/zaghlol_parsing/lib/pipeline/`; pure, synchronous, never throws (an unexpected failure becomes `ParseUnrecognized(internalError)`), no logging, no message text in any non-field result.
- **Request and result.** `ParseRequest{body, source, channel, receivedAt}` (`receivedAt` is the device wall clock as a UTC-flagged `DateTime`; only its y/m/d h:m:s count). `ParseResult` is sealed: `ParseParsed` (institution, template id and version, `language`, `event`, `direction`, `fields`, `confidencePermille`, `reasons`, `needsReview`), `ParseDropped` (`globalPattern` or `institutionPattern`) and `ParseUnrecognized` (`emptyBody`, `bodyTooLong`, `unknownSource`, `noTemplateMatched`, `invalidAmount`, `invalidCurrency`, `internalError`, and from T-073 `genericNoAmount`, `genericDeclined`; with institution and template ids only).
- **Order.** The body is capped at 4000 characters, folded once (`foldKeyIndexed`: the `foldKey` text plus a map back to original offsets), then the institution is resolved, then stage 0 runs on the folded text (institution drop, then global drop; the global drop patterns run on `foldKeyLines` text, where a line break is kept as `\n`, as in the Guard, platform-channels §1.2; an OTP from an unknown sender is dropped, not unrecognized), then an unknown source that does not qualify for the generic parser returns `unknownSource` (one that qualifies goes to stage 8, see "As built (T-073)"). Templates are filtered by channel and tried in registry order, those of the detected language (Arabic letters at least as many as Latin; a tie is Arabic) first and the other language after. The first template that matches and extracts wins. A template whose amount or currency cannot be read is skipped and the next one is tried; if none succeeds the first such failure is returned.
- **Fields.** `ParsedFields{amount, originalAmount, balance, available, balanceIsAvailableLimit, last4, merchant, counterparty{kind: ipaAddress|phone|name, name, ipa, phone}, ref, date, time, occurredAt, occurredAtSource}`. `amount` is the billed amount in the account currency, `originalAmount` the foreign one. Everything the message does not carry is null. Without a `last4` group in the template, the institution `last4` patterns and then the shared ones are tried (first hit); a template that owns a `last4` group is never second-guessed. `occurredAt` is the one resolved value (§4.4): date and time from the message; date only takes the time of day of `receivedAt`; time only takes the received date, or the day before if that is later than receipt; neither takes `receivedAt`. `occurredAtSource` records the rule, and `date`/`time` stay null when absent.
- **Original-text display captures.** `merchant`, `counterparty`, `ipa`, `phone` and `ref` are read from the original message (`matchTemplateOriginal`) and then normalized by `foldForMatching` only (Arabic-Indic digits, tatweel and harakat removed; case and alef/ya/ta-marbuta kept), so `أحمد محمود` shows as written. Dart reports no group offsets, so the capture is located by its folded text inside the matched region; when the same folded text occurs twice there, the position is ambiguous and that group falls back to the folded capture (letters folded, Latin lower-cased). A residual, covered by a test.
- **Confidence.** Integer permille: `baseConfidence x product(factor)`, floored after each factor, clamped 0..1000. Factors (`ParseReason`): `dateOutOfRange` (more than 3 days ahead or 2 years back), `dateInvalid`, `timeInvalid`, `originalAmountInvalid` 700; `balanceInvalid`, `availableInvalid`, `last4Invalid`, `merchantEmpty` 800; `sparseFields` (no last4 and no merchant, counterparty or reference; not for `balance_only`) 900. `kAutoAcceptThresholdPermille = 850`: below it `needsReview` is true (saved with a `low_confidence` item). A missing or invalid amount or currency is not a penalty: the message is `ParseUnrecognized` and keeps its raw text as a review item.
- **Direction** is the template's (`expense`, `income`, `neutral`); keyword direction rules belong to the generic parser. **Time forms:** `H:mm`, `HH:mm:ss`, `h:mm am/pm` and `ص`/`م`.
- **Signed balances (FU-078, as built in T-046).** A `balance` or `available` capture may start with one `-` or `−` (U+2212): the value is a negative `Money` and the result carries the informational reason `balanceNegative` (factor 1000, no penalty). Two signs, or a sign on `amount`, stay invalid (`balanceInvalid` / not a match). The template's group must capture the sign (`(?<balance>-?[\d,.]+)`); a template whose group does not allow it reads no balance from such a message (unchanged). `-0.00` is zero, no reason.
- **Not handled yet.** User custom templates (T-164).

**As built (T-073).** `packages/zaghlol_parsing/lib/generic/` (`generic_parser.dart`, `generic_keywords.dart`, `generic_policy.dart`); the pipeline calls it for an unknown source (stage 8).
- **Eligibility** (`isGenericCandidate`): the source is in `generic.alwaysCapture`; or the channel is `shortcutMessage`, `applePay` or `share`; or `senderHints` match the source and `bodyHints` match the body. Otherwise `unknownSource`. Drop patterns still run first (an OTP from an unknown sender is dropped). A known institution never falls back to the generic parser.
- **Result.** `ParseGeneric{language, amount, direction?, last4?, merchant?, occurredAt, confidencePermille, reasons}`; `needsReview` is always true and confidence is capped at 700 permille (`kGenericMaxConfidencePermille`), below the 850 threshold. `occurredAt` is the receipt time: no date or time is read. Eligible messages with nothing usable return `ParseUnrecognized(genericNoAmount)`; messages with a decline word (`declined`, `failed`, `رفض`, `فشل`, `لم يتم`...) return `genericDeclined` (a failed attempt is not a transaction).
- **Amount and currency.** A number is a candidate only when a currency marker touches it (symbol, 3-letter ISO code, or an AR/EN currency word from `generic_keywords.dart`), before or after, spaces only between. Numbers inside dates and times (`23/10`, `11:14`, `2026-10-23`) are skipped. A marker between two numbers goes to the number with no other marker, else to neither. Numbers within 28 characters after a balance word (`balance`, `avail`, `limit`, `رصيد`, `متاح`) are skipped. ISO codes that are English words (`all`, `try`, `top`, `pen`...) are never read as a currency. `ريال`, `دينار`, `pound` and `Rs.` alone are ambiguous and give no currency: there is no fallback currency. The candidate nearest a direction keyword wins; two different amounts with no keyword to separate them keep the first and add `amountAmbiguous`.
- **Direction** is `expense`, `income` or null. Opposite keywords whose distances to the amount differ by 20 characters or less give null with `directionConflict`; no keyword gives null with `directionUnknown`. So "payment received" with both words next to the amount is left null by design. `transferred to ...` has no keyword and stays null.
- **last4** comes from `globalLast4` first, then a built-in marked pattern (`**1234`, `xx1234`, `ending 1234`, `card 1234`, `رقم البطاقة 1234`, `المنتهي بـ 1234`); a bare four-digit number is never taken. **Merchant**: after `at`, `to`, `from`, `لدى`, `عند`, `الى`, `من`, up to 4 tokens until a stop word, a number, a currency or end punctuation; a Latin span must start with a capital in the original text; tokens that are half digits are rejected; then `cleanMerchant`.
- **Confidence.** 700 x `amountAmbiguous` 700, `directionConflict` 800, `directionUnknown` 800, `sparseFields` 900 (no last4 and no merchant), floored per step in that order.
- **A-66** (`genericDisposition(confirmedCount, alwaysCapture)`): `review` unless `alwaysCapture` and at least `kGenericConfirmationsRequired` (3) confirmations, then `autoSaveLowConfidence`. Counting confirmations and the `capture_senders` row are the ingest layer's job (T-046); the parser itself can never return an auto-acceptable result.
- **Known gaps.** An FX message with the foreign amount nearer the keyword than the billed amount picks the foreign one (`Total EGP 3,400 (EUR 100) debited` gives EUR 100). No balance, date, reference or counterparty extraction. `Rs.`, `ريال` and `دينار` need a template or a qualifier. Direction words outside the dictionaries leave direction null.
- **Lint probe (T-033 M-2).** The runtime adversarial probe now also covers each institution's `drop` and `last4` lists and the shared `globalDrop`, `globalLast4` and `bodyHints`, and its ladder ends at 4000 (the pipeline cap). Since T-035 fix round 2 the bodies also include digits separated by line breaks, and `globalDrop` is probed on `foldKeyLines` text; the fixture runner applies `globalDrop` to `foldKeyLines` text too.

**Fixtures** (`fixtures/<inst>/<template>/<case>.json`): synthetic only, never real customer data (CLAUDE.md §2.6).
```json
{ "sender": "NBE", "channel": "sms", "body": "تم خصم 450.00 جم من بطاقة فيزا **4567 لدى CARREFOUR MAADI EG يوم 23/10. الرصيد المتاح 12400.00 جم",
  "receivedAt": "2026-10-23T11:14:00+03:00",
  "expect": { "template": "nbe.card_purchase.ar", "direction": "expense", "amount": "450.00", "currency": "EGP",
              "last4": "4567", "merchantClean": "Carrefour", "balance": "12400.00", "date": "2026-10-23" } }
```

## 4. Matching, extraction, confidence (stages 3–7)

1. Candidate templates come from the resolved institution, filtered by channel and language. The language is detected by Arabic-letter ratio, with templates of both languages tried in order. User custom templates (Gold) are tried first for their sender.
2. The **first** template whose `pattern` matches with all its required groups wins. Templates are ordered most specific first, which the linter enforces by checking fixtures don't cross-match.
3. **Sanity checks** each reduce confidence by 0.1–0.4 and add a `reason`:
   - amount > 0, and the decimals fit the currency;
   - the date is no more than 3 days in the future or 2 years in the past;
   - `last4` is numeric;
   - balance ≥ 0;
   - the merchant isn't empty after cleaning.
4. **Date policy:**
   - When the message gives no year, choose the year that makes the date nearest in the past to `receivedAt`.
   - When it gives no time, use `receivedAt`'s time.
   - Timezone is the device zone at receipt (EC-10).
5. `confidence = baseConfidence × Π(penalties)`. If it is ≥ `kAutoAcceptThreshold` the transaction is saved; otherwise it is saved **and** a `low_confidence` review item is added. Messages that match no template become `unrecognized` review items, with the raw message kept. The threshold starts at 0.85 (A-12) and is tuned on fixtures in Phase 5.

## 5. Merchant cleaning & matching (stage 6 + categorization)

**Cleaning (FR-PAR-05):**
1. Upper-case Latin, normalize Arabic.
2. Remove trailing terminal/POS IDs (`\b\d{3,}\b$`) and `POS`, `ECOM` and `ONLINE` tokens.
3. Remove country codes (`EG`, `EGY`, `ARE`…) and known city tokens (`MAADI`, `CAIRO`, `NASR CITY`, `القاهرة`… from a list in the registry).
4. Remove legal suffixes (`LLC`, `CO`, `S.A.E`, `ش.م.م`).
5. Collapse spaces.

Display uses the catalog canonical name if matched, else title-cased cleaned text (`CARREFOUR MAADI EG 041` → `Carrefour`).

**`merchant_norm` key (exact rule, T-034):** (1) `foldKey` (digits, tatweel, harakat, alef/ya/ta-marbuta unified, lowercase); (2) a leading Arabic article `ال` is removed; (3) Arabic is transliterated with a small Egyptian-friendly table (`ع`→`a`, `ق`→`k`, `ث`→`s`, `ذ`→`z`…), every character outside `a-z0-9` becomes a space, spaces collapse and trim; (4) at most one leading article is removed: a first token `el`/`al` when another token follows, or an attached `el`/`al` (`elezaby`) when at least four characters follow and the word does not start with a common English stem (`elect`, `eleven`, `album`…); (5) adjacent single-character tokens are joined (`b t e c h` → `btech`), other tokens stay separated by one space; (6) cap 64, then trim a trailing space. The output is `[a-z0-9]` words separated by single spaces (`ELEZABY`, `EL EZABY`, `El-Ezaby` → `ezaby`; `KOSHARY EL TAHRIR` → `koshary el tahrir`). The key is applied once per side (parse time and catalog build); stored aliases are never re-keyed. Golden vectors: `packages/zaghlol_parsing/test/fixtures/merchant_key_vectors.json`, shared with the catalog_build tests. Merchant cleaning strips only short country codes (`EG`, `EGY`, `ARE`, `UAE`), never full names that can belong to a merchant (`بنك مصر`, `NATIONAL BANK OF EGYPT`).

**Lookup order** (BR-CAT-01):
1. **User rule** (`merchant_rules`): by catalog merchant, by `merchant_norm`, or by counterparty for IPA/phone.
2. **Catalog exact alias** (`catalog_aliases.alias_norm = merchant_norm`).
3. **Catalog prefix/token alias** (longest match wins).
4. **Fuzzy:** FTS5 trigram candidates (top 10), scored with Jaro-Winkler on `merchant_norm`. Accept if ≥ 0.92, and ≥ 0.88 when the institution matches a contributed alias (FR-CAT-06: `ELEZABY`, `EL EZABY`, `صيدليات العزبي` → El Ezaby).
5. **Keyword heuristics** (`catalog_keywords`): weighted sum per category, accepted if the top score ≥ 60 and beats the runner-up by 20.
6. Else **needs classification**.

Person-to-person transfers (IPA or phone counterparty) skip catalog and keywords and go straight to rules, then needs classification (BR-CAT-03).

**Categorizer design (T-075; full note in `docs/04-tasks/tasks/T-075.md`).**
- **Rules run in two calls, same precedence.** `match(counterparty, merchantNorm)` first; then, once steps 2–4 have found a catalog merchant, `match(catalogMerchantId)`. Order among rules: counterparty, then `merchant_norm`, then catalog merchant (A-68). A rule always beats the catalog category.
- **Step 3 (prefix/token):** an alias matches only on whole-token boundaries; `prefix` = the key starts with the alias, `token` = the alias is a contiguous token run anywhere in the key. The longest alias wins (then `prefix` over `token`).
- **Step 4 (fuzzy):** only for keys of at least 6 characters (spaces removed), both sides. Jaro-Winkler (p 0.1, prefix cap 4) on the key and on its space-less form, best of the two, computed in exact integer arithmetic as millionths (no floating point); accept at 0.92 (920000); digits must agree; a runner-up of a different category within 0.02 makes the step ambiguous and it falls through. The 0.88 "contributed alias" tier is **off** until the catalog can say which aliases are contributed (open question PO-1).
- **Step 5 (keywords):** matched on `foldKey` of the cleaned merchant text (Arabic kept, not the transliterated key), whole tokens, a leading `ال` ignored.
- **Person-to-person** means counterparty kind `ipa`, `phone` or `person`; `own_account` is not categorized (internal transfer).
- **Sources written:** `user_rule`, `catalog` (steps 2–4), `heuristic` (step 5), `none`. Never `user`.

## 6. Post-parse stages (application layer, `IngestRawMessages`)

All of these run in **one DB write transaction per message batch** (`BEGIN IMMEDIATE`), with **one savepoint per message**: a message that fails on a constraint is stored alone for review (`unrecognized`, `ingestFailed`) and the batch continues; a busy, I/O or full error rolls back the whole batch. The spool ack follows the commit and covers every message of the batch (stored, merged, duplicate, dropped, deferred). Parsing runs before the transaction. Full rules: T-046 design note.

| Stage | Rule | Doc |
|---|---|---|
| Dedupe 1 | `raw_messages.body_hash` unique: same body seen again → drop (BR-ING-02) | — |
| Dedupe 2 | Same institution + last4 + direction + amount + currency within ±2 min from a **different channel** → store the second raw message (`parsed`) and fill only the NULL fields of the existing txn, no new txn (EC-01, A-30). Last-4 may be absent on one side (PO Q1 of T-046, provisional); the window also matches on the raws' `received_at`. Same channel with a different body → keep both (EC-02). | `domain-algorithms.md` §3 |
| Pending/settled merge | Template event `settled`, or a same-merchant match within ±5% within 7 days of a `pending_auth` → update the original amount, status `posted` (EC-54, A-63) | §3 |
| Account resolve | (institution, last4) → existing account, else auto-create (FR-ACC-01) with `kind` from the template; credit-card hints prompt S-06 | — |
| Balance update | If the message has balance/available and its `occurred_at ≥ as_of`, upsert `account_balances` | — |
| Categorize | §5 | — |
| FX conversion | `event = fx_conversion` → two transactions in the same multi-currency account + `transfer_pairs.kind = fx_conversion` (FR-PAR-12, EC-52) | §4 |
| Card settlement | `cc_payment` → transfer, paired with the outgoing payment if found (BR-TXN-04, EC-19) | §4 |
| Self-transfer pairing | BR-XFR-01/02 | §4 |
| Refund matching | BR-XFR-03 | §5 |
| Suggestions | Reimbursement (FR-XFR-08), cross-currency pair (FR-CUR-06), subscription (BR-SUB-01, debounced daily), payday (FR-ONB-10) → `review_items` | §5–7 |
| Events | `IngestRawMessages` emits one `TransactionsChanged(accountIds, cycleKeys)` per committed batch, after the commit, and nothing on failure. `BudgetThresholdCrossed` and `MascotTrigger` come from the budget, pairing and duplicate engines reacting to it | — |

**Event → transaction (T-046).** `card_purchase`, `card_purchase_fx`, `atm_withdrawal`, `bnpl_installment` → expense, posted; `pending_auth` → expense, pending; `settled` → expense, posted (merged into the pending one when found); `declined` → expense, declined (BR-TXN-03); `transfer_out/in`, `instapay_out/in`, `cc_payment`, `wallet_topup` → `transfer_out`/`transfer_in` by the template direction, posted; `salary` → income; `refund`, `reversal` → refund; `fee` → fee; `balance_only` → no transaction (raw `parsed`, balance only). An event without a registered handler (`fx_conversion` until T-089) stores the raw message as `reparse_pending` and creates nothing; the re-parse job runs it again. Every `ParseGeneric` goes through `genericDisposition` with the `capture_senders` row (FU-080); ingest never changes `confirmed_count`.

**As built (T-046).** `app/lib/features/ingestion/` (`domain/` pure rules and types, `application/ingest_raw_messages.dart`, `data/drift_ingest_store.dart`); the spike's raw-row-only commit is replaced inside `IngestionCycle`. Decisions at single points: `domain/ingest_policy.dart` (PO Q1–Q3, provisional — PO to confirm), `domain/ingest_rules.dart` (event table, dedupe key, windows, ±5 %, cycle key). Details:
- `body_hash` v1 and the frozen `hashNorm` in `domain/body_hash.dart`, golden vectors cross-checked with an independent SHA-256. `ux_raw_body_hash` stays the backstop: a copy that slips past the dedupe-1 read rolls back its savepoint and counts `ING_DUP_RACE`.
- Dedupe 2 reads candidates by `dedupe_key` (±24 h), then filters in code (source, status class, two clocks, last-4). The receive-time clock uses the candidate's **own** raw row (`transactions.raw_message_id`); a raw row attached by a merge is not linked to its transaction (no column), so it never widens a later window.
- Pending/settled: the forward window is P in [T − 7 d, T + 2 min], the symmetric one X in [T − 2 min, T + 7 d] (2 min of clock slack both ways). Soft-deleted pending rows are not merge targets. Dedupe 2 does include soft-deleted rows; a soft-deleted or user-verified target is attach-only (no field is filled, the account is not moved, it stays deleted), and the new message's balance is still recorded. A settled amount that changes P also rewrites P's `dedupe_key`.
- User-confirmed input: the parser channel for `paste`/`ocr`/`pdf`/`csv` is `share`; generic and unrecognized user input goes to review like background input (T-049 owns the confirm flow).
- Generic auto-save (A-66, PO Q3 provisional): one account per sender, `institution_code` = `g_` + 16 hex of SHA-256 of the sender key (no sender text in a code column), label = the sender as received. The capture_senders row is matched by sender key and channel. Residual: the parser's generic eligibility does not read `capture_senders`, so an always-capture sender that matches neither `generic.alwaysCapture` nor the hints is `unknownSource` (review) until the registry or T-049 adds it.
- New account labels: the registry institution name in `settings.language` (`en…` English, else Arabic).
- Residuals: an inbox copy whose receive time differs from the original by more than the window, arriving before it, is stored as its own transaction (the original is then a dedupe-1 duplicate). A payment whose pending SMS was merged with a settled **notification** and whose settled SMS arrives later becomes two transactions (the SMS shares the pending row's source, so dedupe 2 skips it, and no pending row is left); proposed as a follow-up in the T-046 report (owner suggestion: T-089).

**Re-parse:** when `registryVersion` increases after an app update, a background job re-parses `raw_messages` whose status is `review`, plus messages parsed by templates whose version changed. User-verified transactions are never modified.

## 7. Generic parser (FR-PAR-13)

For sources the Guard classified as *generic*:
1. **Amount:** find amount candidates by currency token adjacency (`EGP|ج.م|جنيه|USD|\$|€|£|SAR|ر.س|…` before or after a number). The candidate nearest a direction keyword wins.
2. **Direction:** from keyword dictionaries (AR/EN), e.g. `debited|withdrawn|purchase|خصم|سحب|شراء` → expense; `credited|received|deposit|إيداع|تحويل وارد` → income.
3. **Other fields:** last-4 via the global patterns; merchant via the `at|from|to|لدى|من|إلى` + capitalized-span heuristic.
4. **Result:** always a review item (`new_sender`) with suggested fields; nothing is auto-saved. After the user confirms 3 parses from the same sender and turns on "always capture", messages are auto-saved but still marked `low_confidence` until a template exists (A-66).
5. **"Request my bank"** (FR-PAR-14) queues `{institutionName, country, channel}` in the outbox; never the message.

Target: ≥ 80% correct amount + currency on the unseen-format test set (FR-PAR-13 acceptance).

## 8. Custom templates (Gold, FR-PAR-07)

The user highlights the amount (required), merchant, last-4 and date in a sample message. The builder produces a template in three steps:
1. Escape the literal text.
2. Replace the highlighted spans with typed groups, using the amount regex for the currency and `\d{4}` for last-4.
3. Generalize digit runs elsewhere to `\d+` and whitespace to `\s+`.

The builder tests the template against the sample and against the user's other messages from that sender, showing match counts before saving. Templates are stored in `custom_templates`, included in backups, and never uploaded.

## 9. Voice & OCR text reuse

- OCR output (receipt lines) goes through dedicated "screen" templates (`instapay.receipt_screen.*`, `wise.app_screen.en`) using the same engine, with the `ocr` channel and user confirmation (FR-ING-I-04).
- Voice uses a separate grammar (`domain-algorithms.md` §9). It reuses only the amount normalizer and the category keyword matcher.
