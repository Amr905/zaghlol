package app.zaghlol.platform.ingest

import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * FU-194: the restore's drain hold (platform-channels.md 1.4). While a hold
 * is in force no headless engine is started or reused, so nothing but the UI
 * engine can open the database while the restore swaps its files. Capture is
 * unaffected: receivers and the listener still write to the spool.
 *
 * - **Persisted** in [file] (`noBackupFilesDir/capture/drain_hold`, ASCII
 *   epoch ms of the expiry; no content), so it survives a process death
 *   mid-restore.
 * - **Expires** after at most [MAX_TTL_MS] (wall clock); an expiry more than
 *   [MAX_TTL_MS] ahead (the clock was set back) counts as expired, so a crash
 *   never stops the headless drain for longer than that.
 * - [admitEngine] and [hold] share one lock: either the hold sees the engine
 *   that was admitted ([hold] returns true) or the start sees the hold.
 */
class DrainHold(
    private val file: File,
    private val wallMs: () -> Long = System::currentTimeMillis,
) {
    private val lock = Any()
    private var untilMs: Long = load()
    private var engineActive = false

    /** True while a hold is in force (any thread). */
    fun isHeld(): Boolean = synchronized(lock) { heldLocked() }

    /** True while a headless engine exists (from its admission until its teardown). */
    fun headlessActive(): Boolean = synchronized(lock) { engineActive }

    /**
     * Sets (or renews) the hold for [ttlMs], capped to 1..[MAX_TTL_MS]. The
     * file is written first; when that fails this throws [IOException] and
     * no hold is set. Returns whether a headless engine is active now.
     */
    fun hold(ttlMs: Long): Boolean {
        val until = wallMs() + ttlMs.coerceIn(1, MAX_TTL_MS)
        persist(until)
        return synchronized(lock) {
            untilMs = until
            engineActive
        }
    }

    /** Clears the hold (idempotent). The memory hold is cleared even when the delete fails (it then throws). */
    fun release() {
        synchronized(lock) { untilMs = 0 }
        if (file.exists() && !file.delete() && file.exists()) throw IOException("drain hold not deleted")
    }

    /**
     * Main thread, right before a cycle starts or reuses an engine: false while
     * held (no engine may run), else marks the engine active until [engineGone].
     */
    fun admitEngine(): Boolean = synchronized(lock) {
        if (heldLocked()) return false
        engineActive = true
        true
    }

    /** The headless engine was torn down. */
    fun engineGone() = synchronized(lock) { engineActive = false }

    private fun heldLocked(): Boolean {
        val u = untilMs
        if (u <= 0) return false
        val now = wallMs()
        return now < u && u - now <= MAX_TTL_MS
    }

    private fun load(): Long = try {
        if (!file.exists()) 0 else file.readText(Charsets.US_ASCII).trim().toLongOrNull() ?: 0
    } catch (_: Exception) {
        0 // unreadable: not held (the hold only ever shortens to "none")
    }

    private fun persist(until: Long) {
        file.parentFile?.mkdirs()
        val tmp = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(tmp).use { out ->
            out.write(until.toString().toByteArray(Charsets.US_ASCII))
            out.fd.sync()
        }
        if (!tmp.renameTo(file)) {
            tmp.delete()
            throw IOException("drain hold not written")
        }
    }

    companion object {
        /** A hold never lasts longer than this (the restore renews it while it runs). */
        const val MAX_TTL_MS = 10 * 60_000L
        const val FILE_NAME = "drain_hold"
    }
}
