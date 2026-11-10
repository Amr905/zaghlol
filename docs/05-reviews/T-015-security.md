# T-015 Security & privacy review: database key bootstrap

- Reviewer: `security-privacy-reviewer` (Opus), 2026-11-10
- Scope: diff `origin/main...origin/task/T-015-key-bootstrap` @ `92fa7f7` (Dart, Kotlin, Swift, CI scripts, lockfile, ADR-002 amendment, security-model §3)
- CI at head: app-ci **success**, db-platform **success** (`92fa7f7`)

## Verdict: CHANGES_REQUESTED

One Medium finding (S-1) is marked **before merge**: a single native read can turn a possibly transient Keystore/Keychain failure into the D-50 wipe of all user data. The fix is small and stays inside T-015. Everything else is a follow-up.

## What is sound

- **Key generation.** `SecureKeyGenerator` (`app/lib/core/db/key_bootstrap.dart:96-120`) uses `Random.secure()` and makes 32 bytes. `UnsupportedError` maps to `KeyStoreFailed(generate)`. All-equal output is rejected on both sides of the channel (Dart `isDegenerateKey`, Kotlin/Swift `isWellFormedKey`). It is applied as a raw SQLCipher 4 key (`PRAGMA key = "x'…'"`, `cipher='sqlcipher'`, `legacy=4`) only in `_execKey` (`encrypted_open.dart:204-213`). That function drops the `SqliteException`, so `causingStatement` never carries the key (closes T-007 I-2(1)). `driftLogStatements = false`.
- **Android wrapping.** `AndroidKeystoreKek.kt:42-60`: AES-256-GCM, `PURPOSE_ENCRYPT|DECRYPT`, `setRandomizedEncryptionRequired(true)`, no user-auth binding, `setUnlockedDeviceRequired(false)`, non-exportable, StrongBox with a TEE fallback. The IV comes from the provider and its length is checked (`DbKeyStore.kt:218-219`). Every create generates a fresh KEK, so an IV can't repeat under one key. The fixed AAD `zaghlol/k_db/v1` and the version byte bind the blob. The blob is written as tmp, then fsync, then rename, and is read back and compared in constant time before a create returns. It lives in `noBackupFilesDir/keys/`, and the manifest has `allowBackup=false` plus exclude-all `dataExtractionRules`/`fullBackupContent` (T-165).
- **iOS Keychain.** `DbKeyKeychain.swift:81-102`: generic password, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable=false` set in every query, and every query names service and account, so the D-62 seat keys are never touched. Before first unlock the read returns `errSecInteractionNotAllowed`, which maps to `unavailable` and never wipes.
- **Wipe gating in Dart.** `KeyBootstrap._decide` (`key_bootstrap.dart:455-515`) reaches `KeyInvalidated` only on `notFound`/`unusable` with a database present. `unavailable`, an unlistable directory (`FileSystemException`) and a lease timeout all give `KeyUnavailable`. `_create` re-checks `anyExists()` right before it deletes or writes a key (`:529`). `DbFileSet` counts `-wal/-shm/-journal` and the restore and migrate temp files as "database present". Native `createIfAbsent` refuses to overwrite in the `unusable`/`unavailable` states.
- **Boundary hygiene.** Native errors are code-only (`SecretStoreErrors.error`), and the Dart `_guard` drops `PlatformException.message/details`. `DbKeyMaterial.toString()` is redacted, has no `==`/`hashCode`, and compares in constant time. Outcomes print only enum names. The key is never cached in a provider (`db_key_providers.dart`).
- **Cross-engine lease.** One process-wide `BootstrapLeaseManager` and one `DbKeyStore` per process on Android (`@Synchronized`) and one `NSLock` on iOS. `createIfAbsent` and `delete` require a valid lease natively.
- **Negative proofs (verified on GitHub Actions):**
  - (a) `task/T-015-proof-a2` @`4bc1696`, db-platform run 42825275660. Red on the host (`§3 table … notFound with "zaghlol.db" present → KeyInvalidated(missing)`, `Expected: <Instance of 'KeyInvalidated'>`) and on emulator API 35 (AC2).
  - (b) `task/T-015-proof-b2` @`1d7d0a9`, db-platform run 42825291865. Red: `key.log: … 7 matching` (API 26) and `5 matching` (iOS sim).
  - (c) `task/T-015-proof-c` @`667aa11`, app-ci run 42822048850. Red: `SecretStoreTests.testItemIsAfterFirstUnlockThisDeviceOnlyAndNotSynchronizable() failed`.
- **Supply chain.** The 9 new lockfile entries are `flutter_riverpod` 3.5.0, `riverpod` 3.5.0, `state_notifier`, `uuid`, `listen`, `intl`, `material_ui`, `cupertino_ui` and `flutter_localizations` (SDK). They are pure-Dart state, l10n and UI libraries. Riverpod's dependency list is async, clock, collection, `listen`, meta, stack_trace, `state_notifier`, test and `uuid`, published by dash-overflow.net. `listen` is published by flutter.dev (core-packages repo, depends only on `meta`). `material_ui`/`cupertino_ui` are the Flutter team's decoupled Material/Cupertino packages. No analytics, ads, telemetry or network code. Every entry is from pub.dev with a sha256 hash.
- **iOS device-transfer residual.** The design note §8 documents it. The key is `ThisDeviceOnly` and the database is excluded from backup (T-165). If both arrive on a new phone, only the same user's data opens there; no third party gets it. Accepted. T-165-device step 5 must record the observed behaviour.

## Findings

| ID | Severity | Before merge? | Owner |
|----|----------|---------------|-------|
| S-1 | Medium | **Yes** | T-015 |
| S-2 | Medium | No (before T-016 merges) | T-016 (contract addition) |
| S-3 | Low | No | T-008 / T-015 follow-up |
| S-4 | Low | No | CI tooling (FU) |
| S-5 | Low | No | CI tooling (FU) |
| S-6 | Low | No | FU (FU-050 family) |
| S-7 | Info | No | T-016 |
| S-8 | Info | No | Lead |

### S-1 (Medium, before merge): one failed read is treated as proof the key is gone, and that leads to a full data wipe

**Where:**
- `app/android/app/src/main/kotlin/app/zaghlol/platform/keys/DbKeyStore.kt:66-76`: `read()` retries only `UNAVAILABLE`.
- `DbKeyStore.kt:127`: `kek.get() ?: UNUSABLE`.
- `KeyErrorClassifier.kt:40`: `AEADBadTagException → UNUSABLE`.
- `app/ios/Runner/Platform/Keys/DbKeyKeychain.swift:111`: `errSecItemNotFound → notFound`.
- These feed `key_bootstrap.dart:491-508` → `KeyInvalidated`, and from there the T-016 wipe of the DB, spool and temp files.

**Leak/loss path.** The Android Keystore is not reliably deterministic on every device:
- Out-of-memory failures in the Keystore have been reported during decrypt, and the suggested remedy was to retry later. https://github.com/tink-crypto/tink-java/issues/23
- An `AEADBadTagException` has been reported even with backups disabled. https://github.com/tink-crypto/tink-java/issues/23

One `AEADBadTagException` (or a transient `null` from `getKey` while keystore2 restarts) on a launch with a database present is enough. It gives `UNUSABLE` → `KeyInvalidated(unusable)` → irreversible wipe of every transaction, with no second read. The design rule is "wipe only on clear evidence", and a single observation is not clear evidence. The same applies to iOS `-25300` on a launch while data protection is changing state.

**Required change (small):**
1. Android: in `DbKeyStore.read()`, treat `UNUSABLE` the same way as `UNAVAILABLE` for retrying. Return `UNUSABLE` only if every attempt in the existing 100/300/900 ms schedule agrees, and return `UNAVAILABLE` if any attempt disagrees. `kek.get() == null` goes through the same confirmation.
2. iOS: confirm `errSecItemNotFound` (and the wrong-length `unusable`) with the same re-read schedule before returning it.
3. Add tests. Kotlin: a KEK that throws `AEADBadTagException` once and then decrypts gives `FOUND`, and one that always throws gives `UNUSABLE` after 4 attempts. Swift: `-25300` once then success gives `found`.

Optional, recommended: on iOS, map `notFound` to `unavailable` while `UIApplication.isProtectedDataAvailable == false`.

### S-2 (Medium, owner T-016): the 30 s lease expires silently while the caller still believes it holds it

**Where:**
- `BootstrapLeaseManager.kt:14` and the Swift equivalent: TTL 30 s.
- `isValid` is checked only inside native `createIfAbsent`/`delete` (`SecretStoreHost.kt` `requireLease`).
- `key_bootstrap.dart:443-453` hands the lease to the caller on `KeyCreated`/`KeyInvalidated`. The caller then creates or wipes the database **in Dart**, which nothing gates. Dart has no API to renew or check the lease.

**Path:**
1. Engine A (UI) gets `KeyCreated(K1)`. It is then suspended for more than 30 s before it writes `zaghlol.db`. On iOS the app is backgrounded during first launch; on Android the cached-app freezer pauses a process while the clocks keep running.
2. Engine B (T-008 headless, on an incoming SMS) acquires the expired lease, sees `found` with no database, and rotates to K2 (`key_bootstrap.dart:462-470`).
3. A resumes, creates the database with K1 and stores data.
4. On the next launch SQLite returns `NOTADB`, then `reportRejected` gives `KeyInvalidated(rejectedBySqlite)`, and the database is wiped.

The same race lets two engines wipe and create concurrently. This is integrity and availability, not confidentiality.

**Required change (before T-016 merges):**
- Add `isLeaseValid(lease)` (or `renewBootstrapLease`) to `SecretStoreHostApi`.
- Expose `BootstrapLease.ensureValid()` in Dart.
- T-016 calls it right before it creates the first database file and before each wipe step, and aborts to `KeyUnavailable` if the lease has lapsed.
- Alternatively, extend the TTL on every native call made under the lease.

### S-3 (Low): K_db on iOS relies on an implicit default access group

**Where:** `DbKeyKeychain.swift:81-102`. No `kSecAttrAccessGroup` is set.

The default access group today is Runner's application identifier, which is correct. When T-008 adds a `keychain-access-groups` entitlement for the Share Extension (the `K_spool` shared group, security-model §3), `SecItemAdd` without an explicit group writes to the **first** entry of that entitlement. If the shared group is listed first, K_db becomes readable by the Share Extension. That widens the key's exposure, against "Share Extension never opens the DB".

**Required change:** set `kSecAttrAccessGroup` explicitly to `$(AppIdentifierPrefix)<bundle id>` on add and query (read the prefix from `Bundle`/entitlement at runtime). Alternatively, add an XCTest asserting the stored item's `agrp` is not the shared group. Must land before or with T-008.

### S-4 (Low): the device system-log scan is not shown to detect a leak

**Where:** `.github/scripts/db-platform-device.sh` (logcat / `log show` → `system.log`).

In proof run 42825291865 the planted `debugPrint` was caught only in the test-runner log (`key.log`). `system.log` had **0 matches** on both API 26 (13,236 lines) and the iOS simulator (1.6 M lines). The logcat ring buffer had probably rotated (the buffer-enlarging commit `501623a` was reverted in `337de8a`). The test-runner log is a valid gate: the script requires the `ZAGHLOL_KEY_SCAN` line, which proves `print` output reaches `device.log`. But the system-log half gives false comfort for native-side leaks.

Proof (b) was also run on the older two-launch layout, not on the final single-launch layout at `92fa7f7`.

**Fix:**
- Android: `adb logcat -c` before the launch, and capture logcat continuously to a file (`adb logcat -f` / background), or use `-b all -G 16M`.
- iOS: scope with `--predicate 'process == "Runner"'`.
- Re-run proof (b) on the final layout. Ideally add a native `Log.i` variant to prove the system-log half.

### S-5 (Low): the no-logging grep in app-ci has gaps

**Where:** `.github/workflows/app-ci.yml`, step "no logging in key code".

The pattern misses:
- Dart: `stdout.write*`, `stderr.write*`, `debugPrintStack`.
- Kotlin: `printStackTrace()`, `System.err`/`System.out`.
- Swift: `dump(`, `debugPrint` via `Swift.debugPrint` (covered), and calls on an injected `Logger` instance (`logger.error(`), since only `Logger(` construction is matched.

**Fix:** extend the regex and add the generated `.g.` files' error paths to a reviewed allow-list instead of excluding them wholesale.

### S-6 (Low): key copies left in native and Dart memory

These are accepted limits (design note §5), but some cheap wipes are not done:
- `SecretStoreHost.kt:49` returns the plaintext `ByteArray` to the codec and never zeroes it. It could be filled with zeros in the `main` runnable after `callback(result)` returns, since the codec has copied it by then.
- The same applies to the value returned from `createIfAbsent`.
- iOS `Data` and `FlutterStandardTypedData` (`SecretStoreHost.swift:56`) can't be wiped. Accepted.
- The Dart hex `String` and the background-isolate copy can't be wiped. Accepted and documented.

### S-7 (Info): the "found and no DB means rotate" rule depends on a stable DB directory

**Where:** `key_bootstrap.dart:462-470`.

If T-016 (or a future flavor or migration) ever points `dbDirectoryProvider` at a different directory than the one holding the existing `zaghlol.db`, the bootstrap sees "no database". It then deletes the live key, which orphans the real database.

**For T-016:** pin the path in one constant and add a test that the directory used to open the database equals the one passed to `DbFileSet`.

### S-8 (Info): negative-proof runs are not recorded

Design note §9 says the negative-proof runs are recorded in `docs/implementation-status.md`. The T-015 row is still `TODO` and no run IDs are listed. Record the run IDs above when the task is closed.

## Checklist

| Area | Result |
|------|--------|
| Data egress | No new network calls. Channel is local only. No new SDKs. Pass |
| At rest: key | CSPRNG, Keystore-wrapped / Keychain ThisDeviceOnly, not in prefs, files or backups. Pass (S-1, S-3 open) |
| Logging / crash | Code-only errors, redacted `toString`, statement logging off, CI grep plus log scan. Pass (S-4, S-5 follow-ups) |
| Permissions / manifest | No new permissions or exported components (`MainActivity` unchanged apart from the registration). Pass |
| Store policy | Not affected |
| Supply chain | 9 packages, all reputable publishers, no telemetry. Pass |

## Re-review (delta) — `git diff 92fa7f7 d4559c3` (Sonnet)

Evidence: PC runner PASS at d4559c3; GitHub app-ci 42841743318 success (incl. Swift unit tests). db-platform for this SHA was cancelled by an infra stop; it runs in the batch CI.

**S-1: resolved on both platforms.** Android `DbKeyStore.read` and iOS `readLocked` retry every non-found result on the 100/300/900 ms schedule. One `found` wins at once. UNUSABLE/unusable (and iOS notFound) are returned only when every attempt agrees. Any disagreement returns UNAVAILABLE, which never wipes. Tests exist on both sides: one failure then success returns the key, consistent failure is unusable/notFound, and mixed outcomes are unavailable. Two accepted asymmetries:
- Android NOT_FOUND returns on the first attempt. It rests on `Files.notExists` (a NoSuchFile result from the file system), not on the Keystore, so the transient Keystore failure that S-1 was about cannot produce it. A locked or unreadable directory gives UNKNOWN, not ABSENT.
- iOS `createIfAbsent` reads with `confirmNotFound: false`. A false notFound there cannot overwrite, because `SecItemAdd` returns `errSecDuplicateItem` and the winner is read back. `read()`, the path that can lead to a wipe, uses the confirmed read.

**M-1 (security view):** resolved. `createFresh` (which deletes the Keystore alias) is reached only after two ABSENT probes; UNKNOWN throws `KeyStoreFailure`.

**S-3: resolved.** Every query, add and delete on iOS names `kSecAttrAccessGroup` = `<AppIdentifierPrefix><bundle id>`, resolved by `resolveAccessGroup`. A prefix that is empty or still contains `$(` (unsigned build) gives nil, so the attribute is omitted and the item stays in the only group the app has. Tests assert the group on every call. A future `keychain-access-groups` entitlement (T-008) can no longer move K_db into a shared group. The default group is the same as the old implicit one, so items written by earlier builds still match. If a simulator build ever returns `errSecMissingEntitlement` for the pinned group, the result is unavailable (no wipe), a test-environment issue and not a security one.

**Info.plist change:** it adds only `AppIdentifierPrefix = $(AppIdentifierPrefix)`. That expands to the Team ID, which is not a secret (it is in the code signature and the provisioning profile). It requests no entitlement, permission or URL scheme and does not weaken anything.

**S-6: resolved.** `SecretStoreHost.dispatch` takes a `wipe` hook that runs in a `finally` after the Pigeon callback returns (the reply encodes the value synchronously inside the callback). It zeroes `SecretReadMsg.value` and the `createIfAbsent` result, and the input `candidate` is already zeroed in `finally`. The internal `plain` and read-back arrays in `DbKeyStore` were already zeroed. Residual: Pigeon's own encoded reply buffer and the Dart-side copy are outside this task (the Dart side zeroizes after first open, per the security model).

**New findings at Medium or above:** none. Low/Info follow-ups only: the iOS fresh-install read costs about 1.3 s (n-5 above); nothing else.

### Final verdict (security): APPROVED
