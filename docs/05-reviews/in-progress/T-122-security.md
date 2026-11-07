## Security & privacy review: T-122 (EF Core model, initial migration, DB roles)

**Reviewer:** security-privacy-reviewer · **Branch:** `task/T-122-ef-model` @ `0b73ac5` · **CI:** backend-ci run 42352784130 (push, head `0b73ac5`, success)
**Scope read:** the T-122 task file and design note, backend-schema.md §1–§4, security-model.md, deployment.md, SRS (BR-SYNC-03/04, D-47/48/49/62, A-47, NFR-PRIV-*), the full `git diff origin/main...origin/t122`, and the in-progress T-122 test report.
**Live checks:** I ran a throwaway local PostgreSQL 16. It confirmed the digit-run bypass (F2) and the `?|` gaps (F3), and it validated the replacement CHECKs I propose for both.

### Verdict: **CHANGES_REQUESTED**

The baseline is strong:
- Schema `zaghlol`, owned by `migrator`.
- No `pgcrypto`; no column for a raw seat key, order ID, time nonce, IP or attestation verdict.
- Explicit grants, checked in both directions against `GrantMatrix`.
- Hardened SECURITY DEFINER triggers.
- Bootstrap has no passwords; the API is fail-closed at startup; readiness reveals nothing.

Four schema/grant problems (F1–F4) are cheap to fix now, because `InitialCreate` has not been applied to any shared environment. They should be fixed in this task: regenerate `InitialCreate` or add a second migration before merge. F5 needs a recorded decision from the Lead or user.

### Findings

