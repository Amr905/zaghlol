package app.zaghlol.platform.capture

import app.zaghlol.platform.capture.inbox.InboxReader
import app.zaghlol.platform.ingest.IngestTrace
import app.zaghlol.platform.ingest.safely
import app.zaghlol.platform.spool.CaptureStatusStore
import app.zaghlol.platform.spool.SpoolClaim
import app.zaghlol.platform.spool.SpoolStore
import app.zaghlol.platform.spool.UlidGenerator

/**
 * Production [AndroidCaptureHostApi] for one engine (UI or headless; T-039
 * design note section 6). T-041 registers one per engine; T-040 wires
 * [guardWriter] / [guardState] to T-038's `GuardRuntime`. A dependency that
 * is not wired answers `NOT_AVAILABLE` (Guard state: `unknown`).
 *
 * - [drainSpool]: oldest first under the process-wide drain claim; returns
 *   only readable entries, remembers their ids for [ackSpool].
 * - [ackSpool]: deletes only ids that are valid ULIDs **and** were returned
 *   by this host's [drainSpool] (a stray or late ack from another engine
 *   can't delete an entry it never received). Idempotent.
 * - [getSpoolStatus] / [clearSpoolAlerts]: the capture status (section 5).
 *   A lost key is reported there (`keyInvalidatedAtMs`), never thrown.
 * - [holdSpool] (T-041, FU-105): moves entries this host drained and the use
 *   case could not store even alone to `spool/held/`.
 * - The drain stops scanning after the first entry the cipher/Keystore could
 *   not read and after [DRAIN_SCAN_BUDGET_MS] (FU-104 #2); its alerts are
 *   written to the status once per drain (FU-104 #8).
 *
 * Errors: every method catches everything and throws
 * `CaptureApiError(code, null, null)`, so Pigeon never puts `toString()` or a
 * stack trace into the reply (FU-034). Nothing here logs.
 */
