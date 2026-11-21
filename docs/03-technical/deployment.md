# Deployment Considerations

## 1. Environments

| Env | App build | Backend | Stores | Data |
|---|---|---|---|---|
| `dev` | debug, flavor `dev` (bundle `app.zaghlol.dev`) | local Docker Compose (API + Postgres + fake price provider) or shared dev | Play internal app sharing; Xcode | Synthetic only |
| `staging` | release, flavor `staging` (`app.zaghlol.staging`) | `api.staging.zaghlol.app`; Play/App Store **sandbox** purchases; RTDN test topic; ASSN sandbox URL | Play internal testing; TestFlight internal | Synthetic test accounts |
| `prod` | release, flavor `prod` (`app.zaghlol`) | `api.zaghlol.app` | Play closed → staged production; TestFlight external → App Store phased release | Real |

**Android distribution flavors** (ADR-004):
- `prodSms` declares `READ_SMS`/`RECEIVE_SMS` and is the build submitted with the Play SMS declaration.
- `prodNoSms` omits the SMS permissions (notification + share/paste + manual + voice). It is ready to ship immediately if Play rejects or later revokes the exception (D-02, R-01).

Both builds share the same applicationId and code. A capability check hides the SMS UI in `prodNoSms`.

## 2. Mobile build & release pipeline (GitHub Actions)

```
PR:      dart format --set-exit-if-changed · flutter analyze · custom lints (no double money, no raw print)
         · unit tests (domain, parsing fixtures, registry_lint) · widget + golden tests (ar/en, light/dark)
         · Kotlin unit tests (Guard, Robolectric) · Swift unit tests (Guard) on macOS runner
main:    + integration tests on Android emulator (API 26, 34, 36) and iOS simulator (17, 26)
         + privacy_scan integration test + performance benchmarks (parse/scan/cold start) with budgets
tag vX:  build prodSms + prodNoSms AAB (signed via Play App Signing upload key from secrets)
         + iOS IPA (match/fastlane, App Store Connect API key) · upload symbols & mapping
         → Play internal track + TestFlight → manual promotion
```

**Store requirements** to track at each release:
- Play: target API 36 (Android 16) for updates after the extension window; Play Billing Library 8+ (bundled by `in_app_purchase_android` 0.5.x).
- Play: the Data safety form must match `security-model.md` §2.
- Apple: privacy nutrition labels, with **no** tracking and "data not linked to you" except purchase history for signed-in users.
- Apple: Sign in with Apple offered whenever Google sign-in is offered on iOS.
- Apple: account deletion in-app (FR-ACCT-04).

**Versioning:**
- App: semver `MAJOR.MINOR.PATCH+build`.
- `registryVersion` (SMS templates) and the bundled `catalogVersion` are recorded in the build and in About.

**Release cadence:** template updates ship in regular app releases (D-17). The target is a fortnightly release train, plus hotfix releases for parser regressions.

## 3. Backend hosting & infrastructure

**Region & provider (ADR-015, CR-03).** The design is **provider-neutral**: containers + managed PostgreSQL + KMS + object storage/CDN + a secrets manager. The recommended option, which needs product-owner and legal approval, is **a primary region in the EU (e.g. Frankfurt)**:
- **Why:** mature managed services, low latency to Egypt (≈ 60–80 ms), and an EU-level protection standard that suits the PDPL cross-border licence.
- **Gulf regions are not recommended for now:** two AWS Gulf regions have been offline since 2026 attacks.
- **The Egypt-hosted alternative** removes the cross-border permit but narrows provider choice. It stays open if the PDPC licence or legal advice requires local hosting.

**Topology:**
- API service: 2+ stateless replicas (0.5 vCPU / 512 MB each), autoscaling to 6.
- Worker service: 1 replica (singleton leases via PostgreSQL advisory locks).
- Managed PostgreSQL 17: 2 vCPU, zone-redundant HA, PITR 14 days, private networking only.
- KMS: ES256 signing keys, HMAC pepper (`install_hash`), a separate audit HMAC key (`K_audit`, support-lookup e-mails), a separate seat-key HMAC key (`K_seat`, D-55 `device_key_hash`), envelope keys.
- Object storage + CDN: catalog snapshots, the signed `.shortcut` file and store-review media.
- Managed TLS certificates; WAF/rate limiting at the edge.
- Google Cloud project for the Play Developer API service account and the Pub/Sub topic + push subscription to `/v1/notifications/google` (settings: "RTDN push" and "Pub/Sub and Play Console setup" below, T-133).
- App Store Connect: production and sandbox notification URLs.

**KMS and key-ring configuration (T-123).** The API reads its key ring from configuration that the IaC (T-140) writes next to the KMS keys; there is no `signing_keys` table, so a database write can never change the signer.
- `Kms:Provider`: `Local` is allowed only in `Development`/`Testing` (throwaway keys from `backend/tools/dev-keys.sh`, read from `Kms:Local:KeyDirectory`). `File` (T-200, D-76, ADR-023) is the hardened key-file provider for Staging and Production on a self-hosted Linux server (see "File KMS on a self-hosted server" below); `OpenBao` (T-201) keeps every key inside a self-hosted OpenBao Transit engine (see "OpenBao Transit KMS" below) and must be in use before Gold is sold to real users. Any other value refuses to start.
- `Signing:Keys:<n>:{Kid, Purpose (Sync|Entitlement), Status (Next|Active|Retired), KeyRef, PublicJwk:{Kty, Crv, X, Y}}`: exactly one `Active` key per purpose; kids match `^[se][0-9]{4}[a-z]$` (`s` = Sync: response headers and catalog `.sig`; `e` = Entitlement: JWS tokens); each key has its own KMS key. At startup every JWK must equal the KMS public key and each active key must pass a sign-then-verify probe, or the process exits non-zero and readiness never goes green.
- `Kms:HmacKeys:{Seat, Audit, InstallHashPepper}`: key references of the three HMAC keys (`IKeyedHasher`). On Azure only Managed HSM offers HMAC. Each reference names an **immutable key version** (GCP `CryptoKeyVersion`, Azure versioned key URI, AWS key ARN; HMAC KMS keys there have no automatic rotation); provider auto-rotation stays off and the keys carry deletion protection / `prevent_destroy`, because a silently changed HMAC key orphans every stored keyed hash.
- `Kms:HmacKeys:SeatCheck` (T-182): 64 lower-case hex of `HMAC-SHA256(K_seat, "zaghlol-kseat-check-v1")`, computed by IaC once when `K_seat` is created (`backend/tools/dev-keys.sh` writes it for the Local provider). The API recomputes it at startup (constant-time compare); outside Development/Testing a missing value, a mismatch or an unreachable KMS refuses the start; in Development/Testing it is checked when set, and a malformed or mismatching value refuses the start there too. Not a secret (a MAC of a public string).
- **`K_seat` rotation (T-182 design note §6; the emergency procedure is *provisional, PO to confirm*: T-182 Q1):** none on a schedule; the seat hashes can't be recomputed because raw seat keys are never stored. **Emergency rotation** (suspected `K_seat` compromise): create a new key version and `SeatCheck`; in one `migrator` transaction that disables the SEC F9 `installs` triggers for its duration, set `installs.seat_key_hash = NULL, seat_key_trusted = false`, `purchase_seats.device_key_hash = NULL, device_key_trusted = false` and `seat_claimants.device_key_hash = NULL`; deploy the new reference and check together. Effect: installs re-register on their next valid proof; same-iPhone recognition of existing seats is lost once and trust returns with the next attested restore; record it in the audit log and the incident report.
- `Kms:Envelope:KeyRef` (new envelopes) and `Kms:Envelope:PreviousKeyRefs:<n>` (older key-encryption keys that may still decrypt). Envelope format v1: `0x01 ‖ u8 len(keyRef) ‖ keyRef ‖ u16be len(wrappedDek) ‖ wrappedDek ‖ nonce(12) ‖ ciphertext ‖ tag(16)`, AES-256-GCM with a fresh data key per record and associated data `"zaghlol-env-v1" ‖ 0x00 ‖ context`.
- KMS calls time out after 2 s with one retry; a signing outage answers `503 UPSTREAM_UNAVAILABLE` with `Retry-After: 5`.
- Managed PostgreSQL: set `log_error_verbosity = terse` so a CHECK failure's DETAIL (row values) never reaches server logs, and never set `Include Error Detail` on a connection string (the API and migrator refuse it; FU-025).

