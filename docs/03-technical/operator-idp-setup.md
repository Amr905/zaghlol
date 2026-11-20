# Operator sign-in: IdP setup (T-136, input to the T-137 runbook)

The API validates IdP-issued tokens for `zaghlol-ops` (CLI) and the later admin app. The IdP is a **configuration choice** (`OperatorAuth:Profile = Entra | Google | Generic`); the PO's Q1 answer picks one section below. All settings are public values (no client secret: both clients are public PKCE clients). Config keys are in `deployment.md` (Operator tooling row). Validation rules and design: `docs/04-tasks/tasks/T-136.md` (design notes).

Common to both: authorization code + PKCE with a loopback redirect (RFC 8252); device-code grant off (R3-9; screenshot or export goes into the T-136 evidence section); token lifetime at most 60 min; operator rows are created with `backend/deploy/db/seed-operator.sql` using the operator's `sub`. The `operators` table decides who is an operator and which roles they hold; the IdP only proves who they are.

## Option A: Microsoft Entra ID
Sources: <https://learn.microsoft.com/entra/identity-platform/claims-validation>.

1. In the company tenant: App registrations, New registration, "Accounts in this organizational directory only" (single tenant). Redirect URI type "Mobile and desktop applications": `http://localhost` (loopback). Platform setting "Allow public client flows" = Yes (PKCE). Do not enable device-code / allow no other flows.
2. Manifest: `requestedAccessTokenVersion = 2` (or use ID tokens) so `iss` is `https://login.microsoftonline.com/{tenant-id}/v2.0`. Token lifetime policy: 60 min or less.
3. Optional: App roles on the registration (for example `flags_admin`, `support_agent`) and assign groups to them in Enterprise applications, Users and groups. Prefer app roles over groups (group overage drops the `groups` claim).
4. Conditional Access: require MFA for the app. For `support_agent` / `support_lead`, require an authentication strength of phishing-resistant MFA, ideally bound to an authentication context so the token carries `acrs` (then set `PhishingResistantMode=Enforced` and `RequiredAcrs`).
5. Fill config:
   - `OperatorAuth:Enabled=true`, `Profile=Entra`
   - `Issuer=https://login.microsoftonline.com/<tenant-id>/v2.0`
   - `Audiences:0=<client id of zaghlol-ops>` (and `Audiences:1=<admin app client id>`)
   - `AllowedTenants:0=<tenant-id>`
   - optional: `RoleClaim=roles`, `RoleMap:flags_admin=flags_admin` (app-role name to Zaghlol role)
   - `PhishingResistantMode=Advisory` or `Enforced` (+ `RequiredAcrs=<c1..c25>`)

## Option B: Google Workspace
Sources: <https://developers.google.com/identity/gsi/web/guides/verify-google-id-token>.

1. Google Cloud console (a project owned by the Workspace org): OAuth consent screen "Internal" (limits sign-in to the org). Credentials, OAuth client ID, type "Desktop app" for the CLI (loopback redirect). Repeat for the admin app later.
2. Workspace Admin: Security, 2-Step Verification: enforce for the operator OU; for the support OU allow security keys only. **The API cannot see this** (Google ID tokens have no `amr`/`nbf`/group claims), so this policy is the MFA control and `PhishingResistantMode` stays `Advisory`. Record the policy name and a screenshot in the T-136 evidence section.
3. Fill config:
   - `OperatorAuth:Enabled=true`, `Profile=Google`
   - `Issuer=https://accounts.google.com`
   - `Audiences:0=<OAuth client id>`
   - `AllowedDomains:0=<your Workspace domain>` (the token's `hd` must match; accounts outside Workspace have no `hd` and are refused)
   - no `RoleMap` (no role or group claims); roles come from the `operators` row only.

## Checks after filling config
Outside Development/Testing the API refuses to start if the config is incomplete or the discovery document and JWKS cannot be fetched at boot. A startup warning states the MFA control in force (Advisory mode, or Google). Sign in with `zaghlol-ops`: a token from another tenant/domain, another client, or without an `operators` row gets the single 401 body.

## CLI settings (T-137)
`zaghlol-ops` reads `ZAGHLOL_OPS_API_URL`, `ZAGHLOL_OPS_ISSUER` and `ZAGHLOL_OPS_CLIENT_ID` (environment or a JSON config file; details in `docs/ops/support-runbook.md` section 2). The redirect URI registered at the IdP must be the loopback `http://localhost` (or `http://127.0.0.1` when `ZAGHLOL_OPS_REDIRECT_HOST=127.0.0.1`); the CLI picks a free port at run time. Google desktop clients may demand a client secret that Google does not treat as confidential: if so, set it only as `ZAGHLOL_OPS_CLIENT_SECRET` in the environment (a config file never accepts it).

## CLI settings (T-137)
`zaghlol-ops` reads `ZAGHLOL_OPS_API_URL`, `ZAGHLOL_OPS_ISSUER` and `ZAGHLOL_OPS_CLIENT_ID` (environment or a JSON config file; details in `docs/ops/support-runbook.md` section 2). The redirect URI registered at the IdP must be the loopback `http://localhost` (or `http://127.0.0.1` when `ZAGHLOL_OPS_REDIRECT_HOST=127.0.0.1`); the CLI picks a free port at run time. Google desktop clients may demand a client secret that Google does not treat as confidential: if so, set it only as `ZAGHLOL_OPS_CLIENT_SECRET` in the environment (a config file never accepts it).
