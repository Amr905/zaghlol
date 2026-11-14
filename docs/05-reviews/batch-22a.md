# Review — batch 22a: SMS-TEMPLATES (C4) and DESIGN-0

| Field | Value |
|-------|-------|
| Reviewer | code-reviewer (Opus; code + security) |
| Date | 2026-11-14 |
| Diff | `origin/main...origin/task/SMS-templates` (080c9381), `origin/main...origin/task/DESIGN-0` (b87f6e41), merged in `batch/2026-11-14-22` |
| Verdicts | SMS-TEMPLATES: **CHANGES_REQUESTED** (1 money major) · DESIGN-0: **APPROVED** |

Commands run on the batch tree:
- `flutter test --exclude-tags benchmark,golden test/ingestion test/core/settings test/core/l10n test/features/widgets_bridge test/features/settings`: 188 passed.
- `tools/registry_lint`: `dart test` passed (8); `dart run registry_lint --registry ../../app/assets/registry --fixtures ../../app/test/fixtures/sms --check-guard-config ../../app/assets/guard/guard_base.json`: 47 institutions, 474/474 fixtures, 0 findings, Guard base not stale.
- Probe: two synthetic fixtures (CIB and Banque Misr EN purchase ending `Avl Limit: EGP 10,000.00`) through the same CLI: both `fixtureFailed (balance)` and `(available)`. The limit is extracted as `balance` (see M-1).

---

## SMS-TEMPLATES (C4): CHANGES_REQUESTED

### Checks
| Check | Result | Evidence |
|-------|--------|----------|
| Each PO sample row has a template and fixtures (AR + EN) with the right amount, currency, last-4, merchant or counterparty, balance or available, direction, event | PASS for the PO texts | lint 474/474; spot-checked CIB, HSBC, KFH, Citi, ADIB (`EGP 4000.` gives 4000.00), Yalla, all 6 InstaPay, Vodafone Cash, valU, Sympl, Souhoola |
| Amount in minor units, explicit currency, no silent conversion | PASS | every `cur` group only matches `egp`/`جم`/`جنيه` mapped to EGP; a USD message does not match and falls to generic (not mislabelled EGP) |
| Balance vs available limit kept apart | **FAIL for variants** | 41 EN templates use `(?:avl\|available\|bal)\D{0,16}(?<balance>…)`, which also matches `Avl Limit` (M-1); the flag is template-wide (m-1) |
| InstaPay / wallet / BNPL kinds | PASS | `instapay_out` (ipaAddress / phone), `instapay_in` (name), bill as `card_purchase`, `cc_payment` with target last-4 + counterparty, `refund` income with balance; wallets `transfer_out` with phone; BNPL `bnpl_installment` with `isAvailableLimit` for valU/Souhoola |
| Regex safety | PASS | `registry_lint` regex-safety rule clean; merchant groups are lazy and followed by a literal |
| Fixtures synthetic | PASS | PO-supplied synthetic texts; obvious placeholder names, refs and phone numbers |
| Generated Guard base + stale check in app-ci | PASS | `app/assets/guard/guard_base.json` (8.6 KB) equals the export; new app-ci step `registry_lint … --check-guard-config` |
| Registry loaded in every ingest path, custom templates on top | PASS | foreground runner and headless runner: `IngestionRunner._build` awaits `ensureDefaultRegistry()` (headless entry initialises the binding first, `ingestion_main.dart:72`); UI coordinator, scan service and settings read `captureRegistryLoaderProvider` after `main()` preloaded it; runner and scan both wrap with `registryWithCustomTemplates` |
| devSms = real base + spike sender; spike never replaces the real base | PASS | Dart: `spikeOnTopOf(bundledRegistrySync())`; Android: `BaseConfigSource.readForBuild` reads `guard/spike_guard_base.json` only present in `src/devSms/assets`; `spike_guard_base_test` pins that asset to the export of bundled + spike and checks the real senders are in it |
| No raw SMS logged | PASS | new code throws codes only (`INGEST_REGISTRY_INVALID/MISSING`); no prints or logs added |
| Kotlin/Swift Guard golden still agrees | PASS (unchanged) | golden reads `packages/zaghlol_parsing/test/fixtures/guard/golden.json` + its own configs, untouched; the shipped base uses the same `shared.json` drop/last-4 patterns, exported in the portable subset |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| M-1 | **major** (money/data) | `app/assets/registry/institutions/cib.json:53` and the same tail in 41 institution files (every EN template whose balance branch is `(?:avl\|available\|bal)\D{0,16}(?<balance>[\d,.]+)`) | `\D{0,16}` swallows ` Limit: EGP `, so a credit-card message from the same bank ending `Avl Limit: EGP 10,000.00` stores the credit limit as the account **balance**, with `balanceIsAvailableLimit=false`. The account is then inferred `debit` (`account.dart:181`) and the limit is written as its balance, which goes into net worth (`net_worth_repository.dart:137`). Reproduced with synthetic CIB and Banque Misr fixtures. | Make the balance branch refuse a limit: e.g. `(?:avl\|available)\.?\s*bal(?:ance)?\b\D{0,8}(?<balance>…)` (require "bal"), or a negative lookahead `(?![^\d]{0,16}limit)`. Templates are not exported to the Guard, so lookahead is fine. Optionally add an `available` branch for `limit` in the same templates. |
| m-1 | minor | `app/assets/registry/institutions/hsbc.json:43,63`, `kfh.json:43,63`, `citibank.json:43,67` | `isAvailableLimit` is per template, not per capture: a debit-card message from HSBC/KFH/Citi that ends with `Avl Bal` still matches (the tail is optional), so the account is inferred `credit`. | Split into a limit template (flag on, tail required) and a balance template (flag off), or follow up in the parser so the flag only applies when `available` was captured. FU. |
| m-2 | minor | all `senders` in `app/assets/registry/institutions/*.json` | Sender IDs are guesses (builder says so). Wrong guesses mean no capture for that bank; `EgyptPost` for OneBank/Yalla is a broad sender. No NBE. | PO to confirm sender IDs before release; FU on T-036. |
| m-3 | minor | `docs/04-tasks/tasks/T-036.md:40` (same note in T-031/037/068/069/070) | Build note says the registry is not wired and `guard_base.json` is not generated; later commits on the branch did both. | Update the notes. |
| m-4 | minor | `.github/scripts/sms-spike-device.sh:520-521` | The stagingSms `st_guard` assertion was dropped instead of changed to expect 1; the fail text on the spool line still says "without a Guard base". | Assert `st_guard = 1`; fix the message. |
| m-5 | nit | `app/lib/features/capture/application/capture_providers.dart:75-76` | Doc still says "T-036 replaces the missing bundled one". | Update comment. |