class AndroidCaptureHost(
    private val engineId: Long,
    private val store: SpoolStore,
    private val claim: SpoolClaim,
    private val status: CaptureStatusStore,
    private val scheduler: IngestScheduler?,
    /**
     * Validates, encrypts and writes the plaintext user part (T-038
     * `GuardRuntime.writeUser`, wired by T-040). Reports a rejection by
     * throwing `CaptureApiError(CONFIG_INVALID | IO_ERROR)`; anything else
     * becomes `IO_ERROR`.
     */
    private val guardWriter: ((ByteArray) -> Unit)?,
    private val guardState: (() -> GuardConfigState)?,
    private val device: CaptureDevice?,
    /** T-041: timing seam (devSms spike metrics); [IngestTrace.NONE] in production. */
    private val trace: () -> IngestTrace = { IngestTrace.NONE },
    /** Monotonic ms for the drain scan budget (`SystemClock.elapsedRealtime` in production). */
    private val monoClockMs: () -> Long = { System.nanoTime() / 1_000_000 },
    /** T-042 inbox reader: `InboxReaders.forUiEngine` on the UI engine, null on the headless one. */
    private val inbox: InboxReader? = null,
    /** T-044: Activity-bound actions; UI engine only (the headless host answers `NOT_AVAILABLE`). */
    private val ui: UiPermissions? = null,
) : AndroidCaptureHostApi {

    /** Ids this host's drain returned and that are not yet acked. */
    private val drained = HashSet<String>()

    override fun getCapabilities(): CaptureCapabilities = guarded { need(device).capabilities() }

    /**
     * T-044: the runtime request; the rationale UI is Flutter's. `*NoSms`
     * answers `NOT_AVAILABLE` without a system prompt. Errors are code-only.
     */
    override fun requestSmsPermission(callback: (Result<Boolean>) -> Unit) {
        val u = ui ?: return callback(Result.failure(notAvailable()))
        try {
            u.requestSms { r ->
                callback(
                    r.fold(
                        { Result.success(it) },
                        { e -> Result.failure(CaptureApiError((e as? CaptureApiError)?.code ?: IO_ERROR, null, null)) },
                    ),
                )
            }
        } catch (_: Throwable) {
            callback(Result.failure(CaptureApiError(IO_ERROR, null, null)))
        }
    }

    /** T-044: the system "Notification access" screen (the user grants it there). */
    override fun openNotificationAccessSettings(): Unit = guarded { need(ui).openNotificationAccessSettings() }

    override fun isIgnoringBatteryOptimizations(): Boolean = guarded { need(device).isIgnoringBatteryOptimizations() }

    override fun requestIgnoreBatteryOptimizations(): Unit = guarded { need(device).openBatteryOptimizationSettings() }

    override fun writeGuardConfig(userConfigJson: ByteArray): Unit = guarded {
        try {
            val writer = need(guardWriter)
            try {
                writer(userConfigJson)
            } catch (e: CaptureApiError) {
                throw CaptureApiError(if (e.code == CONFIG_INVALID) CONFIG_INVALID else IO_ERROR, null, null)
            }
        } finally {
            userConfigJson.fill(0)
        }
    }

    /**
     * T-042: allowlisted senders' inbox rows, paged. UI engine only: the
     * headless host has no [inbox] (`NOT_AVAILABLE`), so background work never
     * reads the inbox (FU-088).
     */
    override fun queryInbox(query: InboxQuery): InboxPage = guarded { need(inbox).query(query) }

    /**
     * Oldest first, at most [max] (clamped to 1..[MAX_DRAIN]). Returns an empty
     * list while another engine holds the drain claim. Entries that can't be
     * read now are skipped and kept; entries proven not authentic are deleted
     * and counted in the status (`decryptDeleted`), never returned. The scan
     * stops at the first entry the cipher/Keystore could not read (the rest
     * would fail the same way, each after the 1.3 s retry ladder) and after
     * [DRAIN_SCAN_BUDGET_MS]; what it has is returned, the rest waits for the
     * next drain (FU-104 #2).
     */
    override fun drainSpool(max: Long): List<SpoolEntry> = guarded {
        store.sweepTmp()
        if (!claim.acquire(engineId)) return@guarded emptyList()
        val limit = max.coerceIn(1, MAX_DRAIN.toLong()).toInt()
        val out = ArrayList<SpoolEntry>(limit)
        val stamps = ArrayList<Triple<String, Long, Int>>(limit)
        val scope = SpoolStore.DrainScope()
        val pending = store.pendingIds()
        // Ids that left the spool (acked by another engine after a claim
        // expiry, deleted on proof, or held) can't be acked here any more: forget them.
        synchronized(drained) { drained.retainAll(pending.toSet()) }
        val started = monoClockMs()
        try {
            for (id in pending) {
                if (out.size >= limit) break
                if (monoClockMs() - started >= DRAIN_SCAN_BUDGET_MS) break
                when (val r = store.read(id, scope)) {
                    is SpoolStore.ReadResult.Ok -> {
                        val rec = r.record
                        out += SpoolEntry(id, rec.channel, rec.source, rec.body, rec.receivedAtMs, rec.simSlot?.toLong())
                        stamps += Triple(id, rec.rxElapsedNs, rec.bootCount)
                    }
                    is SpoolStore.ReadResult.Unavailable -> if (r.keyRelated) break
                    SpoolStore.ReadResult.Deleted, SpoolStore.ReadResult.Missing -> Unit
                }
            }
        } finally {
            status.recordDrain(scope)
        }
        val ids = out.map { it.id }
        synchronized(drained) { drained.addAll(ids) }
        claim.hold(engineId, ids)
        val t = trace()
        for ((id, rxNs, boot) in stamps) t.safely { drained(id, rxNs, boot) }
        out
    }

    /** Idempotent. Dart calls it after the DB commit (or after its drain-time Guard re-check dropped the entry). */
    override fun ackSpool(ids: List<String>): Unit = guarded {
        if (ids.size > MAX_DRAIN) throw CaptureApiError(IO_ERROR, null, null)
        val own = synchronized(drained) { ids.filter { UlidGenerator.isValid(it) && it in drained }.toSet() }
        store.ack(own)
        synchronized(drained) { drained.removeAll(own) }
        claim.acked(engineId, own)
        if (own.isNotEmpty()) trace().safely { acked(own.toList()) }
    }

    /**
     * FU-105: entries this host drained that the use case could not store
     * even alone (`IngestBatchResult.kept`, after the ack of the rest). Each is
     * moved to `spool/held/` and released from the claim like an ack; an id
     * this host did not drain, or one over the held cap, is left as it is.
     * Same size rule as [ackSpool].
     */
    override fun holdSpool(ids: List<String>): Unit = guarded {
        if (ids.size > MAX_DRAIN) throw CaptureApiError(IO_ERROR, null, null)
        val own = synchronized(drained) { ids.filter { UlidGenerator.isValid(it) && it in drained }.toSet() }
        val held = HashSet<String>()
        try {
            for (id in own) if (store.hold(id)) held += id
        } finally {
            synchronized(drained) { drained.removeAll(held) }
            claim.acked(engineId, held)
        }
    }

    override fun scheduleIngestionNow(): Unit = guarded { need(scheduler).enqueue() }

    override fun getSpoolStatus(): SpoolStatus = guarded {
        val s = status.read()
        val state = try {
            guardState?.invoke() ?: GuardConfigState.UNKNOWN
        } catch (_: Exception) {
            GuardConfigState.UNKNOWN
        }
        SpoolStatus(
            pending = store.pendingCount().toLong(),
            seq = s.seq,
            refusedFull = s.refusedFull,
            refusedGeneric = s.refusedGeneric,
            rateLimited = s.rateLimited,
            missedNotifications = s.missedNotifications,
            firstMissedSmsAtMs = s.firstMissedSmsAtMs.takeIf { it >= 0 },
            decryptDeleted = s.decryptDeleted,
            keyInvalidatedAtMs = s.keyInvalidatedAtMs.takeIf { it >= 0 },
            guardState = state,
            held = store.heldCount().toLong(),
        )
    }

    override fun clearSpoolAlerts(seq: Long): Unit = guarded { status.clear(seq) }

    /** The engine is going away: drop its claim (entries stay for the next drain). */
    fun detach() {
        claim.release(engineId)
        synchronized(drained) { drained.clear() }
    }

    /** Ids this host may still ack (tests only). */
    internal fun ackableCount(): Int = synchronized(drained) { drained.size }

    private fun <T : Any> need(dep: T?): T = dep ?: throw notAvailable()

    private fun notAvailable() = CaptureApiError(NOT_AVAILABLE, null, null)

    private inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: CaptureApiError) {
        throw CaptureApiError(e.code, null, null)
    } catch (_: Throwable) {
        throw CaptureApiError(IO_ERROR, null, null)
    }

    companion object {
        const val MAX_DRAIN = 100

        /** FU-104 #2: a drain stops scanning after this long (monotonic). */
        const val DRAIN_SCAN_BUDGET_MS = 5_000L
        const val NOT_AVAILABLE = "NOT_AVAILABLE"
        const val IO_ERROR = "IO_ERROR"
        const val CONFIG_INVALID = "CONFIG_INVALID"
    }
}
