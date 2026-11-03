# backend/openapi

`zaghlol-v1.yaml` is the machine-readable contract for the Zaghlol backend API v1 (OpenAPI 3.1). It is written from `docs/03-technical/backend-api.md` (sections 1 to 6). Both the .NET backend and the Flutter app are checked against it.

| File | Purpose |
|------|---------|
| `zaghlol-v1.yaml` | The contract: 14 public operations under `/v1`, 12 operator operations under `/admin/v1`, headers, security schemes, problem+json errors |
| `.spectral.yaml` | Spectral ruleset (`spectral:oas` plus Zaghlol rules: no `number` or `float` types, every operation declares problem responses) |

## Rules the file follows

- **Request schemas are closed** (`additionalProperties: false`, including nested items and every `oneOf` branch). This is how BR-SYNC-03 is enforced on the wire: the server answers `400 UNKNOWN_FIELD` to any other field. Do not add a field for messages, transactions, amounts, balances, budgets, assets or user rules.
- **Response schemas are open**, because v1 only changes additively and clients ignore unknown fields.
- **Money and prices are decimal strings** (`DecimalString`) next to an ISO 4217 `currency`, never JSON numbers.
- **Timestamps** are RFC 3339 UTC and end in `Z` (`UtcTimestamp`).
- Every error response is `application/problem+json` with the `Problem` schema and a code from `ProblemCode`. The code list must match section 6 of `backend-api.md`.
- Changing the contract means changing the document first, then this file, then the code.

## Checks

```sh
# Lint (same command as CI, job "OpenAPI lint (Spectral)"; warnings fail too)
cd backend/openapi
npx --yes @stoplight/spectral-cli@6.15.0 lint zaghlol-v1.yaml --ruleset .spectral.yaml --fail-severity=warn

# Contract tests (spec structure, live responses, docs consistency)
cd backend
dotnet test tests/Zaghlol.Contract.Tests
```

`tests/Zaghlol.Contract.Tests` covers:

- **Live conformance:** boots the real API in-process and validates the actual `/v1/health` response and the problem+json responses (404, 405, 400, 500) against the schemas. Each new endpoint adds its tests here as it is implemented.
- **Unknown fields:** every request schema is closed, and for every request example, adding an unexpected field at any object level makes it invalid.
- **Structure:** every error is problem+json; `Zaghlol-Signature` on all signed responses; `Idempotency-Key` only on the three documented operations; install-scoped calls require `Zaghlol-App` and `Zaghlol-Install`; notification endpoints never accept install or account tokens; admin operations use only the operator scheme and declare `x-required-roles`; no `number`, `float` or `double` anywhere.
- **Docs:** the endpoint tables (sections 2 and 5) and the error code table (section 6) of `backend-api.md` match the spec, and every code in `Zaghlol.Domain.ErrorCodes` is documented.

## Dart DTOs for the app (to wire in after T-001 merges)

Nothing is generated or created under `app/` by T-006. The intended approach is below, so T-124 and T-141 can use it.

**Package:** `packages/zaghlol_api_contract` (a member of the pub workspace in `pubspec.yaml`, per `docs/03-technical/project-structure.md`). It holds only models, with no HTTP client.

**Why models only.** Every signed response (`/v1/sync`, verify, restore, entitlement, sign-in, the catalog snapshot) has to be verified against `Zaghlol-Signature` over the exact response bytes before it is decoded. A generated client that decodes JSON on its own would defeat that, so the app keeps its own thin transport and uses the package for request and response types.

**Generation (preferred).** `openapi-generator-cli` 7.x with the `dart-dio` generator and `built_value` (it handles `oneOf` and nullable types best), producing models only:

```sh
npx --yes @openapitools/openapi-generator-cli@2.x generate \
  -i backend/openapi/zaghlol-v1.yaml \
  -g dart-dio \
  -o packages/zaghlol_api_contract \
  --global-property models,modelTests=false,modelDocs=false,supportingFiles=false \
  --additional-properties=pubName=zaghlol_api_contract,serializationLibrary=built_value,enumUnknownDefaultCase=true,nullSafe=true
```

- `enumUnknownDefaultCase=true` is required so that a new `ProblemCode` or status added on the server does not break old apps.
- `packages/zaghlol_api_contract/lib/` is generated and committed; CI regenerates it and fails on a diff.
- Pin the generator version in the repository (the `@openapitools/openapi-generator-cli` version and `openapitools.json`) so output is reproducible.

**Fallback if the generated `oneOf` types are awkward.** Hand-maintain the DTOs in the same package (only about ten are needed: install, sync request and response, the catalog ops, verify and restore requests and responses, entitlement, sign-in, problem) and add a Dart schema test that loads `zaghlol-v1.yaml` and checks that (a) each request DTO serializes to keys that are all in the schema's `properties` and include every `required` key, and (b) the sample responses in `app/test/fixtures/api/` (copied from the spec examples) parse without loss. The Dart test, not the generator, is then the guard against drift.

Either way the DTO for money fields must keep them as strings and convert to integer minor units at the domain boundary; never `double`.
