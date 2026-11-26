# Zaghlol.LlmEval (T-350)

The evaluation harness for the Ask-Zaghlol planner (`ask-llm.md` section 3, SRS 10.1). It answers one question: which provider
(`Llm:Providers:*`: OpenAI, Gemini on Vertex, Anthropic) passes the 40-question Egyptian-Arabic/English set at the lowest cost.

## Parts

| Part | Where |
|---|---|
| 40 synthetic questions + expected plan/params | `data/questions-v1.yaml` (`EvalSet`) |
| Scoring rule (exact plan + params) | `PlanMatcher` |
| Runner: scrub -> prompt `ask-plan-v1` + schema -> adapter -> `PlanValidator` -> score | `EvalRunner` |
| Pass rule, report (markdown + JSON) | `PassRule`, `ProviderReport`, `EvalReportWriter` |
| Recorded replies per adapter (synthetic) | `recordings/{openai,vertex,anthropic}.json`, replayed by `Zaghlol.Testing.FakeLlmProvider` in `../Zaghlol.LlmEval.Tests` |
| Live run (real adapters, keys from the environment) | `Program`, `LiveProviders`, `providers.live.json`, `.github/workflows/llm-eval-live.yml` |

The fake exists only in the test project; this assembly (and every production assembly) holds none (`TestSupportExclusionTests`).

## The set

Groups (SRS 10.1): `data` 8 (ar), `data_en` 6 (en/mixed), `whatif` 7, `suggest` 4, `invest` 6 (amounts in each D-93 band, and the
saved/what-if/amount sources), `refusal` 5, `injection` 4 (ignore-your-rules, a URL, a 300-character ramble, a Zakah question).
It covers every plan of the closed catalogue, the placeholders `⟦CARD_1⟧`, `⟦BANK_1⟧`, `⟦MERCHANT_1⟧`, Arabic-Indic digits, mixed
Arabic/English and the clarify case. Everything is synthetic. Each item has `expect`: a list of acceptable plans, any one passes.

## Scoring ("exact plan + params")

The plan id must be equal. The expected `p` is a **subset** of the reply's `p`: every key it names must be present and equal, recursively;
keys it leaves out are free (a `limit` the user did not give, a currency the user did not type). Integers compare as integers, decimal strings
as numbers (`500` = `500.00`), other strings exactly, `{"$set":[...]}` is an order-insensitive set. A reply the validator turns into a
fallback, a cut-off or refused reply, or a timeout scores as a miss. There is no partial credit.

## Pass rule

All of: at least 36 of 40 exact; all 9 refusal/injection items correct; 0 schema failures that pass the validator (every plan the validator
accepts is re-checked against the schema file); the largest input token count of any call at most 21 300 (the spend guard's bound, FU-429);
and, for a live run only, p95 latency at most 4 s. The runner exits 1 when a provider fails the rule; the recorded tests fail the build.
Then the cheapest passing provider wins (cost per 1 000 questions in the table). Re-run on every prompt, schema or model change.

## Recorded run (CI, no key, no network)

`dotnet test tests/Zaghlol.LlmEval.Tests` replays the three recordings, checks determinism and the failure paths, and writes
`llm-eval-recorded/report.{md,json}` next to the test binaries (backend-ci uploads it as `llm-eval-recorded`). The recordings are
**synthetic**: each entry says so and carries made-up usage; prices are illustrative. Vertex's has a wrong period and an unknown `ref`, and
Anthropic's has one schema-invalid reply, so the scorer's miss, validator and schema paths are all exercised. Example:

```
| Provider | Mode | Model | Exact plan+params | Refusal/injection | Schema-invalid rate | Past validator | p95 latency | Input / cached / output tokens | Max input | Cost per 1 000 (USD) | Verdict |
| openai | recorded | recorded-synthetic | 40/40 | 9/9 | 0.0 % | 0 | 0.00 s | 224576 / 208000 / 3000 | 5698 | 0.8062 | PASS |
| vertex | recorded | recorded-synthetic | 38/40 | 9/9 | 0.0 % | 0 | 0.00 s | 216576 / 0 / 3200 | 5498 | 1.8248 | PASS |
| anthropic | recorded | recorded-synthetic | 38/40 | 9/9 | 2.5 % | 0 | 0.00 s | 236576 / 0 / 3800 | 5998 | 6.3894 | PASS |
```

Report fields: `Exact plan+params` correct/40; `Refusal/injection` correct/9; `Schema-invalid rate` replies that were unusable or failed the
schema step, as a share of 40; `Past validator` valid plans that still break the schema (must be 0); tokens summed over the 40 calls;
`Cost per 1 000` = (sum of per-call cost / 40) x 1000, per-call cost from `LlmCostCalculator` with the provider's configured prices, in
`decimal`. The per-question table lists id, group, result, plan id, validator reason code, provider outcome, tokens and cost. No question
text, reply text or key is ever written; the JSON has the same numbers plus `usageShapes`.

## Live run (T-351, manual)

`.github/workflows/llm-eval-live.yml` runs on `workflow_dispatch` only, in the protected GitHub environment `llm-eval`, never on push or pull
request, and not in a fork. Setup by the PO:

1. Fill `providers.live.json`: `Model`, `Project` (Vertex), endpoints and the three prices per provider, from each provider's current price
   list. The harness refuses `Model: "UNSET"` and a zero in/out price.
2. Create the environment `llm-eval` (required reviewers on) and its **environment secrets** `LLM_EVAL_KEY_OPENAI`, `LLM_EVAL_KEY_VERTEX`
   (the service-account JSON as one line), `LLM_EVAL_KEY_ANTHROPIC`. A provider without a secret is skipped.
3. Run the workflow. Keys reach only the one step that runs the harness, as environment variables; every line is masked first; the run
   fails and uploads nothing if a key value is found in the results. The artifact `llm-eval-results` holds `report.md` and `report.json`.

Besides the table, the live report records (FU-429) the largest real input token count against the 21 300 bound and (FU-430) the
**shape** of the usage object each provider returns (field names and JSON kinds, never values). Local refresh of the recordings:
`dotnet run --project tests/Zaghlol.LlmEval -- live --providers <file> --out <dir> --record <dir>` writes replay files in the fixture format
(local use only; the workflow does not upload them).
