# Batch 63 review

## T-229 (C1) — APPROVED
Digest pins appended as `image:tag@sha256:...` in backend-ci, backend-monsterasp, backend-server-kit; only the image token changed on each line, YAML structure and continuations intact. No syntax problem.

## T-230 (C2 native) — APPROVED
Checked: boot receiver `exported=false`, filters only BOOT_COMPLETED and re-checks the action; store holds id, time and Dart-redacted String/Int fields only, in `noBackupFilesDir/notif`; `schedule` adds, fire/show/cancel/cancelScheduled/cancelAll remove or clear (covers FU-267 re-derive, T-228 paid-bill cancel, delete-all); past-due dropped, no burst; LOCKED_BOOT not used (store is credential-protected, so it re-arms after unlock; documented). Notification tests green; app-ci green at f6a865b1.

Minors (proposed FU-291, none block):
1. `ScheduleBook.kt` `FileScheduleStore.save`: `writeText` is not atomic (a kill mid-write truncates the file and loses all pending entries). Write to a temp file then rename.
2. `@Synchronized` is per `ScheduleBook` instance; the presenter, alarm receiver and boot receiver each build their own, so there is no cross-instance lock (read-modify-write race on rare overlap). Use a shared lock (companion object) or a process-wide singleton.
3. `AndroidManifest.xml` top comment still says "no RECEIVE_BOOT_COMPLETED"; now stale.
4. Corrupt lines are silently skipped and dropped on next save (acceptable, noted).

## Lead delta check
FU-291 minors fixed in the batch: `ScheduleBook` uses one process-wide lock (companion object) instead of per-instance `@Synchronized`; `FileScheduleStore.save` writes a temp file and renames it; manifest header comment corrected. New Kotlin test: 8 threads over two books on one file write 200 entries with no lost entry and no temp file left. Verified by app-ci on the batch branch.