**File KMS on a self-hosted server (T-200, D-76; design note `design-notes/T-200.md`, ADR-023).** Until T-201 moves the keys into OpenBao, Staging and Production read their keys from files with `Kms:Provider = File`. Known weakness: a code-execution bug in the API or worker (or root on the server) can copy the keys, and copied signing keys forge entitlements until the kid is rotated and an app release drops it. T-201 must land before Gold is sold to real users.

*Settings* (all public values; set them as environment variables, e.g. an env file next to the compose file, never in the repository):
- `Kms:Provider=File`, `Kms:File:KeyDirectory=<absolute, canonical path inside the container>` (e.g. `/run/zaghlol-kms`, the bind-mount target below; not under `/run/secrets`).
- Key references `file:<name>`: `Signing:Keys:<n>:KeyRef=file:<kid>` (`<kid>.pem`, a P-256 private key in PEM), `Kms:HmacKeys:Seat|Audit|InstallHashPepper=file:<name>` and `Kms:Envelope:KeyRef=file:<name>` (`<name>.key`, base64 of 32 random bytes with one optional trailing newline, nothing else).
- `Kms:File:Fingerprints:<name>=<64 hex>` for **every** configured key (the key tool prints them). A replaced, recreated or swapped file refuses the start. In environment variables a `-` in the name may be written `_` (`Kms__File__Fingerprints__install_pepper`), which is how the tool prints it.
- `Kms:File:OtherEnvironmentFingerprints:<n>`: the other environment's fingerprints (production lists staging's; staging lists production's once it exists). A key listed there refuses the start. Outside Development/Testing either this list or `Kms:File:NoOtherEnvironment=true` (only while no other environment exists) is required.
- `Kms:HmacKeys:SeatCheck`: printed by the key tool for the `seat` key.

*The process refuses to start* (constant message, no path, key name or key value in the log) when: the OS is not Linux; the directory setting is missing, relative, not canonical or passes through a symbolic link; the directory has any group/other permission or is owned by neither the process user nor root; a parent directory is owned by another user or is group/other-writable without the sticky bit; any entry in the directory is a symlink, a subdirectory, has any group/other or setuid/setgid/sticky bit, or is owned by another user; a configured key file is missing, over 8 KiB or not the right format; the directory is inside a source tree (`.git` or `Zaghlol.sln` above it), overlaps the content root or the application folder, or holds `kms.env` (written by `dev-keys.sh`); a key is one committed to the repository (test vectors, the catalog dev seed key) or a degenerate 32-byte key; a fingerprint pin is missing or wrong; a key belongs to the other environment; one key reference or one set of key bytes serves two roles (two HMAC keys, or an HMAC key and the envelope key); a signing key has a private scalar below 2^64 or explicit curve parameters; outside Development/Testing, a kid uses year `0000`, or the process can't be marked non-dumpable (`prctl(PR_SET_DUMPABLE, 0)`, done before the first key is read). Then the T-123 ring check and the T-182 `SeatCheck` run as before.

