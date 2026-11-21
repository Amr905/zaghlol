# ADR-026: Key custody on a shared Windows host (HostSecrets, D-80)

| | |
|---|---|
| Status | Proposed (built by T-205; PO confirms) |
| Date | 2026-11-21 |
| Deciders | Product owner (MonsterASP.NET + Aiven, D-80), backend-engineer (T-205) |
| References | SRS D-80, D-76; ADR-023 (self-hosted key custody), ADR-025 (self-hosted server, the alternative); T-200, T-201, T-205, T-206, T-207; `deployment.md` section 7 "MonsterASP.NET + Aiven"; task design note `docs/04-tasks/tasks/T-205.md` |

## Context
D-80 puts the API on MonsterASP.NET: one IIS site on a shared Windows host, no shell, no container, no server we control. The
backend still needs its signing keys (entitlements, sync responses), HMAC keys (`K_seat`, `K_audit`, the `install_hash` pepper)
and the envelope key-encryption key.

The two ADR-023 providers don't fit:
- **File KMS (T-200)** refuses to start off Linux: its safety rests on POSIX owner and mode checks and `prctl`, which Windows/IIS
  doesn't have, and we can't inspect or control the host's ACLs.
- **OpenBao (T-201)** needs a server we run (raft storage, unseal key, TLS). There is none in D-80.

What the host gives us: per-site settings it injects into the process as environment variables (`web.config`
`<aspNetCore><environmentVariables>`), deployed by our workflow from GitHub environment secrets.

## Options considered
1. **Host-injected secret settings** (`Kms:Provider = HostSecrets`), behind an explicit custody opt-in. Available now, no extra
   service. The host's staff, a host compromise, the host's backups of the site folder and anyone with the site's control-panel or
   Web Deploy credentials can read the keys.
2. **A small OpenBao/File KMS server elsewhere** (a VPS), reached over TLS from the shared host. Better custody, but it is the
   server D-80 is avoiding, and it adds a network dependency to every signature.
3. **A cloud KMS.** Ruled out by the PO (D-76).
4. **Keys in `appsettings.Production.json`** shipped with the build. Rejected: keys would sit in build artefacts, CI logs and
   anything that copies the publish folder; the provider refuses this case.

## Decision
Option 1, as a **temporary custody level that the operator has to accept explicitly**:

- A new provider `HostSecrets` reads one setting per key, `ZAGHLOL_KEYS__<name>`, holding the unpadded base64url of
  `{"zaghlol":"host-key-v1","name":"<name>","pem"|"key":"<the File KMS .pem or .key text>"}`. It is the **File KMS ring in another
  container**: the same `file:<name>` key references, kids, `Signing:Keys` entries, envelope wrap and fingerprint pins
  (`Kms:File:Fingerprints:<name>`, `Kms:File:OtherEnvironmentFingerprints`, `Kms:File:NoOtherEnvironment`). It works on Windows and Linux.
- Outside Development and Testing it refuses to start unless `Kms:AcceptSharedHostCustody = true`. Staging is included: it runs on
  the same kind of host.
- It keeps every T-200 guard that doesn't need the OS: key-reference rules, one role per symmetric key, committed-key denylist,
  degenerate and tiny keys, named P-256 only, fingerprint pins, other-environment fingerprints, no year-0000 kids, same bytes under
  two names; on Linux also the non-dumpable flag. Refusals are constant messages with no key bytes, names or values.
- New guards: a missing or malformed setting, the same name set twice (`-` and `_` spellings), and **key material in a
  configuration file** (any `ZAGHLOL_KEYS` value served by a file provider such as `appsettings*.json`, or an `appsettings*.json`
  in the content root or app folder that contains `ZAGHLOL_KEYS` or the fixed prefix every value starts with).
- The app never writes a key to disk. The key tool (`Zaghlol.Workers --generate-keys --format host-secrets`) prints the settings
  once to stdout and writes no file; `--from-dir` converts an existing File KMS directory.

## Consequences
- The API can be deployed on MonsterASP.NET with real keys today, and the same ring runs unchanged on the File KMS or, after the
  BYOK import, OpenBao.
- **Accepted residual (weaker than ADR-023).** Whoever can read the site's settings can copy every key: the host's staff, an attacker
  who compromises the host or our control-panel/Web Deploy credentials, and the host's backups of the site folder (`web.config` is
  on the host's disk, written by our deploy, not by the app). A code-execution bug in the API can copy them too, as with the File KMS.
  A copied signing key forges entitlements until the kid is rotated and an app release that drops it is the minimum supported version;
  a copied `K_seat`/`K_audit`/pepper lets the holder test guesses against hashes in a database dump. Windows has no per-process
  "non-dumpable" switch, and IIS/WER crash dumps are a host setting we can't change; the setting strings also stay in the process
  environment block and `IConfiguration` for the life of the process (immutable strings can't be zeroed).
- **Mitigations we keep:** keys never in the repository, build artefacts or CI logs (only in GitHub environment secrets with a required
  reviewer, and in `web.config` on the host); IIS doesn't serve `web.config`; pins in committed settings detect a swapped key; separate
  staging/production keys with each other's fingerprints listed; signing keys rotated yearly and on any suspicion of host compromise.
- **Exit path (required before scale, and immediately if the host or our host credentials are compromised):** move to File KMS or
  OpenBao on a server we control (ADR-023/ADR-025). HMAC and envelope keys move as they are: write each `key`/`pem` field to
  `<name>.key`/`<name>.pem` with the T-200 modes (same ring, same pins), then for OpenBao run the existing `--openbao-keys` BYOK import,
  so stored hashes and envelopes stay valid. Signing keys move by **rotation** into new kids (new keys created on the new server; the
  old kids published as Retired until the app release that drops them), never by copying — a key that lived on the shared host is
  treated as exposed. After a compromise, also rotate `K_seat` by the T-182 emergency procedure.
- The custody flag is a recorded decision, not a default: the key tool doesn't print it, and the deployment section asks the operator
  to set it after reading this ADR.
- ADR-023 stays the target custody; ADR-025 stays the documented alternative hosting.
