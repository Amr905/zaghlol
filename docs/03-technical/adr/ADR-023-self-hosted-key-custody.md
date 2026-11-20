# ADR-023: Self-hosted key custody (D-76)

| | |
|---|---|
| Status | Accepted (PO decision D-76, 2026-11-20); step 1 built by T-200, step 2 built by T-201 (pending review) |
| Date | 2026-11-20 |
| Deciders | Product owner (decision), solution-architect, backend-engineer (T-200) |
| References | SRS D-76; ADR-012, ADR-015; T-123 (KMS abstraction), T-140, T-182; design notes `design-notes/T-200.md`, `design-notes/T-201.md`; `deployment.md` §3 "File KMS on a self-hosted server" and "OpenBao Transit KMS"; `security-model.md` §6 |

## Context
The backend signs entitlements and sync responses (ES256), computes keyed hashes (`K_seat`, `K_audit`, the `install_hash` pepper) and envelope-encrypts Apple refresh tokens and idempotency bodies. T-123 put these behind three ports (`ISigningKeyProvider`, `IHmacProvider`, `IDataKeyProvider`) and assumed a cloud KMS (T-140). The only adapter was `Local` (key files, Development/Testing only), so Staging and Production could not start.

The product owner can't use a cloud provider. The server is one self-hosted Linux machine running the API and worker containers.

## Options considered
1. **Hardened key files on the server** (`Kms:Provider = File`). Cheap and available now. The keys live in the API's memory and on a root-controlled mount; a code-execution bug in the API or worker can copy them.
2. **Self-hosted OpenBao (Vault fork) Transit engine** on the same server. Keys stay inside OpenBao (non-exportable); the API only asks it to sign, MAC or wrap. A code-execution bug can use the keys while it lasts but can't take them away. More moving parts: unseal key custody, OpenBao backups, policies, TLS.
3. **Hardware (YubiHSM / smart-card HSM via PKCS#11).** Strongest local custody, but needs hardware at the hosting site, a PKCS#11 stack in the container and HMAC/wrap support we'd have to verify per device. Not available now.
4. **Wait for a cloud KMS.** Blocks every deploy; the PO has ruled it out.

## Decision
Two steps:
1. **Now: option 1, hardened** (T-200). A separate `File` provider that is allowed in every environment on Linux, loads every configured key once at start and refuses to start unless the key directory and files are private to the app user (no group/other bits, safe parents), outside any source tree and the app's content root, free of `dev-keys.sh` output, not a key committed to the repository, pinned by fingerprint in configuration, and not one of the other environment's keys. A production key tool (`dotnet Zaghlol.Workers.dll --generate-keys`, shipped in the image) creates the keys and prints only public values. `Local` stays Development/Testing only.
2. **Before Gold is sold to real users: option 2** (T-201). HMAC and envelope keys are imported once so stored hashes and envelopes stay valid; signing keys are rotated into new non-exportable kids with an app release pinning both.

T-201 details (design note `design-notes/T-201.md`): OpenBao on the same server with raft storage, the built-in static-key auto-unseal (unseal key root-controlled on the host, mounted into OpenBao only, two offline copies; recovery shares with three people) and a declared file audit device; TLS with a private CA that the API pins; AppRole login per process (`secret_id` from a private file, bound to the stack network; no response wrapping, because restarts have no orchestrator to hand out single-use wraps); least-privilege policies generated per key (the worker gets envelope keys only, `Kms:Scope = Envelope`). The File envelope KEK is imported as a decrypt-only Transit key: Transit's AES-GCM ciphertext layout equals the File wrap, so old envelopes open through OpenBao with the File associated data and no row is rewritten. The T-200 start-up guards carry over to the credential folder and, as pins on public fingerprints (for imported HMAC keys the same values as T-200), to the keys in OpenBao.

## Consequences
- Staging and Production can start without a cloud provider.
- Accepted residual until T-201: anyone who gets code execution as the app user (or root on the server) can copy the signing and HMAC keys. Copied signing keys forge entitlements until the kid is rotated **and** an app release that drops it is the minimum supported version. This is why step 2 is a launch gate for paid Gold.
- The provider seam stays as it is: T-201 adds one more case to `KmsServiceCollectionExtensions.SelectProvider`. Key references carry the provider prefix (`local:`, `file:`, `openbao:`), and envelope blobs carry their key reference, so the OpenBao adapter routes old `file:` envelopes to the imported key `file-<name>`.
- With OpenBao, a code-execution bug in the API or worker can use the keys while it lasts but not copy them; destroying its `secret_id` ends it without an app release. Root on the server still reaches every key (unseal key and raft data on the same machine); that residual is unchanged and documented.
- Operators own offline backups of the key directory (two encrypted copies, never in the repository or the server's normal backup set) and the per-environment fingerprint lists.
- Windows and macOS can't run the File provider (no POSIX owner/mode check); development there keeps using `Local`.
- ADR-015's "managed KMS" assumption no longer holds for key custody; the rest of ADR-015 is unchanged.