*Creating the keys* (once per environment, on the server, inside the release image, no network; the tool refuses to run in or write into a source tree, refuses an `--out` whose path passes through a symbolic link, and refuses an existing `--out`, a dangling link included):
```
sudo install -d -m 0700 -o 1654 -g 1654 /etc/zaghlol/kms-production
docker run --rm --network none --user 1654:1654 -v /etc/zaghlol/kms-production:/out \
  --entrypoint dotnet zaghlol:<tag> /app/worker/Zaghlol.Workers.dll --generate-keys --environment Production \
  --out /out/keys --kid s2026a --kid e2026a --secret seat --secret audit --secret install-pepper --secret envelope
```
It writes `/etc/zaghlol/kms-production/keys/` (mode 0500) with 0400 files owned by uid 1654 (the image's non-root user) and prints the ring entries (status `Next`; set `Active` for the first key of each purpose), the fingerprints and `SeatCheck`. Nothing secret is printed. The output is a valid env file and also safe to `source` in a POSIX shell (names use `_` only).

*Mounting:* bind-mount the whole key directory read-only, e.g. `volumes: ["/etc/zaghlol/kms-production/keys:/run/zaghlol-kms:ro"]` on the `api` and `worker` services, with `Kms:File:KeyDirectory=/run/zaghlol-kms`. Keep `/etc/zaghlol` and `/etc/zaghlol/kms-production` owned by root or 1654 and not group/other-writable.
- Why the files are owned by uid 1654 and not "root, 0400": the container runs as uid 1654 (the image's non-root user), and a root-owned 0400 file is unreadable to it. A root-owned file is accepted by the checks only for a process that runs as root, which the image doesn't.
- Docker secrets (`secrets:` in compose or swarm) are not used for these keys: Docker puts each secret as a file in `/run/secrets`, a directory it creates itself (root, 0755), which the directory check refuses, and swarm's default file mode is 0444. The directory bind mount keeps the 0500/0400 modes from the host.
- Keep the content root (`/app`) and the image free of keys; the API refuses a key directory under `/app`.

*Memory, dumps and swap* (the keys live in the API and worker memory for the whole process lifetime):
- In Staging/Production the File provider marks the process non-dumpable before reading a key: no core file, and no `ptrace` or `/proc/<pid>/mem` read by other processes of the same uid. If the call fails, the process refuses to start.
- Also set `ulimits: { core: 0 }` on the `api` and `worker` services, so a crash never writes a core file through the host's `core_pattern` (systemd-coredump or apport would otherwise store it under `/var/lib/systemd/coredump` or `/var/crash`, where routine backups pick it up).
- Never enable .NET crash dumps in Staging/Production: `DOTNET_DbgEnableMiniDump` unset or `0`, no `createdump`, no `dotnet-dump` against these processes.
- Run the server without swap, or with encrypted swap (e.g. `cryptsetup` with a random key per boot), so key pages never reach a disk in clear.
- Use a local ext4/xfs bind mount and no Docker user-namespace remap or rootless Docker: under a remap the host's uid 1654 appears as another uid inside the container and the owner check refuses the start; file systems that fake modes (CIFS `noperm`, vfat) would pass the mode check without enforcing it.

*Backup:* right after creating the keys, copy the key directory to two offline encrypted media (for example an `age`- or GPG-encrypted archive on two USB drives kept in different places). Never into the repository, a cloud drive, chat, or the server's routine backup set. Record only the fingerprints in the runbook. Losing `seat`, `audit` or `install-pepper` orphans every stored keyed hash; losing `envelope` makes stored Apple refresh tokens unreadable.

*Rotation:*
- Signing keys (yearly or on suspicion): run the tool with `--kid s2027a` (and/or `e2027a`) into a new folder, as for the first set (for example `/etc/zaghlol/kms-rotate`; it writes `<folder>/keys/` at 0500 with 0400 files owned by 1654). The live key directory `/etc/zaghlol/kms-production/keys` is 0500 too, so open it only for the move: `chmod u+w /etc/zaghlol/kms-production/keys && mv /etc/zaghlol/kms-rotate/keys/s2027a.pem /etc/zaghlol/kms-production/keys/ && chmod 0500 /etc/zaghlol/kms-production/keys` (the file keeps mode 0400 and owner 1654; check with `ls -l`, because the next start refuses a wrong mode or owner). Back the new key up offline like the first set (see Backup), then remove the tool's folder (`chmod -R u+w /etc/zaghlol/kms-rotate && rm -r /etc/zaghlol/kms-rotate`), so no second copy stays on the server. Add the ring entry with `Status=Next` and its fingerprint, restart. Ship an app release that pins both kids. Once that release is the minimum supported version, set the new kid `Active` and the old one `Retired`; drop the retired kid in a later release.
- Envelope key: `--secret envelope-2027`, set it as `Kms:Envelope:KeyRef` with its fingerprint and move the old reference to `Kms:Envelope:PreviousKeyRefs:<n>` until no stored row uses it.
- HMAC keys: no scheduled rotation (stored hashes can't be recomputed); `K_seat` has the emergency procedure above.
- Each restart re-runs every check; a wrong file or pin stops the start rather than serving with the wrong key.

**OpenBao Transit KMS (T-201, D-76 step 2; design note `design-notes/T-201.md`, ADR-023).** `Kms:Provider = OpenBao`: the signing, HMAC and envelope keys live in an OpenBao (open-source Vault fork) Transit engine on the same server and never leave it. The API asks Transit to sign a SHA-256 digest (`ecdsa-p256`, JWS marshaling = `r‖s`), to MAC (`hmac` keys) and to make or open envelope data keys (`datakey/plaintext`, `decrypt`). Signing and HMAC calls always name **key version 1**, so a `rotate` in OpenBao can't change what signs or which key hashes. Every call runs under the existing 2 s timeout with one retry; an unreachable, sealed or refusing OpenBao answers `503 UPSTREAM_UNAVAILABLE` with `Retry-After: 5`, and a sealed or unreachable OpenBao at start refuses the start.

*What it protects against, and what not.* A code-execution bug in the API or worker can use the keys while it lasts (sign, MAC, unwrap) but can't copy them; closing the hole and destroying its `secret_id` ends it with no app release. Root on the server still gets every key (it can read the unseal key and OpenBao's data), as with T-200.

*Settings* (public values; the env file next to the compose file):
- `Kms:Provider=OpenBao`, `Kms:OpenBao:Address=https://openbao:8200` (https with no user name, path, query or fragment; `http` only in Development/Testing), `Kms:OpenBao:Mount` (default `transit`), `Kms:OpenBao:CredentialDirectory=/run/zaghlol-openbao`.
- Key references `openbao:<transit key name>`: `Signing:Keys:<n>:KeyRef=openbao:<kid>`, `Kms:HmacKeys:Seat|Audit|InstallHashPepper=openbao:seat|audit|install-pepper`, `Kms:Envelope:KeyRef=openbao:<envelope key>`. During the migration `Kms:Envelope:PreviousKeyRefs:<n>=file:<name>` (old envelopes, opened through the imported key `file-<name>`). `file:` is refused anywhere else.
- `Kms:OpenBao:Fingerprints:<transit name>` for **every** key in use (printed by the key tool; `-` may be written `_`). For the imported `hmac` keys the value equals the T-200 `Kms:File:Fingerprints:<name>` (same key). `Kms:OpenBao:OtherEnvironmentFingerprints:<n>` or `Kms:OpenBao:NoOtherEnvironment=true`, as for File.
- `Kms:HmacKeys:SeatCheck`: unchanged from T-200 (the imported `K_seat` is the same key; the start re-proves it).
- The **worker** sets `Kms:Scope=Envelope` and uses its own credential folder: its OpenBao policy allows envelope keys only, and with this scope it checks and uses only those. The API keeps the default `Full`.

*The process refuses to start* (constant message, no address, path, credential or key in the log) when: outside Development/Testing the OS is not Linux, the address is not https, a kid uses year `0000`, the process can't be made non-dumpable, or neither the other-environment list nor `NoOtherEnvironment=true` is set; the credential folder fails any of the T-200 key-folder checks (canonical path, 0700/0500 owned by the app user or root, files 0400/0600, safe parents, no symlink or subfolder, not in a source tree or the app folder, no `kms.env`) or lacks `role-id`, `secret-id` (1–256 printable characters, no spaces) or `ca.pem`; a key reference has the wrong form for its role or one Transit key serves two roles; OpenBao is unreachable, sealed, presents a certificate not issued by `ca.pem` (the only trusted CA; system roots are ignored) or refuses the login or a key read; a key has the wrong type (`ecdsa-p256`, `hmac` of 32 bytes, `aes256-gcm96`), is exportable, allows plaintext backup or deletion, or is soft-deleted; a key is a committed test key, belongs to the other environment, has a missing or wrong pin, or shares its fingerprint with another key. Then the T-123 ring check and `SeatCheck` run as before.

*Server set-up (once per environment; files in `backend/deploy/openbao/`):*
1. Host folders as listed in `docker-compose.openbao.yml` (OpenBao runs as uid 1655, the API/worker as 1654). TLS: a private CA (key kept offline) issues the server certificate with **exactly these names** (C3: other containers use `https://openbao:8200`; the healthcheck and operator commands inside the container use `https://127.0.0.1:8200`):
   ```
   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 3650 -subj "/CN=zaghlol-openbao-ca" \
     -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -keyout ca-key.pem -out ca.pem
   openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=openbao" -keyout server-key.pem -out server.csr
   printf 'subjectAltName=DNS:openbao,DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\nbasicConstraints=critical,CA:FALSE\n' > ext.cnf
   openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -days 825 -extfile ext.cnf -out server.pem
   ```
   Put `server.pem`, `server-key.pem` and `ca.pem` in `/etc/zaghlol/openbao/tls` (owner 1655, 0400; folder 0500) and move `ca-key.pem` offline. Unseal key (64 hex characters, no newline; a raw binary key can lose a white-space byte to trimming): `sudo sh -c 'umask 077; openssl rand -hex 32 | tr -d "\n" > /etc/zaghlol/openbao/unseal/unseal.key' && sudo chown 1655:1655 /etc/zaghlol/openbao/unseal/unseal.key && sudo chmod 0400 /etc/zaghlol/openbao/unseal/unseal.key`; copy it at once to the two offline encrypted media (as the T-200 keys). It is mounted into the OpenBao container only, and the server's routine backup set must exclude `/etc/zaghlol/openbao/unseal`.
2. `docker compose -f <stack>.yml -f deploy/openbao/docker-compose.openbao.yml up -d openbao`, then `docker compose exec openbao bao operator init -address=https://127.0.0.1:8200 -ca-cert=/openbao/tls/ca.pem -recovery-shares=3 -recovery-threshold=2`. With the static seal OpenBao unseals itself; the output holds three recovery shares (give one each to three named people, offline) and a root token.
3. Run `setup.sh` once in a **one-off** container of the same image on the `kms` network, with a writable output folder (C4; the `openbao` service itself has no set-up mount and a read-only root):
   ```
   sudo install -d -m 0700 -o 1655 -g 1655 /etc/zaghlol/openbao-setup-out
   read -rs BAO_TOKEN && export BAO_TOKEN   # the root token, not echoed
   docker run --rm --network zaghlol-backend_kms --user 1655:1655 --read-only --tmpfs /tmp -e HOME=/tmp \
     -e BAO_ADDR=https://openbao:8200 -e BAO_CACERT=/tls/ca.pem -e BAO_TOKEN \
     -e ZAGHLOL_KIDS="s2027a e2027a" -e ZAGHLOL_ENVELOPE_KEYS=envelope-2027 -e ZAGHLOL_LEGACY_ENVELOPE_KEYS=envelope \
     -e ZAGHLOL_BOUND_CIDRS=172.30.53.0/24 \
     -v /etc/zaghlol/openbao/tls/ca.pem:/tls/ca.pem:ro -v "$PWD/deploy/openbao:/setup:ro" -v /etc/zaghlol/openbao-setup-out:/setup-out \
     --entrypoint sh ghcr.io/openbao/openbao:2.7.2@<digest from docker-compose.openbao.yml> /setup/setup.sh apply /setup-out
   ```
   It enables the Transit mount, creates the signing and new envelope keys (non-exportable, no plaintext backup, no deletion), writes the `zaghlol-api`, `zaghlol-worker` and `zaghlol-keytool` policies (`setup.sh policy api` prints one), creates the two AppRoles (1 h tokens, `secret_id` and tokens bound to `ZAGHLOL_BOUND_CIDRS`, which is **required**: S2), writes `role-id`/`secret-id` per role and a 15-minute key-tool token into the output folder (never printed), and fails if no audit device is enabled (declared in `openbao.hcl`). Re-running changes no key and keeps existing `secret-id` files. The audit log blocks every request when it can't be written: watch the disk of `/var/lib/zaghlol/openbao/audit` and rotate `audit.log` with `logrotate` + `SIGHUP` to the OpenBao process (`docker compose kill -s HUP openbao`).
4. Credential folders: copy `/etc/zaghlol/openbao-setup-out/api/role-id`, `.../api/secret-id` and `ca.pem` into `/etc/zaghlol/openbao-api` (and the worker's into `/etc/zaghlol/openbao-worker`), owner 1654, files 0400, folder 0500; mount each read-only at `/run/zaghlol-openbao` of its service (the compose file does).
5. Migration (below), then revoke the key-tool token and the root token (`bao token revoke -self`); generate a new root from the recovery shares only when needed (`bao operator generate-root`).

*Migration from the File provider (T-200), once per environment:*
- Copy `/etc/zaghlol/openbao-setup-out/keytool-token` and `ca.pem` into `/etc/zaghlol/openbao-keytool` (owner 1654, files 0400, folder 0500; the tool refuses files other users can read). Then run the key tool inside the release image, as uid 1654, on the `kms` network, with the T-200 key folder mounted read-only: `docker run --rm --network zaghlol-backend_kms --user 1654:1654 -v /etc/zaghlol/kms-production/keys:/run/zaghlol-kms:ro -v /etc/zaghlol/openbao-keytool:/run/keytool:ro --entrypoint dotnet zaghlol:<tag> /app/worker/Zaghlol.Workers.dll --openbao-keys --environment Production --address https://openbao:8200 --ca-file /run/keytool/ca.pem --token-file /run/keytool/keytool-token --file-keys /run/zaghlol-kms --import-hmac seat --import-hmac audit --import-hmac install-pepper --import-envelope envelope --kid s2027a --kid e2027a --envelope envelope-2027`. It imports the three HMAC keys and the envelope KEK by BYOK (wrapped with OpenBao's RSA-4096 wrapping key; never in clear on the wire or in the audit log), verifies each without reading it back (an HMAC key's Transit pin must equal its T-200 pin; the legacy KEK must open a File-format wrap the tool made), and prints only pins, `Kms__Envelope__PreviousKeyRefs__0=file:envelope` and the new kids' ring entries (`Status=Next`). Re-running verifies and does not import again; a different key under a taken name stops it.
- If `Kms:Envelope:PreviousKeyRefs:0=file:envelope` is forgotten, old envelopes are **not** lost: a blob naming a key reference that isn't configured is "unavailable" (`503`, metric `zaghlol.kms.unavailable{operation="data_key"}`), and the worker keeps pending Apple revocations and retries them once the setting is fixed (review S1; applies to every provider).
- Stored `install_hash`, seat hashes, audit hashes and log pseudonyms stay valid (same HMAC keys); old envelopes (Apple refresh tokens, idempotency bodies) open through `file-envelope`, new ones use `envelope-2027`. No database row is rewritten.
- Signing keys are **rotated in, not imported**: ship an app release that pins the T-200 kids and the new `s2027a`/`e2027a`; once it is the minimum supported version, switch `Kms:Provider` to `OpenBao` with the new kids `Active` and the old ones `Retired`. The Retired T-200 entries keep `KeyRef=file:<kid>` and their `PublicJwk`; under OpenBao they are **verify-only**: never used to sign, not looked up in OpenBao, still published in the JWKS, and account tokens they signed keep validating. Pin each one as before: `Kms:OpenBao:Fingerprints:<kid>` = the T-200 `Kms:File:Fingerprints:<kid>` (SHA-256 of the public key; a wrong or missing pin refuses the start). A `file:` signing reference that is `Active` or `Next` refuses the start. This is the switch-over moment. If no app release with the old kids is in users' hands yet, the new kids can be `Active` from the first OpenBao start.
- After the switch: remove the File key mount from the services, keep the T-200 offline backup until the legacy key is gone, and destroy the `.pem` files of retired kids. An envelope's key reference is stored in clear at bytes 3.. of the blob (format v1), so the rows still on the legacy key are counted by `SELECT (SELECT count(*) FROM zaghlol.accounts WHERE substring(apple_refresh_token_enc FROM 3 FOR 13) = 'file:envelope'::bytea) + (SELECT count(*) FROM zaghlol.idempotency_records WHERE substring(response_body_enc FROM 3 FOR 13) = 'file:envelope'::bytea) + (SELECT count(*) FROM zaghlol.pending_apple_revocations WHERE substring(sealed_blob FROM 3 FOR 13) = 'file:envelope'::bytea);` (`file:envelope` is 13 bytes; adjust for another name). Idempotency rows and pending revocations age out under their retention rules (backend-schema.md §4); Apple refresh tokens stay as long as their account keeps them. Only at 0: drop `PreviousKeyRefs`, then delete `file-envelope` in OpenBao (set `deletion_allowed` first, as an operator).

*Rotation:* signing kids as before (new `ecdsa-p256` key per kid via `ZAGHLOL_KIDS` and `setup.sh apply`, pin and ring entry from the key tool's `--kid`, app release first). Envelope: a new Transit key (`envelope-2028`) as `Kms:Envelope:KeyRef`, the old one in `PreviousKeyRefs` until its rows are gone (or `bao write transit/keys/<name>/rotate` as an operator: new data keys use the new version, old wraps keep opening; the API's policy can't rotate). HMAC keys: never (the key version is pinned to 1). AppRole `secret_id`: yearly or on suspicion: `bao write -f auth/approle/role/zaghlol-api/secret-id`, replace the file **atomically** (`install -m 0400 -o 1654 -g 1654 new-secret-id /etc/zaghlol/openbao-api/.secret-id.new && mv /etc/zaghlol/openbao-api/.secret-id.new /etc/zaghlol/openbao-api/secret-id`; the folder must be briefly writable by root only), restart the service, then destroy the old one (`secret-id-accessor/destroy`). A login that can't read the credentials at run time answers 503 and is retried; at start it refuses the start. Unseal key: write a new key file, set it as `current_key` with a new `current_key_id`, move the old one to `previous_key`/`previous_key_id`, restart OpenBao.

*Incident (suspected code execution in the API or worker):* fix and redeploy; destroy the role's `secret_id`s and revoke its tokens (`bao lease revoke -force -prefix auth/approle/login`); issue a new `secret_id`. Review the audit log (`/var/lib/zaghlol/openbao/audit/audit.log`) for signatures made during the window. The keys did not leave OpenBao, so no app release or rotation is needed for that reason alone.

*Backup and restore:* `bao operator raft snapshot save /openbao/data/snap-<date>` daily into the server's normal backup set (it is encrypted under the seal key and useless without it), plus the unseal key's two offline copies and the recovery shares. Restore: same `openbao.hcl` and unseal key, `bao operator raft snapshot restore -force <file>`, restart; the API's pins prove the same keys are back. Losing every copy of the unseal key and the recovery shares loses every key.

*Hardening:* the `openbao` service runs read-only, as uid 1655, with all capabilities dropped, `no-new-privileges`, `core: 0`, on an internal network with no published port; `disable_mlock = true` (raft), so run the host without swap or with encrypted swap (T-200 note). Never enable `unsafe_allow_api_audit_creation` outside CI, never set keys `exportable` or `allow_plaintext_backup` (both are irreversible), and never give the API or worker tokens any other policy.

*CI:* the `openbao-live` job (`backend/tools/openbao-live.sh`) runs the pinned OpenBao image with this `openbao.hcl` (raft, static seal, TLS, audit), `setup.sh`, both key tools and the live tests before and after a restart, sealed and stopped.

**Forwarded headers and the client address (T-124).** The per-network rate limits (`RateLimits:*`) group clients by the /24 (IPv4) or /56 (IPv6) of the address that ASP.NET Core `ForwardedHeaders` resolves. `X-Forwarded-For` is trusted only from listed proxies; if none is listed behind a load balancer, every client looks like the load balancer and the whole service shares one bucket, so one client could block registration for everyone.
- `ForwardedHeaders:KnownProxies:<n>` (IP addresses) and/or `ForwardedHeaders:KnownNetworks:<n>` (CIDR, e.g. `10.0.0.0/16`): the addresses of the hop directly in front of the API.
- `ForwardedHeaders:NoProxy=true`: set this instead only when clients connect to the API directly (no load balancer, CDN or WAF in front).
- Outside `Development`/`Testing` the API **refuses to start** unless at least one proxy entry is listed or `NoProxy=true` is set (`ForwardedHeadersConfigurationException`).
- `ForwardLimit` is 1: the API takes the right-most `X-Forwarded-For` entry. The list must match the real hop count. With CDN → load balancer → API, list the load balancer and make it append the client address the CDN supplied (or raise the limit and list both hops); otherwise every client again shares the CDN's address.

**Account deletion and Apple revoke (T-135).** `DELETE /v1/accounts/me` always deletes the account; when Apple's token revoke fails, the API stores only the sealed refresh token in `pending_apple_revocations` and the worker (`AppleRevocationRetryService`, every 15 min with back-off, rows dropped after 30 days) retries it. Both the API and the **worker** therefore need the `Kms:*` settings (to unseal) and `Accounts:Apple:*` (`ServicesId`, `BundleId`, `TeamId`, `KeyId`, `PrivateKey` from the secrets manager); the worker refuses to start in Production without them.

**Price worker (T-127).** `Prices:Providers` is a comma-separated list of provider names in priority order (`fake`, `goldapi`, `metalpriceapi`; later `local_gold`, `fx`, `spot_gold`; see `gold-price-providers.md`). It is empty by default, so the worker fetches nothing and the sync `prices.stale` turns true after 24 h. `fake` is for development and staging only; the worker refuses to start with it in Production. `local_gold`, `fx` and `spot_gold` have no adapter yet (BLK-03, D-41): naming one stops startup. `goldapi` and `metalpriceapi` need `Prices__GoldApi__ApiKey` / `Prices__MetalpriceApi__ApiKey` from the secrets manager (never a file; a missing key stops startup); optional `Prices:Bounds:*` sanity bounds. `Prices:IntervalMinutes` (default 60, minimum 1) sets the fetch period. The worker needs the `Worker` connection string; the API needs `App` and `Admin` (already required).

**Contribution aggregation (T-129).** The worker runs `ContributionAggregatorService` at start and every `Contributions:IntervalMinutes` (default 60, at least 1; not a secret). Each run, in one transaction on the worker login, deletes raw `merchant_contributions` rows older than 180 days, rolls the rest up into `contribution_aggregates` (`ready_for_review` at 5 distinct installs, A-48), and deletes the raw rows of promoted and rejected aggregates. It needs no new secret, grant or migration. Metric `zaghlol.contribution.events{event=ready|promoted|rejected|purged_decided|purged_expired}` (counts only); a failed run is logged by exception type only. Operators need the `catalog_editor` role for the queue and the two decisions.

**Retention purger (T-139).** The worker deletes data past its retention age (backend-schema.md section 4) once at start and then every `Retention:IntervalHours` (default 24, minimum 1); `Retention:BatchSize` (default 5000, clamped to 100..50000) bounds each delete statement. It needs only the `Worker` connection string and no new grant or secret. The metrics `zaghlol.retention.purged` and `zaghlol.retention.failed` carry a fixed `rule` tag; logs carry only the rule name and a row count. `audit_log` deletes are also limited by the database's row-level security (1 year for support actions, 3 years for the rest), so a clock error in the worker cannot erase recent evidence.

**Daily sync (T-128).** `Sync:ThrottleWindow` (a `TimeSpan`, default `24:00:00`) is the server-side window between two effective syncs of one install; `Sync:MaxDeltaOps` (default 2000) is the largest catalog delta sent inline, above which the answer is `mode: full`. Both must be positive or the API refuses to start. Neither is a secret. The contribution `install_hash` uses the existing `Kms:HmacKeys:InstallHashPepper` key (HMAC of `"zaghlol-install-hash-v1" ‖ 0x00 ‖ installId`); a KMS outage drops that call's intake (the app resends) without failing the sync. The migration `AddInstallLastSyncAt` adds `installs.last_sync_at` (nullable, no backfill: `NULL` = never synced, so every install's next sync is allowed) and the `zaghlol.count_daily_active` function (EXECUTE for `app_rw` only); the migration `CountDailyActiveServerDay` replaces it with a two-argument form that uses the database's UTC date and accepts only `android` or `ios` (no data change).

**Ops channel for flag changes (T-126).** `OpsChannel:WebhookUrl` is an incoming-webhook URL (Slack, Google Chat or Teams; body `{"text": "..."}`) that receives one message per feature-flag change. The URL is a credential: set it from the secrets manager (environment variable `OpsChannel__WebhookUrl`), never in a file in the repository. It must be an absolute `https` URL or the API refuses to start (the value is not echoed). Unset, nothing is posted. A failed post is logged by exception type only and never fails the change, which is already committed and audited.

**Google Play verify, acknowledge sweeper and RTDN (T-130, T-133).** The API (verify, support order lookup, RTDN ingest) and the worker (`PlayAckSweeperService` every 15 min; the RTDN processor, the daily voided-purchases job and the hourly expiry sweep; each one instance across replicas through a PostgreSQL advisory lock) read `Purchases:Google:*`:
- `PackageName`: the app's Play package (never taken from a request). Production refuses a debug, dev, staging, test or sandbox segment.
- `Products:<productId>:Kind` (`subscription` | `onetime`) and `Products:<productId>:Plan` (`monthly` | `yearly` | `lifetime`): exactly three products, one per plan, monthly and yearly subscriptions and a one-time lifetime product (`zaghlol_gold_monthly`, `zaghlol_gold_yearly`, `zaghlol_gold_lifetime`; PO question 2 confirms they are separate subscription products, not base plans). Production refuses `android.test.*` IDs.
- `CredentialSource`: `ApplicationDefault` (preferred: workload identity federation or the platform identity, no key in the deployment) or `ServiceAccountJson`, with the key JSON in `Purchases:Google:Credential` set from the secrets manager (environment variable `Purchases__Google__Credential`), never a file in the repository. The service account needs only the Play Console permissions for reading orders and managing orders and subscriptions on this app (PO question 1). A 401/403 from Play raises `ZaghlolStoreAuthError`.
- `BaseUrl`: defaults to `https://androidpublisher.googleapis.com`; Production refuses any other value.
- `OrderLookup`: `fallback` (default) or `orders`; set `orders` only after the `orders.get` availability check recorded in T-130 (AC 5).
- `Budget:TokenLimit` / `Budget:TokensPerPeriod` / `Budget:PeriodSeconds` / `Budget:Replicas` / `Budget:WorkerShare` / `Budget:WorkerReplicas` (T-133; defaults 600 / 130 / 60 / 1 / 0.2 / 1): the Play call budget, as Apple's. The first two are the **total over all processes**, sized under the Play Developer API daily quota (200 K/day assumed, T-130 PO question 4, T-133 PO question 6). Every HTTP attempt (retries included) costs one permit. The worker takes `WorkerShare ÷ WorkerReplicas` for acknowledge and notification lanes, with `Notification` refused while ≤ 25 % of its bucket remains (acknowledge reserve); each API process takes `(1 − WorkerShare) ÷ Replicas` for verify, inline acknowledge, support and restore. Run **one worker replica** unless `WorkerReplicas` is raised to match (FU-098 item 4). `voidedpurchases.list` also has its own Play quota (6 000/day, 30 per 30 s per package); the daily job uses at most 10 calls.
- **RTDN push (T-133, API):** `Rtdn:Audience` (the push subscription's audience, `https://api.zaghlol.app/v1/notifications/google`), `Rtdn:PushServiceAccount` (the push auth service-account e-mail) and optional `Rtdn:Subscription` (`projects/<project>/subscriptions/<name>`). Production refuses to start without the first two; Development and Testing answer 401 without them. Google's signing keys are discovered from `https://accounts.google.com/.well-known/openid-configuration` (outbound HTTPS from the API).
- `RateLimits:GoogleNotifications:TokenLimit` / `TokensPerPeriod` / `PeriodSeconds` (API; defaults 1 200 / 1 200 / 60): the `notifications-google` per-/24 bucket, used instead of `RateLimits:PerNetwork` for that route.
- **Pub/Sub and Play Console setup (T-133; owner and names: T-133 PO questions 1–2):** a topic in the Google Cloud project; `roles/pubsub.publisher` on it granted **only** to `google-play-developer-notifications@system.gserviceaccount.com`; a **push** subscription to `https://api.zaghlol.app/v1/notifications/google` with authentication on, a dedicated push service account with no roles of its own (the Pub/Sub service agent `service-<project-number>@gcp-sa-pubsub.iam.gserviceaccount.com` holds `roles/iam.serviceAccountTokenCreator` on it), the audience set explicitly to the endpoint URL, message retention 7 days, retry policy 10–600 s and **no** dead-letter topic (the voided job and expiry sweep fill gaps). Play Console → Monetize → Monetization setup → Real-time developer notifications: the topic name, notifications for subscriptions and all one-time products. Staging uses its own package, topic and subscription. Go-live check: "Send test notification" → `zaghlol.rtdn.ingest{kind="test",outcome="stored"}`.
- Missing or invalid values stop the API and the worker outside Development and Testing; no value is echoed. `Resilience:*` overrides apply only in Development and Testing.
- **Production refuses to start the API** while verify has no entitlement composer (`NullVerifyGrant`, until T-132). The App Store verifier is registered since T-131.

**App Store verify, order lookup and notifications (T-131, T-134).** The API and the worker (notification processor, daily `Get Notification History`, hourly expiry sweep) read `Purchases:Apple:*`; both refuse to start in Production without it:
- `BundleId`: the iOS bundle ID (PO question 2). Production refuses a debug, dev, staging, test or sandbox segment.
- `Products:<productId>:Type` (`auto_renewable` | `non_consumable`) and `Products:<productId>:Plan`: exactly three products, monthly and yearly auto-renewable subscriptions (in **one subscription group**, so an upgrade keeps its `originalTransactionId`) and a non-consumable lifetime product (PO question 3).
- `AllowSandbox` (`true` | `false`): whether sandbox purchases (App Review, TestFlight) are accepted and recorded as `environment = sandbox`. **Required in Production** (no default; PO question 4 proposes `true`); defaults to `true` elsewhere. Watch `zaghlol.purchase.environment{env="sandbox"}` in production.
- `IssuerId`, `KeyId`, `PrivateKey`: an App Store Connect **In-App Purchase** key (Users and Access → Integrations → In-App Purchase; PO question 1). Set them from the secrets manager as `Purchases__Apple__IssuerId`, `Purchases__Apple__KeyId` and `Purchases__Apple__PrivateKey` (the `.p8` PKCS#8 PEM, an EC P-256 key). All three are required outside Development and Testing; **Production refuses a private key that comes from a configuration file** (JSON, XML, INI or user secrets). The key is loaded into memory once and never logged. Rotate it yearly (see "Key rotation"); a 401 from Apple raises `ZaghlolStoreAuthError`.
- **API token** (`AppStoreApiTokenProvider`): ES256 JWT, header `{alg: ES256, kid, typ: JWT}`, payload `{iss: issuerId, iat, exp: iat + 20 min, aud: "appstoreconnect-v1", bid: bundleId}`, cached and re-minted 5 minutes before `exp`. Apple rejects tokens whose `exp` is more than 60 minutes after `iat` (Apple staff quoting the App Store Server API docs, Developer Forums thread 719814, checked 2026-11-11). The `bid` claim and the header follow Apple's App Store Server Library and the design note's 2026-11-11 check; Apple's "Generating JSON Web Tokens for API requests" page could not be fetched from the build environment, so that part is an **assumption to confirm** with the first live call (PO question 6), where a wrong claim shows as a 401.
- `ProductionBaseUrl` / `SandboxBaseUrl`: default to Apple's `https://api.storekit.apple.com` and `https://api.storekit-sandbox.apple.com` (Apple's recommended domains since 2026-05-05). **Every environment except Development and Testing refuses any other value**, the older `*.itunes.apple.com` domains included (FU-077 I-1). A call goes to the base URL of the signed `environment` only; there is no fallback between them.
- `TestRootCertificate`: base64 DER of a test PKI root that replaces the pinned Apple root, **Development and Testing only**; every other environment refuses it. The pinned root (Apple Root CA - G3, SHA-256 `63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179`) is embedded in `Zaghlol.Infrastructure` and its fingerprint is checked at startup in every environment.
- `Budget:TokenLimit` / `Budget:TokensPerPeriod` / `Budget:PeriodSeconds` / `Budget:Replicas` / `Budget:WorkerShare` (defaults 300 / 60 / 60 / 1 / 0.2): the Apple call budget, separate from Play's. The first two are the **total over all processes**. The worker takes `WorkerShare` of it for notification processing and reconciliation (the only lane it may use); each API process takes `(1 − WorkerShare) / Replicas`, so set `Replicas` to the **API** replica count (T-134). Every HTTP attempt (retries included) costs one permit; restore stops first (it may use at most 30 % of an API process's bucket). Verify is also limited to 10 calls an hour per install; that limit is per API process, so with N replicas an install can reach 10 × N an hour (FU-092 nit 6). Apple publishes no fixed limits and answers 429 per endpoint, so size these from the observed `zaghlol.store.call{store="app_store", outcome="rate_limited"}` rate before go-live.
- `Budget:WorkerShare` must be a decimal fraction strictly between 0 and 1 (invariant culture, e.g. `0.2`); anything else stops startup in every environment, naming the key only. The API and the worker each register only their own partition (a process can't hold both).
- `RateLimits:AppleNotifications:TokenLimit` / `TokensPerPeriod` / `PeriodSeconds` (API; defaults 1 200 / 1 200 / 60): the `notifications-apple` per-/24 bucket of `POST /v1/notifications/apple`, used instead of `RateLimits:PerNetwork` for that route. A 429 is retried by Apple.
- **ASSN V2 URLs (T-134):** App Store Connect → App Information → App Store Server Notifications, Version 2. Production Server URL = `https://api.zaghlol.app/v1/notifications/apple`; the Sandbox Server URL points at one backend only (production or staging: T-134 PO question 1). The environment is taken from the signed payload, never from the URL.
- Missing or invalid values stop the API outside Development and Testing; no value is echoed. `Resilience:*` and `Budget:VerifyPerInstallPerHour` overrides apply only in Development and Testing. Production also refuses any App Store client or JWS verifier other than the real ones. Development (docker compose) starts with an empty section: iOS verify then answers `PURCHASE_WRONG_APP`.

**Restore attestation verifiers (T-181; wired into the API by T-185).** `AddZaghlolAttestation` reads, and refuses to start on, the following (no value is echoed):
- `Attestation:AppAttest:TeamId`: the 10-character Apple Team ID; with `Purchases:Apple:BundleId` it forms the App ID whose SHA-256 is the App Attest RP ID hash. Required outside Development and Testing.
- `Attestation:AppAttest:AllowDevelopmentEnvironment` (`true` | `false`, default `false`): accept the `appattestdevelop` AAGUID (development-signed builds). Set it only on **staging**; Production refuses `true`.
- `Attestation:AppAttest:TestRootCertificate`: base64 DER test root, **Development and Testing only**. The pinned root (Apple App Attestation Root CA, SHA-256 `1cb9823ba28ba6ad2d33a006941de2ae4f513ef1d4e831b9f7e0fa7b6242c932`, valid to 2045-03-15) is embedded in `Zaghlol.Infrastructure` and checked at startup in every environment. The fingerprint was taken from two independent published copies because apple.com wasn't reachable from the build environment; confirm it against apple.com/certificateauthority before launch (T-181 PO question 1).
- `Attestation:PlayIntegrity:BaseUrl`: defaults to `https://playintegrity.googleapis.com/`; other values only in Development and Testing. The package is `Purchases:Google:PackageName`. The call uses the same `Purchases:Google` credential with the OAuth scope `https://www.googleapis.com/auth/playintegrity`: the service account must be allowed to call the Play Integrity API for the app (Play Console → App integrity → link the Google Cloud project; enable the Play Integrity API in that project). No new secret. Optional verdicts (`deviceAttributes`, `recentDeviceActivity`, `appAccessRiskVerdict`, `environmentDetails`) stay **off** in Play Console (R2-7).
- Production refuses any attestation verifier other than the real ones (a test fake can never serve users).

**Infrastructure as code:**
- OpenTofu modules per environment under `backend/deploy/`.
- Secrets are referenced, never stored.
- CI deploys with OIDC federation (no static cloud keys).

**Backend pipeline:**
```
PR:   dotnet build -warnaserror · format · unit + integration tests (Testcontainers Postgres) · OpenAPI contract tests
      · SCA + container scan
main: build image (distroless, non-root) → push → deploy staging → EF migration job → smoke tests (sync, verify sandbox)
tag:  promote the same image digest to prod → migration job (expand/contract, backward compatible) → rolling deploy
      → synthetic checks → automatic rollback on failed health
```

**Migrations:** expand → deploy → contract across two releases. Migrations must be compatible with the N-1 API version, because a rolling deploy runs mixed versions. A CHECK added to a table that already holds rows is validated against them: the FU-018 CHECKs on `merchant_contributions` and `bank_requests` (AddPriceFeedColumns) were added while both tables were empty. Since T-128 the sync writes them, so a later migration that tightens one of their CHECKs must first delete or migrate the rows that would fail it (or add the constraint `NOT VALID` and validate after the cleanup).

## 4. Operations

| Topic | Plan |
|---|---|
| Backups / DR | PITR 14 days; daily logical dump to separate storage (30 days). RPO ≤ 5 min, RTO ≤ 4 h. Restore drill each quarter. If the backend is down, **the app keeps working** (NFR-BE-01); only purchases verification, cross-platform Gold and freshness are delayed. |
| Key rotation | ES256 `kid` yearly (next key embedded in the app ≥ 1 release earlier); Play service-account key replaced by workload identity federation where possible; Apple API key yearly |
| Scaling | 500k installs / 100k daily syncs fits the base topology (backend-schema §5). Scaling triggers on CPU > 60% or p95 latency. |
| Cost (indicative, base topology) | Low hundreds of USD/month (API + worker + HA Postgres + CDN + KMS), to be confirmed for the chosen provider and region |
| Incident response | On-call rota (business hours + paging for SLO burn). Breach runbook with PDPC notification within 72 h. |
| Operator tooling (D-37) | v1: `zaghlol-ops` CLI against the admin API (OIDC authorization code + PKCE with a loopback redirect, MFA; the device-code grant is disabled for its client, R3-9). Later: an admin web app reusing the same API. Operator auth settings (T-136): `OperatorAuth:Enabled=true`, `Profile` (`Entra`, `Google` or `Generic`), `Issuer` (https, exact `iss`), `Audiences:0..n` (the `zaghlol-ops` and admin-app client IDs), `AllowedTenants:0..n` (Entra tenant GUIDs) or `AllowedDomains:0..n` (Google Workspace `hd` domains), optional `RoleClaim` and `RoleMap:{claim value}=role` (setup per IdP in `operator-idp-setup.md`), optional `Algorithms` (subset of RS256/ES256), `AcceptedAmr` (default `mfa`), `PhishingResistantMode` (`Advisory` default, `Enforced` with `RequiredAcrs` = the Entra authentication-context ID), `ClockSkewSeconds` 60, `MaxLifetimeSeconds` 3600, `JwksRefreshHours` 24, `OperatorCacheSeconds` 30. Public values only; outside Development/Testing the API refuses to start unless these are complete and the IdP's discovery document and JWKS load at boot. The e-mail pseudonym key `K_audit` is `Kms:HmacKeys:Audit`. Operators are provisioned by `backend/deploy/db/seed-operator.sql` run as `migrator`. |
| Compliance | PDPC licence (+ cross-border permit if abroad), DPO, records of processing, store privacy forms, Play SMS declaration with demo video |

## 5. Launch checklist (architecture items)

- [ ] Play SMS-permission declaration submitted; `prodNoSms` ready.
- [ ] Signed `Zaghlol.shortcut` published; setup checker verified on iOS 17 and iOS 26.
- [ ] ES256 production keys created with the File KMS key tool (T-200) and moved into OpenBao Transit before Gold is sold (T-201, D-76); key directory backed up offline twice; public keys embedded (JWKS from `EcPublicJwk.ToJwks`); key-rotation test passed; `log_error_verbosity = terse` on the managed PostgreSQL.
- [ ] `ForwardedHeaders:KnownProxies`/`KnownNetworks` set to the load balancer in front of the API (or `ForwardedHeaders:NoProxy=true` if there is none), matching the real hop count; the per-network limit checked from two client networks in staging.
- [ ] RTDN + ASSN V2 configured for prod and sandbox; reconciliation jobs green.
- [ ] Price provider contract signed (OQ-02); stale alerts tested.
- [ ] Hosting region approved and PDPL licensing done (CR-03).
- [ ] Self-hosted server: runbook (section 6) done, restore drill passed, backup off-server copy verified, OpenBao move done before Gold.
- [ ] Privacy scan + data-boundary contract tests green on the release candidate.

## 6. Self-hosted server (single Linux host)

ADR-025. The product owner can't use a cloud provider, so the whole backend runs on **one Ubuntu 24.04 server with Docker** that
he controls. Sections 3 to 5 still define every setting; this section says how they are put together on that one host. Files:
`backend/deploy/server/` (compose, Caddyfile, env examples, `harden.sh`, `deploy.sh`, `backup/`, optional `observability/`), the
workflow `.github/workflows/backend-deploy-server.yml` and the checks `.github/workflows/backend-server-kit.yml`. The OpenTofu
files and `backend-deploy.yml` are the cloud alternative and stay untouched.

**What runs.** `postgres:17` (no published port, data in `/var/lib/zaghlol/postgres`, WAL archived to `/var/lib/zaghlol/backup/wal`),
a one-shot `migrate`, `api` (2 replicas; `API_REPLICAS=1` on a small host), `worker` (1), `caddy` (the only published ports: 80, 443/tcp,
443/udp; automatic Let's Encrypt certificate; reverse proxy to the replicas; `/catalog/` serves the snapshot folder read-only;
1 MiB request bodies; 10 s header and 15 s body timeouts; access log with the client network cut to /24 or /56 and no headers),
and optionally an OTel collector, Prometheus, Alertmanager and Grafana. All containers drop every capability, set
`no-new-privileges`, `ulimits.core: 0`, use read-only roots and run as non-root users (api/worker 1654, postgres 999, caddy 65532).
The network `172.30.52.0/24` is fixed, so `ForwardedHeaders__KnownNetworks__0=172.30.52.0/24` is exact (Caddy is the one hop in
front of the API). The api and worker mount `/etc/zaghlol/kms-production/keys` read-only at `/run/zaghlol-kms` (section 3, "File KMS").
`-f ../openbao/docker-compose.openbao.yml` is added on top after the OpenBao move; `compose.sh` does that when the marker file
`/etc/zaghlol/use-openbao` exists (`use-observability` likewise).

**Two env files.** `/etc/zaghlol/production.env` (`production.env.example`: image references, domain, database passwords) is read by
Compose only; `/etc/zaghlol/app.env` (`app.env.example`: every API/worker setting of section 3) is passed to api and worker, which
therefore never see a database password they don't use (connection strings are built per service in the compose file). Both root, 0600.
Database login passwords come from `production.env`: `postgres/init/20-set-passwords.sh` applies them on first initialisation
(after the unchanged `bootstrap-roles.sql`), `backup/set-db-passwords.sh` re-applies them after a change. Never `dev-passwords.sql`.

**Images.** Third-party images are pinned by digest in `production.env` (`pin-images.sh` prints the lines; the example holds real digests resolved 2026-11-21, and an
all-zero placeholder only for the backend image, which the first deploy writes). The backend image is `ghcr.io/amr905/zaghlol-backend@sha256:...`, written
into `BACKEND_IMAGE` by `deploy.sh`, which also keeps the previous one in `BACKEND_IMAGE_PREVIOUS`.

### First install (numbered runbook)

1. **Server.** Ubuntu 24.04 LTS, at least 2 vCPU / 4 GB / 40 GB, a static public IP, root or sudo SSH with your own key.
   Install Docker Engine and the Compose plugin from Docker's apt repository (not rootless, no userns remap: section 3). Reboot.
   Copy the repository's `backend/deploy` folder to `/opt/zaghlol/deploy` (`rsync -a backend/deploy/ root@server:/opt/zaghlol/deploy/`).
2. **DNS.** An `A` (and `AAAA`) record for the API name (for example `api.<your domain>`) pointing at the server. Check with
   `dig +short api.<your domain>`. Ports 80 and 443 must reach the server (Let's Encrypt needs 80).
3. **Harden.** Put the deploy key's public part in `/etc/zaghlol/deploy.pub` (generate the pair on your laptop:
   `ssh-keygen -t ed25519 -f deploy_key -C zaghlol-deploy`; the private half goes to GitHub only). Then, with your own SSH key already
   working, `sudo /opt/zaghlol/deploy/server/harden.sh`. It sets ufw (22, 80, 443), SSH keys only (refused if no key exists), unattended
   security upgrades, swap off, no core dumps, Docker log rotation, the deploy user, the folders under `/etc/zaghlol` and
   `/var/lib/zaghlol` with the owners and modes of section 3, and the backup timer files. Re-run it after any change. Without
   swap a memory spike kills a process instead of paging: size the host with headroom, or use encrypted swap instead.
4. **Keys (File KMS).** As in section 3: `sudo docker pull <image>` of the first release, then the `--generate-keys` command into
   `/etc/zaghlol/kms-production` (`--kid s2026a --kid e2026a --secret seat --secret audit --secret install-pepper --secret envelope`).
   Copy the printed ring entries, fingerprints and `SeatCheck` into `app.env`. Back the key directory up to two offline encrypted media at once.
5. **Env files.** `sudo install -m 0600 -o root -g root /opt/zaghlol/deploy/server/production.env.example /etc/zaghlol/production.env`,
   `...app.env.example /etc/zaghlol/app.env`, `.../backup/backup.env.example /etc/zaghlol/backup.env`; fill every value
   (`openssl rand -hex 24` for passwords; `./pin-images.sh` for digests; the store, Pub/Sub, operator sign-in and price values come from the
   consoles named in section 3). Set `ASPNETCORE_ENVIRONMENT=Production`. Create the off-server backup key
   (`ssh-keygen -t ed25519 -f /etc/zaghlol/backup/id_ed25519 -N ''`), install its public half on the backup host, and write the target's pinned host
   key into `/etc/zaghlol/backup/known_hosts` (`ssh-keyscan -t ed25519 <backup host>`, compare the fingerprint by hand). Run `harden.sh` again to enable the timer.
6. **GitHub.** Create the environment `backend-production` with a required reviewer, the secrets `DEPLOY_SSH_KEY` and `DEPLOY_KNOWN_HOSTS`
   (`ssh-keyscan -t ed25519 <server>`, fingerprint checked by hand), the variables `DEPLOY_HOST`, `DEPLOY_API_DOMAIN` (and optionally
   `DEPLOY_USER`), and the repository variable `BACKEND_SERVER_DEPLOY_ENABLED=true`.
7. **First deploy.** Actions > backend-deploy-server > Run workflow, approve it. It builds the image, pushes it by digest, ships
   `backend/deploy`, and runs `deploy.sh` (pull, start postgres, migrate, start everything, smoke `GET /v1/health` on the server and from
   the runner). On the server, `./compose.sh ps` shows everything healthy; Caddy fetches the certificate on the first request.
   Run the first backup by hand (`sudo systemctl start zaghlol-backup.service`) and check `journalctl -u zaghlol-backup.service`.
8. **Operator, stores, prices.** Seed the first operator (`backend/deploy/db/seed-operator.sql` as `migrator`), set the ASSN V2 and RTDN URLs
   (section 3), run a synthetic sync and a sandbox purchase.
9. **Move the keys into OpenBao before Gold is sold** (T-201, D-76): follow "OpenBao Transit KMS" (section 3) with the folders `harden.sh` already made;
   `touch /etc/zaghlol/use-openbao`, switch the `Kms__*` entries of `app.env` as that section says, `./compose.sh up -d`; then remove the File key mount.
   The OpenBao raft snapshot joins the nightly backup (`bao operator raft snapshot save`), but never `/etc/zaghlol/openbao/unseal` or the key folders.
10. **Restore drill** (`backend/deploy/server/backup/restore-drill.md`) before launch and every quarter.

### Day-to-day

- **Upgrade the backend:** run the workflow again (it migrates first, N-1 compatible, then recreates api and worker). A failed smoke test puts the
  previous digest back automatically; migrations are never reversed (expand/contract, section 3). To redeploy a known digest, give `image_digest`.
- **Upgrade Postgres/Caddy/other images:** `./pin-images.sh`, review the diff, edit `production.env`, `./compose.sh pull && ./compose.sh up -d`. A Postgres major upgrade
  needs a dump/restore (`backup/restore.sh`), not a tag bump.
- **Backups (`backup/`).** `zaghlol-backup.timer` runs nightly at 02:30 UTC: `pg_dump` (custom format), a base backup, a `pg_switch_wal`, retention of 15 days, then an `rsync` over
  ssh with a pinned host key to `OFFSITE_TARGET`. `archive_command` copies each WAL segment to `/var/lib/zaghlol/backup/wal` (at least every 5 minutes), which `backup.sh` mirrors
  off-server too: 14-day point-in-time recovery, RPO of about 5 minutes for a lost disk if the last WAL reached the target (otherwise the previous nightly run). A failed run mails `ALERT_EMAIL` and logs
  to the journal. Backups hold no financial data (it never reaches the server) but do hold install hashes and contributions: keep the target encrypted and private, and keep key material out of it.
  The mirror deletes off-server what local retention drops: give the target its own snapshots or an append-only mode if ransomware on this host is a concern.
- **Restore** (`backup/restore.sh`, drill in `backup/restore-drill.md`): `dump` into a scratch database, `live` to replace the live schema from a dump, `pitr <base> "<UTC time>"` to rebuild the cluster.
  A new server needs runbook steps 1 to 5, the offline key backups, then `restore.sh pitr`.
- **Rotation.** Signing, envelope and OpenBao secret ids: section 3. Database passwords: edit `production.env`, `backup/set-db-passwords.sh`, `./compose.sh up -d --force-recreate api worker`.
  Deploy SSH key: new pair, replace `/etc/zaghlol/deploy.pub`, run `harden.sh`, update the GitHub secret. Off-server backup key: replace on both ends. Apple/Play credentials: edit `app.env`, recreate api and worker.
- **Optional monitoring** (`observability/`): `touch /etc/zaghlol/use-observability`, create `/etc/zaghlol/alertmanager/alertmanager.yml` and `smtp-password` from the example (folder root:65534 0750),
  `./compose.sh up -d`. The collector turns OTLP into Prometheus metrics, Prometheus loads the repository's alert rules (the container and Postgres exporter rules stay silent until such exporters are added), Alertmanager
  e-mails, and Grafana (127.0.0.1:3000, reach it with `ssh -L`) shows the repository dashboards. Without it the apps export nothing and run unchanged. Watch disk space and certificate expiry by hand or with an external uptime check on `https://<api>/v1/health`.
- **Residual risks of one host (ADR-025):** no zone redundancy (a server loss means hours of restore, RTO 4 h assumes the drill works), root on the host reads the File-KMS keys (until OpenBao, and even then the unseal key), Docker's published ports bypass ufw (only Caddy publishes any), and a deploy key is root-equivalent.

## 7. MonsterASP.NET + Aiven

D-80. The API runs as one IIS site on MonsterASP.NET (Windows, shared host) and the database is Aiven for PostgreSQL. The
self-hosted server (section 6) stays the alternative. Hosting profile, embedded workers, deploy workflow and keep-alive: T-206;
Aiven profile: T-207 (their subsections join this section).

### Keys: HostSecrets provider (T-205, ADR-026)

The File KMS refuses Windows and OpenBao needs our own server, so on this host the keys come from **secret settings the host
injects** (`Kms:Provider = HostSecrets`). It is the File KMS key ring (same `file:<name>` key references, kids, `Signing:Keys`
entries, pins and envelope format) read from one environment variable per key instead of one file per key. Read ADR-026 first:
this custody is weaker than section 3 and is accepted only by setting `Kms:AcceptSharedHostCustody=true`.

**Settings.**

| Setting | Where | Value |
|---|---|---|
| `ZAGHLOL_KEYS__<name>` (one per key: `s2026a`, `e2026a`, `seat`, `audit`, `install_pepper`, `envelope`) | GitHub environment secret → `web.config` `<environmentVariable>` at deploy | printed by the key tool; **private** |
| `Kms__Provider=HostSecrets` | public settings | |
| `Kms__AcceptSharedHostCustody=true` | public settings | set by you, after reading ADR-026; refused start without it outside Development/Testing |
| `Signing__Keys__<n>__…`, `Kms__HmacKeys__…`, `Kms__Envelope__…` | public settings | as in section 3 (`file:<name>` references) |
| `Kms__File__Fingerprints__<name>`, `Kms__HmacKeys__SeatCheck` | public settings | printed by the key tool |
| `Kms__File__OtherEnvironmentFingerprints__<n>` or `Kms__File__NoOtherEnvironment=true` | public settings | required outside Development/Testing |

"Public settings" may be committed in `appsettings.<Environment>.json` or set as host settings. A `ZAGHLOL_KEYS` value must
**never** be in any `appsettings*.json` (or any other configuration file): the API refuses to start if one is, even in a file it
doesn't load. Names may use `_` for `-` and any letter case; setting both spellings of one name is refused.

**Create the keys** (on your own machine, Windows or Linux, outside any checkout; the tool writes no file):

```
dotnet Zaghlol.Workers.dll --generate-keys --format host-secrets --environment Production \
  --kid s2026a --kid e2026a --secret seat --secret audit --secret install-pepper --secret envelope
```

It prints, once, the `ZAGHLOL_KEYS__…` lines (private), then the public lines (`Kms__Provider`, ring entries with `Status=Next`,
fingerprints, `SeatCheck`). Then:
1. Create each `ZAGHLOL_KEYS__<NAME>` line as a secret of the GitHub environment (`backend-production`, required reviewer); the
   deploy workflow (T-206) writes them into the site's `web.config` as `<environmentVariable name="ZAGHLOL_KEYS__<name>" value="…" />`.
2. Put the public lines into the production settings, set the first kids to `Active` (rotation rules, section 3), add
   `Kms__AcceptSharedHostCustody=true` and the other-environment fingerprints.
3. Back up the private lines offline, like the File KMS keys (two encrypted media, never the repository, a cloud drive or chat), then
   clear the terminal and its scrollback.
4. Staging gets its own run with `--environment Staging`; list each environment's fingerprints in the other's
   `Kms__File__OtherEnvironmentFingerprints`.

**Already have File KMS keys** (section 3)? Convert them instead of creating new ones, so every stored hash and envelope stays valid:
`--generate-keys --format host-secrets --environment Production --from-dir <key directory>` (run as a user that can read it).
Pins and `SeatCheck` stay the same.

**Check.** The start log says `KMS key ring verified`; a refusal names the guard with a constant message and no key data.
`GET /v1/health` shows no key data either.

**Rotation.** As in section 3, with `--kid`/`--secret` runs of the same tool: add the new secret and its ring entry and pin, deploy,
flip statuses per the rules. Rotate the signing kids at least yearly here, and at once if the host or our host credentials may be compromised.

**Leaving the shared host** (ADR-026 exit path): write each value's `pem`/`key` field (base64url-decode the setting, read the JSON) to
`<name>.pem`/`<name>.key` with the section 3 modes, switch `Kms__Provider` to `File` with the same ring and pins, then follow "OpenBao
Transit KMS" (BYOK import of HMAC and envelope keys). Rotate the signing keys into new kids on the new server; don't carry them over.
