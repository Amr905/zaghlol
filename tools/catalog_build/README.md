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
| `data/catalog_curated.csv` | Source of truth. Backend column set. `alias` cells may be raw text. A merchant row's `match` is the match mode of the alias derived from its own name. Merchant ids are the 1-based row order (**append only**), local to the seed and not the backend's. |
| `app/assets/catalog/catalog_seed.json.gz` | The seed: `{version, ops[]}` (OpenAPI `CatalogSnapshot`, upserts only), canonical JSON, gzip. |
| `app/assets/catalog/catalog_seed.json.sig` | `Zaghlol-Signature` header (`kid=..; alg=ES256; sig=..`) over the **inflated** JSON bytes. Signing is deterministic (RFC 6979). |
| `data/catalog_seed.csv` | Output for the backend: same columns, aliases already normalized. Import it with the T-125 seed import into an empty draft. The backend allocates its own merchant ids (one shared draft identity counter), so they do **not** match the app's seed ids; see FU-079. Never feed it back to this tool (aliases would be keyed twice; stored keys are never re-keyed). |

Rules enforced at build time

- Every alias is keyed with `merchantKey` from `zaghlol_parsing` (parsing-engine section 5), tested against `packages/zaghlol_parsing/test/fixtures/merchant_key_vectors.json`. A key shorter than 2 characters fails the build.
- A spaced leading article (`AL MARAI`) also gets its attached spelling (`ALMARAI`); see `aliasVariants`. The reverse is never guessed.
- One alias key may belong to one merchant only.
- Keywords are stored folded (`foldKey`).
- Category names, colours and buckets are catalog data (copy deck, "category names ... localized in the catalog seed"); there are no ARB keys for them.

`dev/dev_signing_key.json` is a DEV key (kid `s0000a`) whose private half is committed on purpose. `--key` refuses any kid that is not `s0000x`: a production key is never exported to a file. The app trusts `s0000a` only outside release builds (`allowDevKeys: !kReleaseMode`), so a release build that still carries the dev-signed seed loads no catalog. A store release bundles the backend's KMS-signed snapshot instead (FU-078, FU-079).

`--check` writes nothing and exits 1 when a committed output is stale; `test/catalog_build_test.dart` runs it.
