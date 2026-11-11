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
- **Patterns** compile with Dart `RegExp`, case-insensitive, with a single leading `(?i)` accepted and dropped (Dart has no inline flags; any other inline flag is a compile error). Body and pattern are folded the same way (`foldKey` on the body, `foldArabicVariants` on the pattern), so templates may be written with either spelling of alef, ya, ta marbuta. Captures therefore come from lower-cased, folded text. Consequences: Latin merchants are upper-cased again by cleaning, Arabic merchant display text shows the folded letters (`ة` as `ه`). That residual stays until the pipeline (T-033) decides whether to map captures back to the original text.
- **Backtracking heuristic** (`backtrackingProblems`) is a check on the pattern text, not a proof, because Dart has no regex timeout. It rejects an unbounded quantifier on a group that contains an unbounded quantifier, a quantified group with an empty or duplicate alternative, lookarounds, backreferences, more than 6 unbounded `.` wildcards and patterns over 600 characters. Overlapping but different alternatives (`(a|ab)*`) are not detected.
- **Number and currency policy:** a number capture may be followed by one `.` or `,` (it is dropped); `0,123` style grouping is rejected. A `cur` capture is looked up in the template `currencyMap`, then as an ISO code or symbol; `$` on an account in another currency is USD (an explicit marker beats the account currency, like `£` and `€`), and `﷼` has no default. A `cur` capture that cannot be resolved is a problem, never a silent fall back to the institution currency. Without a `cur` group the institution `defaultCurrency` applies.
- **Fixtures** live outside the bundle: `app/test/fixtures/sms/<institution>/<case>.json` with `sender` (or `package` for notifications), optional `channel`, `body`, `receivedAt` (wall clock in the device zone; the offset is ignored) and `expect`. `expect.outcome` is `matched` (default, needs `template`), `dropped` (an institution or global drop pattern fired) or `unmatched`. Other `expect` keys: `direction`, `event`, `amount`, `currency`, `originalAmount`, `originalCurrency`, `last4`, `merchantClean`, `merchantKey`, `counterparty`, `ipa`, `phone`, `balance`, `available`, `ref`, `date`, `time`, `problems`. A key set to `null` means "must be absent". Extraction problems must be declared in `expect.problems` or the fixture fails.
- **Lint checks:** loader errors, every fixture, **cross-match** (a fixture body matched by more than one template of its institution and channel is an error, so templates must be disjoint on the fixtures), at least 4 passing fixtures per template (`--min-fixtures`), and the Guard config export (sorted and deterministic, under 200 KB, patterns exported as written). Output lists file paths and field names only, never message text or values.
- **CLI:** `dart run registry_lint [--registry dir] [--fixtures dir] [--min-fixtures n] [--guard-config file] [--check-guard-config file] [--write-manifest]` from `tools/registry_lint`; exit 0 clean, 1 findings, 2 usage or I/O error.
- The fixture runner uses a minimal extractor (`extractFields`: amount, currency, original amount, balance, available, last4, merchant, counterparty, ids, date). T-033 builds stages 0, 5, 7 and the generic fallback around it.

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

## 6. Post-parse stages (application layer, `IngestRawMessages`)

All of these run in **one DB transaction per message batch**, and the spool ack follows the commit.

| Stage | Rule | Doc |
|---|---|---|
| Dedupe 1 | `raw_messages.body_hash` unique: same body seen again → drop (BR-ING-02) | — |
| Dedupe 2 | Same institution + last4 + direction + amount + currency within ±2 min from a **different channel** → link the second raw message to the existing txn, no new txn (EC-01, A-30). Same channel with a different body → keep both (EC-02). | `domain-algorithms.md` §3 |
| Pending/settled merge | Template event `settled`, or a same-merchant match within ±5% within 7 days of a `pending_auth` → update the original amount, status `posted` (EC-54, A-63) | §3 |
| Account resolve | (institution, last4) → existing account, else auto-create (FR-ACC-01) with `kind` from the template; credit-card hints prompt S-06 | — |
| Balance update | If the message has balance/available and its `occurred_at ≥ as_of`, upsert `account_balances` | — |
| Categorize | §5 | — |
| FX conversion | `event = fx_conversion` → two transactions in the same multi-currency account + `transfer_pairs.kind = fx_conversion` (FR-PAR-12, EC-52) | §4 |
| Card settlement | `cc_payment` → transfer, paired with the outgoing payment if found (BR-TXN-04, EC-19) | §4 |
| Self-transfer pairing | BR-XFR-01/02 | §4 |
| Refund matching | BR-XFR-03 | §5 |
| Suggestions | Reimbursement (FR-XFR-08), cross-currency pair (FR-CUR-06), subscription (BR-SUB-01, debounced daily), payday (FR-ONB-10) → `review_items` | §5–7 |
| Events | `TransactionsChanged(accounts, cycles)`, `MascotTrigger`, `BudgetThresholdCrossed` | — |

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
