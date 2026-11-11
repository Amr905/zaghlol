# catalog_build (T-030)

Builds the bundled, signed merchant/category catalog from a curated CSV.

```
cd tools/catalog_build
dart run catalog_build --input data/catalog_curated.csv \
  --out ../../app/assets/catalog --csv-out data/catalog_seed.csv \
  --key dev/dev_signing_key.json [--version 1] [--check]
```

Inputs and outputs

| File | Role |
|---|---|
| `data/catalog_curated.csv` | Source of truth. Backend column set. `alias` cells may be raw text. A merchant row's `match` is the match mode of the alias derived from its own name. Merchant ids are the 1-based row order: **append only**. |
| `app/assets/catalog/catalog_seed.json.gz` | The seed: `{version, ops[]}` (OpenAPI `CatalogSnapshot`, upserts only), canonical JSON, gzip. |
| `app/assets/catalog/catalog_seed.json.sig` | `Zaghlol-Signature` header (`kid=..; alg=ES256; sig=..`) over the **inflated** JSON bytes. Signing is deterministic (RFC 6979). |
| `data/catalog_seed.csv` | Output for the backend: same columns, aliases already normalized. Import it with the T-125 seed import into an empty draft: the backend allocates merchant ids in the same row order, so ids match the app. Never feed it back to this tool (aliases would be keyed twice; stored keys are never re-keyed). |

Rules enforced at build time

- Every alias is keyed with `merchantKey` from `zaghlol_parsing` (parsing-engine section 5), tested against `packages/zaghlol_parsing/test/fixtures/merchant_key_vectors.json`. A key shorter than 2 characters fails the build.
- A spaced leading article (`AL MARAI`) also gets its attached spelling (`ALMARAI`); see `aliasVariants`. The reverse is never guessed.
- One alias key may belong to one merchant only.
- Keywords are stored folded (`foldKey`).
- Category names, colours and buckets are catalog data (copy deck, "category names ... localized in the catalog seed"); there are no ARB keys for them.

`dev/dev_signing_key.json` is a DEV key whose private half is committed on purpose. The app trusts only `bundledSeedKeys()` (`packages/zaghlol_catalog`); a store release must re-sign with a production Sync key and swap the trusted key (FU-078).

`--check` writes nothing and exits 1 when a committed output is stale; `test/catalog_build_test.dart` runs it.
