# Backend infrastructure (OpenTofu / Terraform, GCP) - prepared, NOT deployed

Status: T-140 preparation. Provider and region are **not yet chosen** by the PO (`docs/03-technical/hosting-options.md`).
This code targets the recommended option (GCP `europe-west3`) and can be dropped if the PO picks another provider.
Nothing here holds a secret, a state-backend credential or a long-lived key.

```
modules/network      VPC, subnet for Cloud Run direct VPC egress, private services access for Cloud SQL
modules/database     Cloud SQL PostgreSQL 17, private IP only, PITR, log_error_verbosity=terse, pgaudit
modules/kms          key ring; ES256 signing keys per kid; HMAC keys K_seat, K_audit, install_hash pepper; envelope key
modules/pubsub       RTDN topic, push subscription (OIDC, 7-day retention, no dead letter), push service account
modules/app          Secret Manager secrets (empty), Cloud Run API service, worker pool, migration job
modules/edge         global external ALB, Cloud Armor, managed certificate, CDN bucket, logging off
modules/environment  wires the above together for one environment (one GCP project per environment)
envs/staging, envs/prod   thin roots: variables + remote state (gcs, bucket passed at init)
scripts/seat-check.sh     computes Kms:HmacKeys:SeatCheck once per environment
```

## Check locally

```
tofu fmt -check -recursive
cd envs/staging && tofu init -backend=false && tofu validate     # needs access to the provider registry
```
CI does both in `.github/workflows/backend-iac-validate.yml` (also greps for static credentials, broad KMS roles, missing
`prevent_destroy`, rotation and LB logging).

## Key custody (AC "policy denies export")

- Grants are per key, never on the ring or project: API identity gets `roles/cloudkms.signerVerifier` (sign, verify, MAC,
  public key) on signing and HMAC keys and `cryptoKeyEncrypterDecrypter` on the envelope key; the worker gets only the
  envelope key. No role used here has an export permission, and Cloud KMS signing, MAC and encrypt keys are not exportable.
- HMAC and signing keys: pinned to `cryptoKeyVersions/1`, no `rotation_period`, `prevent_destroy`, 30-day scheduled destroy.
  A signing-key rotation is a new kid in `signing_keys` plus `signing_key_status` (Next, Active, Retired).
- Still to write (design note): policy-as-test beyond the CI greps (for example a `tofu plan -json` assertion), data-access
  audit logs for KMS, the C# cloud KMS adapter, and the JWK derivation for `Signing:Keys:<n>:PublicJwk`.

## First deploy (PO / operator, once per environment)

1. Create the GCP project, a GCS bucket for state (versioned, uniform access), and a workload identity pool + provider that trusts
   this repository for the `staging` / `prod` GitHub environments; create a deploy service account the pool may impersonate.
   Grant it only what the stack needs (project editor-style roles are not needed; scope to the services in
   `modules/environment` and `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`).
2. Commit `envs/<env>/settings.auto.tfvars` (copy `terraform.tfvars.example`; non-secret values only).
3. Bootstrap order (the image registry must exist before the first image): `tofu apply` with
   `-target=module.environment.google_artifact_registry_repository.images`, push the image, then run the workflow.
4. After the first apply: run `bootstrap-roles.sql` as the Cloud SQL admin (if `ALTER ROLE ... NOSUPERUSER` fails because
   `cloudsqlsuperuser` is not a superuser, make those statements conditional: T-122 follow-up), set the five login passwords,
   and add a first version to each secret in `secret_ids` (connection strings use `Host=<db_private_ip>;SSL Mode=Require`).
   Add the two service accounts (`api_service_account`, `worker_service_account` outputs) in Play Console, and paste
   `rtdn_topic` into Play Console. Point the DNS A record at `load_balancer_ip`.
5. `scripts/seat-check.sh <project> <region> <env>` and store the value as `kseat_check_hex` (repository variable `KSEAT_CHECK_HEX`).
6. For prod, grant the prod deploy service account `roles/artifactregistry.reader` on the staging repository so the workflow
   can promote the same digest.

## Variables the deploy workflow needs (GitHub environment variables, none secret)

Repository: `BACKEND_DEPLOY_ENABLED` (`true` to enable; unset keeps the workflow inert), `STAGING_IMAGE_REGISTRY`
(`<region>-docker.pkg.dev/<staging-project>/zaghlol/backend`). Per environment (`staging`, `prod`): `GCP_PROJECT_ID`,
`GCP_REGION`, `API_HOSTNAME`, `TF_STATE_BUCKET`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_DEPLOY_SERVICE_ACCOUNT`, `KSEAT_CHECK_HEX`.
Configure required reviewers on both GitHub environments (environment protection). Secrets live only in Secret Manager.

## Not covered yet

Observability wiring (`backend/deploy/observability`), the launch checklist (`docs/ops/launch-checklist.md`), the break-glass
procedure for `zaghlol_ops_ro`, and the edge sentinel-query smoke test: they stay in T-140 proper.