Tests to add with M-1: a synthetic fixture per affected template family (EN purchase ending `Avl Limit: EGP …`) expecting `balance: null`; the lint's fixture run then fails without the fix. Note `registry_lint` requires each fixture to match its template, so either expect `available` (if a limit branch is added) or keep the tail optional and expect both null.

---

## DESIGN-0: APPROVED

### Checks
| Check | Result | Evidence |
|-------|--------|----------|
| Fresh install opens light + Arabic | PASS | defaults `Settings.language = ar`, `Settings.theme = light` (`settings_keys.dart:29,39`); provider fallbacks before the stream loads also `ar`/`light`; `MaterialApp.themeMode` now wired (it was never applied before); `default_theme_language_test`: dark English device still opens light, Arabic, RTL |
| Explicit choice wins; `system` stays an option | PASS | `an explicit choice wins`, `system stays an option` tests; preferences screen keeps the System choice |
| Other consumers follow | PASS | notification strings use `appLocaleProvider` first; widget bridge test pinned to `en` explicitly |
| OFL licence present | PASS | `app/assets/fonts/OFL.txt` (IBM copyright + full SIL OFL 1.1); pubspec comment points to it |
| Design shots do not run in normal CI | PASS | `design_shot` tag; tests skip unless `DESIGN_SHOTS` is set; real fonts in tests only with `REAL_FONTS`/`DESIGN_SHOTS` |

### Findings
| # | Severity | File:line | Issue | Required change |
|---|----------|-----------|-------|-----------------|
| d-1 | minor | `app/lib/core/settings/settings_keys.dart:9-10` | Default change contradicts FR-ONB-03 ("device language until chosen"); the PO decision is cited only in code comments, not in `PO_DECISIONS.md` or the SRS. | Record the PO decision (Part 1) and amend FR-ONB-03. |
| d-2 | minor | `app/assets/fonts/OFL.txt` | The licence is in the repo but not shown in the app's licence page (`LicenseRegistry`); OFL is satisfied by the TTF name table, but listing it is cleaner. | FU: `LicenseRegistry.addLicense` for IBM Plex Sans Arabic. |

---

## Fix list (blocking only)
| Task | File:line | Required change | Test to add |
|------|-----------|-----------------|-------------|
| SMS-TEMPLATES | `app/assets/registry/institutions/cib.json:53` + the 40 other institution files with the `(?:avl\|available\|bal)\D{0,16}(?<balance>…)` EN tail | Balance branch must not match `limit` (require `bal`, or negative lookahead for `limit`); regenerate nothing else (templates are not in the Guard base, but re-run `--check-guard-config`) | Synthetic fixture(s) with an `Avl Limit: EGP …` tail expecting `balance: null` (or `available` if a limit branch is added), run by `registry_lint` / `real_registry_test` |