| # | Severity | Where | Issue and leak/exploit path | Required change | Owner |
|---|---|---|---|---|---|
| F1 | **Medium** | `Persistence/GrantMatrix.cs:72-73` (`AccountsReadable`), `:144` (`ops_ro` gets `S` on every other table), `deploy/db/bootstrap-roles.sql:27,40` (`zaghlol_ops_ro` LOGIN) | `ops_ro` is a direct-DB login. It can `SELECT` `accounts.email`, `accounts.provider_subject`, `purchases.store_key`, `purchases.linked_purchase_token` and `store_notifications.store_key`. **(a)** An insider can bulk-read every user's e-mail without any audit row. That bypasses D-47/NFR-PRIV-07 ("every support lookup leaves an audit row") and security-model.md:139 ("operator access only through the admin API"; "no bulk export"). **(b)** A Google purchase token works as a bearer credential for restore: per EC-64, a shared token moves the seat. An `ops_ro` holder can harvest every token and take or share other users' Gold, which defeats D-46/D-52. `token_hash` was excluded for this kind of reason; these columns were not. | Remove `email`, `provider_subject`, `purchases.store_key`, `purchases.linked_purchase_token` and `store_notifications.store_key` from `ops_ro` (column lists like `InstallsReadable`). `ops_rw` keeps them, because the admin API needs them for lookup and the live ownership check. Also do one of: drop the `zaghlol_ops_ro` login from bootstrap until T-140 documents a break-glass procedure (with pgaudit), or document that procedure now. Add `Denied` cases to `GrantTests`. | backend-engineer (T-122); break-glass procedure: T-140 |
| F2 | **Medium** | `InitialCreate.cs:72,270,272`; `Configurations/ServiceConfigurations.cs:50-51,89-90` | The digit-run CHECK `!~ '[0-9]{6,}'` matches ASCII digits only. Verified on PostgreSQL: `'٠١٢٣٤٥٦٧'` (Arabic-Indic) and `'۰۱۲۳۴۵۶'` (Extended) pass. `[[:digit:]]` does not catch them either. A spaced phone such as `'010 1234 5678'` also passes. For an Egyptian product, the backstop on the BR-SYNC-04 "no phone numbers" rule misses the most likely forms. There are more gaps: no `@` guard, so an IPA handle passes, and `institution_code`/`category_code` (`:270`) are only length-capped, so they accept 64 characters of any text, phone numbers included. | Use `merchant_norm !~ '([0-9٠-٩۰-۹][[:space:].-]?){6,}' AND position('@' in merchant_norm) = 0`, and the same for `bank_requests.institution_name_norm`. Use `institution_code ~ '^[a-z0-9_]{1,64}$'` and `category_code ~ '^[a-z0-9_.]{1,64}$'` (match the catalog code alphabet). Add negative tests: Arabic-Indic, Extended, spaced and `@` cases. Update backend-schema.md §2/§3. | backend-engineer (T-122) |
| F3 | **Medium** | `InitialCreate.cs:53` and `ServiceConfigurations.cs:130` (`ck_audit_log_details_no_identifiers`); `InitialCreate.cs:46` (`target`) | `NOT (details ?\| array[...])` checks top-level keys only, and the match is case-sensitive. Verified: `{"x":{"email":..}}`, `{"Email":..}`, `{"x":[{"orderId":..}]}` and `{"ticket_ref":"a@b.c"}` are all accepted. `target` has no CHECK at all, so `target = 'user@x.com'` is accepted. D-57/NFR-PRIV-07 say e-mails and order IDs are never stored, and audit rows are kept 1–3 years. | Replace it with this CHECK (validated on PostgreSQL; `jsonb_path_exists` without `_tz` is immutable): `NOT jsonb_path_exists(details, 'lax $.** ? (@.type() == "object").keyvalue() ? (@.key like_regex "^(e-?mail\|order_?id)$" flag "i")') AND details::text !~ '@' AND position('@' in target) = 0`. Add negative tests for the nested, case and value forms. | backend-engineer (T-122) |
| F4 | **Medium** | `GrantMatrix.cs:141` (`worker_rw` `SD` on `audit_log`); `InitialCreate.cs:44` (`operator_id`, no FK) | The audit log is append-only for the API roles (verified: `app_rw` has nothing; `ops_rw` has SELECT/INSERT only). It is not tamper-resistant, though. `worker_rw` can `DELETE` any row, including the rows written today, so a worker bug or an injection in a job can erase support-action evidence. `operator_id` also has no FK, so `ops_rw` can insert rows attributed to an operator who doesn't exist. | Enable RLS on `audit_log` with `FOR SELECT` policies for the three readers, `FOR INSERT TO ops_rw`, and `FOR DELETE TO worker_rw USING ((action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze') AND at < now() - interval '1 year') OR (action NOT IN (...) AND at < now() - interval '3 years'))`. The owner (`migrator`) is unaffected. Add `operator_id REFERENCES operators(id)` (operators are disabled, never deleted). Add a test: `DELETE` of a fresh row as `zaghlol_worker` affects 0 rows. If the Lead defers this to T-139, record it there as an acceptance criterion. | backend-engineer (T-122, or T-139 with Lead sign-off) |
| F5 | **Medium** (process + repo config) | `.github/workflows/backend-ef-migration.yml:26-28,126-133,234-246`; repo setting | **(a)** This is a deviation from the approved design. The design note says the workflow is "workflow_dispatch… `permissions: contents: read`… **The workflow never pushes**." The implementation adds a `push` trigger and a `contents: write` commit job. **(b)** `main` has **no branch protection and no rulesets** (`gh api .../branches/main/protection` returns 404 "Branch not protected"; rulesets `[]`). "Never pushes to main" therefore depends on a single `REF_NAME` line. Worse, any workflow on any `task/**` branch can grant itself `contents: write` and push to `main`, because push-event workflows run from the pushed commit. | The Lead records an explicit approval of the push-mode deviation in the T-122 design note, or the workflow reverts to dispatch-only. The user/repo admin adds a ruleset on `main`: PR required, no direct pushes, no bypass for `github-actions[bot]`. The ruleset also covers `app-regen.yml`. | Lead + user (repo admin) |
| F6 | Low | `backend-ef-migration.yml:181,85,189` | **(a)** The path whitelist uses `printf '%s' "$rel" \| grep -Eq '^…$'`, and grep matches line by line. A path containing a newline passes when any one line matches, for example `…/Zaghlol.Infrastructure/x\n…/Migrations/20261107073856_A.cs`. Today this is blocked only by upload-artifact's ban on `\n` and by `git add` being scoped to `Zaghlol.Infrastructure`. Within that scope it could still land an arbitrary `.cs` file outside `Migrations/`. **(b)** File names aren't tied to `$NAME`, and an existing (shipped) migration may be overwritten, because the count check is 3 and "modified" files are collected. **(c)** `actions/setup-dotnet@v4` isn't SHA-pinned, and its output feeds the write job. | Use `[[ "$rel" =~ ^backend/src/Zaghlol\.Infrastructure/Persistence/Migrations/(...)$ ]]` and also reject `rel` containing `[^A-Za-z0-9._/-]`. Require exactly `<ts>_${NAME}.cs` and `<ts>_${NAME}.Designer.cs` with the same `<ts>`, plus the snapshot. Refuse if either migration file already exists in the tree. Pin `setup-dotnet` by SHA. Apply the same newline fix in `app-regen.yml:204-207`. | backend-engineer / Lead (CI) |
| F7 | Low | DB server config (not in repo); `PostgresDatabaseReadiness.cs:80-81` (good) | When a privacy CHECK fires, PostgreSQL logs `DETAIL: Failing row contains (…)` on the **server**, by default. The backstop that rejects a phone number in `merchant_norm` would write that phone number into the provider's DB logs (retention unknown, outside the D-47/NFR-PRIV-06 controls). Npgsql redacts Detail client-side unless `Include Error Detail=true`. | T-140: set `log_error_verbosity = terse` and `log_parameter_max_length_on_error = 0` on the managed instance, and document the retention of those logs. T-127: API validation must reject before the INSERT, with a test that the CHECK is never what fires. T-122/T-123: fail startup if any connection string sets `Include Error Detail`. | T-140, T-127, backend-engineer |
| F8 | Low | `InitialCreate.cs:62` (`bank_requests.country`), `:164/:235` (`app_version`), `:343` (`store_notifications.last_error`, doc says "error code only; never payload text"), `:337/:441` (`store_key`) | These are unbounded free-text columns with no format backstop. A client can put arbitrary data in `app_version` or `country`, and a future handler can write exception text into `last_error`. All are minor, because DTO validation is the primary control. | Add CHECKs: `country ~ '^[A-Z]{2}$'`; `app_version ~ '^[0-9]{1,4}(\.[0-9]{1,4}){1,3}([+-][0-9A-Za-z.]{1,32})?$'` in both tables; `last_error ~ '^[A-Z0-9_]{1,64}$'`; `char_length(store_key) <= 512`. | backend-engineer (T-122) |
| F9 | Low | `GrantMatrix.cs:102,81,150`; no BEFORE UPDATE trigger | The documented monotonic invariants live only in application code. `installs.seat_key_hash` is "set once, never replaced". `seat_key_trusted` is "only false → true" (it gates the over-cap sign-in rebind, D-65(a)). `attach_reclaim_used_at` is "NEVER cleared" (D-58), yet `ops_rw` holds column UPDATE on it. A bug or an injection in `/v1` or `/admin` can reset them and re-open a one-time reclaim or a trusted rebind. | Add a BEFORE UPDATE trigger on `installs` and `purchases` that raises when `OLD.seat_key_hash IS NOT NULL AND NEW.seat_key_hash IS DISTINCT FROM OLD.seat_key_hash AND NEW.deleted_at IS NULL`, when `OLD.seat_key_trusted AND NOT NEW.seat_key_trusted`, or when `OLD.attach_reclaim_used_at IS NOT NULL AND NEW.attach_reclaim_used_at IS DISTINCT FROM OLD...`. Optionally add `CHECK (deleted_at IS NULL OR (seat_key_hash IS NULL AND registration_key_hash IS NULL))`. | backend-engineer (T-122, or T-181/T-182/T-186) |
| F10 | Low | `GrantMatrix.cs:127-128,122-123,156`; `bootstrap-roles.sql:45-49` | Least-privilege trims. `worker_rw` has table-wide UPDATE on `installs` (includes `token_hash`) and on `purchases` (includes `account_id` and `account_linked_by`). `app_rw` has SELECT on `merchant_contributions` and `bank_requests`, needed only for EF `RETURNING received_at`. `ops_rw` has SELECT on `replay_guard`, which no admin endpoint uses. `CONNECT` on the database is still granted to PUBLIC. | Make worker UPDATE column-level: the registration/seat_key/deleted_at columns on installs; state, expires_at, acknowledged, last_verified_at and linked_purchase_token on purchases. For contributions, use `INSERT … ON CONFLICT DO NOTHING` without RETURNING (or grant column SELECT on `received_at` only). Drop `ops_rw` on `replay_guard`. `REVOKE CONNECT ON DATABASE … FROM PUBLIC` and grant CONNECT to the 5 logins. | backend-engineer |
| F11 | Low | `PersistenceServiceCollectionExtensions.cs:56-57` | Fail-closed covers a *missing* connection string only. If an operator puts the `migrator` (owner) or provider-admin credentials into `ConnectionStrings:App`, nothing stops it: the API would run as schema owner, which bypasses all grants and the two-login injection boundary. | At startup, run `SELECT rolsuper, pg_has_role(current_user,'migrator','MEMBER'), (SELECT nspowner = current_user::regrole FROM pg_namespace WHERE nspname='zaghlol')` per runtime role. Refuse to start unless the login is a member of exactly its expected group. | backend-engineer (T-122 or T-123) |
| F12 | Info | `SchemaTests.cs:219` | The denylist doesn't cover IPs, user agents, verdicts, receipts or raw payloads. | Add `(^\|_)ip(_\|$)\|user_agent\|verdict\|receipt\|jws\|raw_\|_payload$\|signature`, with explicit allow-list entries for any legitimate hits. | backend-engineer |
| F13 | Info | backend-schema.md §4 "Deleted installs/accounts: tombstone 30 days"; `idempotency_records` (no FK) | `accounts` has no tombstone column, so account deletion is an immediate hard delete. That is the better privacy outcome, but the doc is inconsistent. `idempotency_records` has no FK by design, so the immediate deletion on install or account delete depends on T-124/T-135 handlers (24 h is the backstop). | Fix the doc wording. T-124/T-135 need tests that `DELETE /v1/installs/me` and `DELETE /v1/accounts/me` remove the matching idempotency rows. | Lead (doc), T-124, T-135 |
| F14 | Info | `HealthProbe.cs:5` / Dockerfile HEALTHCHECK | The container HEALTHCHECK now probes readiness (DB-dependent), so a DB outage marks every API container unhealthy. That is an availability concern, not a leak. | T-140: keep orchestrator liveness process-level, per the design note. | T-140 |

### What I checked and accept (no finding)

- **Schema content vs BR-SYNC-03/D-48/D-62:**
  - There are no columns for a raw seat key, order ID, time nonce, device identifier, IP, verdict payload or raw envelope.
  - Seat material is only keyed hashes (`seat_key_hash`, `device_key_hash`).
  - `replay_guard` stores hashes only.
  - `store_notifications` holds extracted columns plus a digest.
  - `signing_keys` was correctly removed.
- **Triggers** (`InitialCreateSql.cs:22-47`):
  - Both are SECURITY DEFINER, owned by `migrator`, with `SET search_path = zaghlol, pg_temp`. `pg_temp` is last and names are fully qualified.
  - EXECUTE is revoked from PUBLIC, and trigger functions can't be called directly anyway.
  - `TEMPORARY` is revoked on the database, and only `migrator` can create objects in `zaghlol`.
  - Each body only nulls columns for `OLD.id`, so they can't be abused beyond the delete the caller is already allowed to do.
  - The test asserts exactly these two functions exist, so a smuggled extra definer function fails CI.
- **Roles:**
  - 4 NOLOGIN groups and 5 logins, each in exactly one group, all NOSUPERUSER/NOCREATEDB/NOCREATEROLE/NOREPLICATION/NOBYPASSRLS.
  - `migrator` has no memberships and no CREATEROLE/CREATEDB; the tests probe both.
  - `public` is revoked.
- **Grant rows the implementer asked about:**
  - `app_rw` DELETE on `accounts`: needed for `DELETE /v1/accounts/me`.
  - `app_rw` writes on `daily_active_counts`: aggregate counts only, no personal data (ADR-021).
  - `app_rw` SI on `merchant_contributions`: accepted, with the F10 trim.
  - `ops_rw` SELECT on `replay_guard`: F10.
- **Secrets:**
  - `bootstrap-roles.sql` sets no passwords.
  - Dev passwords exist only in `dev-passwords.sql` and compose.
  - The image copies `src/` only, so `deploy/` isn't in it.
  - Postgres is bound to `127.0.0.1` in compose.
- **Readiness:**
  - The 503 body is `{status, code: UPSTREAM_UNAVAILABLE, correlationId}` with `instance` stripped.
  - Only the exception type is logged.
  - The probe is bounded to 1 s, cached for 2 s and single-flight.
  - The migrate job logs only the type and SQLSTATE.
  - The connection strings and the default Npgsql detail redaction never reach logs.
- **Connection strings:**
  - App, Admin, Worker and Migrator are separate.
  - The migrator can't be registered at runtime (it throws).
  - `ValidateOnStart` fails closed when a string is missing (see F11 for a wrong-role string).
- **Deletion:**
  - Account delete: `account_installs` cascade, and the trigger nulls `account_id` and `account_linked_by` while keeping `attach_reclaim_used_at`. Audit rows stay until their own 1-year mark, per D-47.
  - Install delete: claimants and the attest key cascade, the seat is vacated, `device_key_hash` is kept per D-62, and `purchases.install_id` becomes NULL.
  - Contributions and bank requests keep only the peppered `install_hash`, which can't be joined back.
- **Retention indexes:** each §4 purge has a matching index:
  - `ix_audit_log_support_at`'s partial predicate equals the D-47 purge predicate.
  - The plain `ix_audit_log_at` serves the 3-year purge.
  - `ix_installs_last_seen` serves the 12-month purge.
  - `deleted_at` (partial) serves the 30-day tombstone purge; `first_seen_at WHERE registration_key_hash IS NOT NULL` serves the 24 h purge.
  - `received_at` covers contributions, bank requests and notifications.
  - `expires_at` covers the replay and idempotency tables; `claimed_at` covers claimants.
  - Promoted/rejected contribution deletes use the unique-index prefix.
- **Write job** of the workflow:
  - It runs no repo code. Hooks and fsmonitor are disabled, and the checkout uses `persist-credentials: false`.
  - Tracked symlinks are rejected, and every destination component is checked for symlinks.
  - There are checks for NUL bytes, size and file type.
  - The token appears only in the push step, as a masked header.
  - Every `${{ }}` value goes through `env:`.
  - The push target is `refs/heads/$REF_NAME` with `task/*` enforced in both jobs.

### Answers to the implementer's open questions

1. **Is `accounts.email` per design?** Yes. A-47/D-49 allow storing the e-mail from the ID token's `email` claim for support lookup only, and the audit trail stores just the `K_audit` HMAC (D-47). It must not be readable by `ops_ro`, though (F1). Keep it as an allowed exception in the denylist test.
2. **Is `app_attest_keys.public_key` per design?** Yes. It is the App Attest credential public key, needed to verify assertions (backend-schema §3 "Device attestation"). It isn't a seat key and isn't a device identifier.
3. **Are the top-level-only CHECKs on `audit_log.details` enough?** No. Nested keys, case variants and values inside other keys all get through, and `target` has no CHECK. Use the jsonpath CHECK in F3.
4. **The digit-run CHECK misses Arabic-Indic digits: does it matter?** Yes, it matters (verified). Spaced digits and `@` also get through. Fix as in F2.
5. **The 5 logins and 4 groups:** correct shape. F1 covers the `ops_ro` login's reach, and F10 covers CONNECT.
6. **Extra grant rows:**
   - `app_rw` DELETE on `accounts`: accept.
   - `app_rw` SI on `merchant_contributions`: accept, but drop SELECT or reduce it to `received_at` (F10).
   - `app_rw` writes to `daily_active_counts`: accept.
   - `ops_rw` SELECT on `replay_guard`: drop (F10).
7. **SECURITY DEFINER search_path:** it is pinned correctly and the functions can't be abused (see the accepted items above).
8. **Can `ops_ro` read anything sensitive?** `token_hash`, `apple_refresh_token_enc` and `response_body_enc` are correctly hidden. E-mail, provider subject and purchase tokens are still readable (F1).
9. **Is `audit_log` append-only for the API roles?** Yes. It isn't append-only against `worker_rw` (F4).
10. **`migrator` privileges:** appropriate. It is the owner, with no role or database creation and no superuser. It is never registered at runtime.
11. **Does the bootstrap SQL leak passwords?** No. Dev passwords are confined to compose.
12. **Do deletions remove personal data?** Yes, with `device_key_hash` kept by design. The idempotency-row deletion is handler-owned (F13).
13. **Do the retention indexes support the D-47 and 12-month purges?** Yes.
14. **Workflow: no repo code in the write job, symlink/path vetting, NUL check, no push to `main`, no secrets in logs?** All met in the script, except the line-based path regex (F6). "Never push to main" isn't enforced at repo level (F5), and push mode departs from the approved design (F5).
15. **Can a crafted migration smuggle executable content into a later CI run?** Yes, in principle. A migration is ordinary C#: a `[ModuleInitializer]`, a static constructor, or `migrationBuilder.Sql(...)` running as the schema owner in production. It is compiled into `Zaghlol.Infrastructure.dll` and loaded by the API, the workers and the migrate job. The bot commit adds no new capability, because only a branch pusher can trigger it and they could commit the same C# directly. It does lend "generated" provenance that reviewers may trust, though. Existing mitigations:
    - The grant-equality test catches any extra privilege.
    - The function-list test catches extra definer functions.
    - `has-pending-model-changes` catches snapshot drift.

    Still required:
    - Treat bot commits as code under review: CODEOWNERS on `Persistence/Migrations/**` and on `.github/workflows/**`.
    - Apply the F6 name/overwrite checks.
    - Add the F5 ruleset on `main`.
16. **Do readiness 503s leak database details?** No.
17. **Connection strings: separation and fail-closed?** They are separated, and startup fails closed when a string is missing. Add the role assertion in F11.

**Required before APPROVED:** F1, F2, F3 and F4 fixed in this task, or F4 explicitly moved to T-139 by the Lead. A recorded Lead decision on F5(a) and the `main` ruleset for F5(b). F6–F14 can be fixed here or tracked in the named tasks.