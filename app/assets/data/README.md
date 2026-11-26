# assets/data — name, honorific and business-word lists (T-325)

Bundled lists for the LLM-categorise person-name check (FR-LCAT-05 rule e, `docs/03-technical/llm-categorise.md` §2 rule 5).

| File | Content | Entries |
|---|---|---|
| `eg_given_names.txt` | Common Egyptian given names: Arabic script plus common English transliterations | ~2,100 |
| `eg_business_words.txt` | Business and shop words (Arabic and English) | ~150 |
| `eg_honorifics.txt` | Honorifics stripped before the name check: أ، أستاذ، م، د، دكتور، حاج، حاجة، Mr, Mrs, Ms, Dr, Eng | 12 |

Format: UTF-8, no BOM, one entry per line, sorted by code unit, deduplicated, NFC-normalised. Every line is already folded with `foldKey` (FR-PAR-04): alef variants to ا, ى to ي, ة to ه, no diacritics or tatweel, ASCII lower case.

## Sources and licence (OQ-LCAT-05)

- **Given names:** compiled by the project author from general knowledge of common Egyptian and Arabic given names and their common Latin transliterations. No list was copied wholesale from any published or copyrighted source. Individual given names are not copyrightable facts.
- **Honorifics:** the list in `docs/03-technical/llm-categorise.md` §2 rule 5 (project spec).
- **Business words:** the list in `docs/01-requirements/llm-categorise.md` FR-LCAT-05 (e) and the §2 rule 5 spec list, plus common shop and company type words added by the author.

Status: compiled from general knowledge (not from a public-domain dataset). Before the flag goes ON, legal and UX review of these lists is still required (OQ-LCAT-05).

No entry is a real person's full name, a phone number or a merchant name.
